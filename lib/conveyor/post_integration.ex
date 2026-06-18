defmodule Conveyor.PostIntegration do
  @moduledoc """
  Conservative post-integration patch-equivalence check.

  Phase 1 records manual external integration. This service compares the accepted
  patch captured by Conveyor with the patch at the human-provided external commit
  and records both an `ExternalChange` summary and detailed `PatchEquivalence`.
  """

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.ExternalChange
  alias Conveyor.Factory.HumanApproval
  alias Conveyor.Factory.PatchEquivalence
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            human_approval: HumanApproval.t(),
            external_change: ExternalChange.t(),
            patch_equivalence: PatchEquivalence.t(),
            done_eligible?: boolean()
          }

    @enforce_keys [:human_approval, :external_change, :patch_equivalence, :done_eligible?]
    defstruct [:human_approval, :external_change, :patch_equivalence, :done_eligible?]
  end

  @done_eligible [:exact, :equivalent_with_human_edits]

  @spec check!(Ecto.UUID.t(), keyword()) :: Result.t()
  def check!(human_approval_id, opts \\ []) when is_binary(human_approval_id) do
    approval = get_by_id!(HumanApproval, human_approval_id)
    run_attempt = get_by_id!(RunAttempt, approval.run_attempt_id)
    project = project_for!(run_attempt.slice_id)
    patch_set = latest_patch_set!(run_attempt.id)
    accepted_patch = BlobStore.read!(patch_set.patch_ref, blob_root: blob_root(opts))

    external_patch =
      external_patch!(project.local_path, run_attempt.base_commit, approval.external_commit)

    external_patch_sha256 = raw_sha256(external_patch)
    external_files = changed_files(external_patch)
    accepted_files = changed_files(accepted_patch)
    extra_files = external_files -- accepted_files
    protected_paths = protected_paths(extra_files, Keyword.get(opts, :protected_path_globs, []))
    accepted_hunks_present? = accepted_hunks_present?(accepted_patch, external_patch)

    equivalence =
      classify_equivalence(
        accepted_patch,
        external_patch,
        accepted_hunks_present?,
        extra_files,
        protected_paths
      )

    verification_status = if equivalence in @done_eligible, do: :passed, else: :failed

    external_change =
      Ash.create!(
        ExternalChange,
        %{
          human_approval_id: approval.id,
          run_attempt_id: run_attempt.id,
          external_commit: approval.external_commit,
          external_patch_sha256: external_patch_sha256,
          equivalence: equivalence,
          human_edit_summary: human_edit_summary(equivalence, extra_files, protected_paths),
          verification_status: verification_status
        },
        domain: Factory
      )

    patch_equivalence =
      Ash.create!(
        PatchEquivalence,
        %{
          external_change_id: external_change.id,
          accepted_patch_sha256: patch_set.patch_sha256,
          external_patch_sha256: external_patch_sha256,
          normalized_patch_id: normalized_patch_id(accepted_patch, external_patch),
          accepted_hunks_present: accepted_hunks_present?,
          extra_files_changed: extra_files,
          protected_paths_changed: protected_paths,
          equivalence: equivalence,
          rationale: rationale(equivalence, accepted_hunks_present?, extra_files, protected_paths)
        },
        domain: Factory
      )

    updated_approval =
      Ash.update!(
        approval,
        %{equivalence_decision: equivalence},
        domain: Factory
      )

    %Result{
      human_approval: updated_approval,
      external_change: external_change,
      patch_equivalence: patch_equivalence,
      done_eligible?: equivalence in @done_eligible
    }
  end

  defp blob_root(opts), do: Keyword.get(opts, :blob_root, ".conveyor/blobs")

  defp external_patch!(repo, base_commit, external_commit) do
    git!(repo, ["diff", base_commit, external_commit])
  end

  defp classify_equivalence(accepted_patch, external_patch, true, [], []) do
    if normalize_patch(accepted_patch) == normalize_patch(external_patch) do
      :exact
    else
      :equivalent_with_human_edits
    end
  end

  defp classify_equivalence(_accepted_patch, _external_patch, true, _extra_files, []) do
    :equivalent_with_human_edits
  end

  defp classify_equivalence(
         _accepted_patch,
         _external_patch,
         true,
         _extra_files,
         _protected_paths
       ) do
    :partial
  end

  defp classify_equivalence(
         _accepted_patch,
         _external_patch,
         false,
         _extra_files,
         _protected_paths
       ) do
    :divergent
  end

  defp accepted_hunks_present?(accepted_patch, external_patch) do
    accepted = normalize_patch(accepted_patch)
    external = normalize_patch(external_patch)

    accepted != "" and (accepted == external or String.contains?(external, accepted))
  end

  defp normalize_patch(patch) do
    patch
    |> String.split("\n")
    |> Enum.reject(&String.starts_with?(&1, "index "))
    |> Enum.reject(&String.starts_with?(&1, "\\ No newline"))
    |> Enum.join("\n")
    |> String.trim()
  end

  defp changed_files(patch) do
    ~r/^diff --git a\/(.+?) b\/(.+)$/m
    |> Regex.scan(patch)
    |> Enum.map(fn [_line, _from, to] -> to end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp protected_paths(files, globs) do
    Enum.filter(files, fn file ->
      Enum.any?(globs, &glob_match?(file, &1))
    end)
  end

  defp glob_match?(file, glob) do
    cond do
      String.ends_with?(glob, "/**") ->
        prefix = String.trim_trailing(glob, "/**")
        file == prefix or String.starts_with?(file, prefix <> "/")

      String.contains?(glob, "*") ->
        regex =
          glob
          |> Regex.escape()
          |> String.replace("\\*", "[^/]*")
          |> then(&Regex.compile!("^#{&1}$"))

        Regex.match?(regex, file)

      true ->
        file == glob
    end
  end

  defp human_edit_summary(:exact, _extra_files, _protected_paths),
    do: "External patch matches accepted patch."

  defp human_edit_summary(:equivalent_with_human_edits, extra_files, _protected_paths) do
    "Accepted hunks are present with unprotected human edits: #{Enum.join(extra_files, ", ")}"
  end

  defp human_edit_summary(:partial, _extra_files, protected_paths) do
    "Accepted hunks are present but protected paths changed: #{Enum.join(protected_paths, ", ")}"
  end

  defp human_edit_summary(:divergent, _extra_files, _protected_paths) do
    "External patch does not contain the accepted patch hunks."
  end

  defp rationale(equivalence, accepted_hunks_present?, extra_files, protected_paths) do
    %{
      equivalence: equivalence,
      accepted_hunks_present: accepted_hunks_present?,
      extra_files_changed: extra_files,
      protected_paths_changed: protected_paths
    }
    |> Jason.encode!()
  end

  defp normalized_patch_id(accepted_patch, external_patch) do
    "normalized:" <>
      raw_sha256(normalize_patch(accepted_patch) <> "\n---\n" <> normalize_patch(external_patch))
  end

  defp latest_patch_set!(run_attempt_id) do
    PatchSet
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt_id))
    |> Enum.sort_by(&DateTime.to_unix(&1.generated_at, :microsecond), :desc)
    |> List.first()
    |> case do
      nil -> raise ArgumentError, "run attempt #{run_attempt_id} has no accepted PatchSet"
      patch_set -> patch_set
    end
  end

  defp project_for!(slice_id) do
    slice = get_by_id!(Slice, slice_id)
    epic = get_by_id!(Epic, slice.epic_id)
    plan = get_by_id!(Plan, epic.plan_id)
    get_by_id!(Project, plan.project_id)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp git!(repo, args) do
    case System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git #{Enum.join(args, " ")} failed with #{status}: #{output}"
    end
  end

  defp raw_sha256(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
