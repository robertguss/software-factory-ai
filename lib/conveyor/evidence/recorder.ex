defmodule Conveyor.Evidence.Recorder do
  @moduledoc """
  Writes machine evidence, dossier, diff, logs, and projected run artifacts.
  """

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Artifacts.Projector
  alias Conveyor.Evidence.AcceptanceMapper
  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.Evidence
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.RunAttemptLifecycle

  @schema_version "conveyor.evidence_packet@1"

  defmodule Result do
    @moduledoc false
    @type t :: %__MODULE__{
            evidence: Evidence.t(),
            projection: Projector.Result.t(),
            artifacts: [Artifact.t()]
          }
    @enforce_keys [:evidence, :projection]
    defstruct [:evidence, :projection, :artifacts]
  end

  @spec record!(RunAttempt.t(), PatchSet.t(), [map()], map() | struct(), keyword()) :: Result.t()
  def record!(
        %RunAttempt{} = run_attempt,
        %PatchSet{} = patch_set,
        acceptance_criteria,
        verification_result,
        opts \\ []
      ) do
    blob_opts = Keyword.take(opts, [:blob_root])
    acceptance = AcceptanceMapper.map!(acceptance_criteria, verification_result)
    evidence_json = evidence_json(run_attempt, patch_set, acceptance, verification_result)
    dossier = dossier_markdown(run_attempt, patch_set, acceptance)
    diff = BlobStore.read!(patch_set.patch_ref, blob_opts)
    logs_json = logs_json(verification_result)

    artifacts = [
      write_artifact!(
        run_attempt,
        "evidence",
        "application/json",
        "evidence.json",
        evidence_json,
        blob_opts
      ),
      write_artifact!(run_attempt, "manifest", "text/markdown", "dossier.md", dossier, blob_opts),
      write_artifact!(run_attempt, "diff", "text/x-diff", "diff.patch", diff, blob_opts),
      write_artifact!(
        run_attempt,
        "log",
        "application/json",
        "logs/verification.json",
        logs_json,
        blob_opts
      )
    ]

    evidence = upsert_evidence!(run_attempt, patch_set, acceptance, "diff.patch")

    run_attempt =
      if run_attempt.status == :running do
        RunAttemptLifecycle.transition!(run_attempt, :record_evidence, actor: "evidence-recorder")
      else
        run_attempt
      end

    projection =
      Projector.project_run!(run_attempt,
        blob_root: Keyword.get(opts, :blob_root, ".conveyor/blobs"),
        projection_root: Keyword.get(opts, :projection_root, ".conveyor/runs")
      )

    %Result{evidence: evidence, projection: projection, artifacts: artifacts}
  end

  defp evidence_json(run_attempt, patch_set, acceptance, verification_result) do
    %{
      "schema_version" => @schema_version,
      "run_attempt_id" => run_attempt.id,
      "patch_set_id" => patch_set.id,
      "status" => Atom.to_string(acceptance.status),
      "acceptance_results" => acceptance.acceptance_results,
      "findings" => acceptance.findings,
      "verification" => normalize(verification_result)
    }
    |> canonical_json()
  end

  defp dossier_markdown(run_attempt, patch_set, acceptance) do
    results =
      acceptance.acceptance_results
      |> Enum.map_join("\n", fn result ->
        "- #{result["id"]}: #{result["evidence_status"]}"
      end)

    findings =
      acceptance.findings
      |> Enum.map_join("\n", fn finding ->
        "- #{finding["severity"]}: #{finding["category"]} #{finding["test_ref"] || ""}"
      end)

    """
    # Run Dossier

    RunAttempt: #{run_attempt.id}
    PatchSet: #{patch_set.id}
    Status: #{acceptance.status}

    ## Acceptance

    #{results}

    ## Findings

    #{if findings == "", do: "- none", else: findings}
    """
    |> String.trim()
    |> Kernel.<>("\n")
  end

  defp logs_json(verification_result) do
    %{
      "schema_version" => "conveyor.verification_log@1",
      "verification" => normalize(verification_result)
    }
    |> canonical_json()
  end

  defp upsert_evidence!(run_attempt, patch_set, acceptance, diff_ref) do
    attrs = %{
      run_attempt_id: run_attempt.id,
      patch_set_id: patch_set.id,
      changed_files: patch_set.changed_files,
      diff_ref: diff_ref,
      tool_invocation_refs: [],
      acceptance_results: acceptance.acceptance_results,
      risks: acceptance.findings,
      summary: summary(acceptance)
    }

    case existing_evidence(run_attempt.id, patch_set.id) do
      nil -> Ash.create!(Evidence, attrs, domain: Factory)
      evidence -> Ash.update!(evidence, attrs, domain: Factory)
    end
  end

  defp write_artifact!(run_attempt, kind, media_type, projection_path, content, blob_opts) do
    blob = BlobStore.write!(content, blob_opts)

    attrs = %{
      run_attempt_id: run_attempt.id,
      kind: kind,
      media_type: media_type,
      projection_path: projection_path,
      blob_ref: blob.ref,
      sha256: blob.sha256,
      size_bytes: blob.size_bytes,
      subject_kind: "run_attempt",
      producer: "evidence-recorder",
      schema_version: @schema_version,
      sensitivity: :internal
    }

    case existing_artifact(run_attempt.id, projection_path) do
      nil -> Ash.create!(Artifact, attrs, domain: Factory)
      artifact -> Ash.update!(artifact, attrs, domain: Factory)
    end
  end

  defp existing_artifact(run_attempt_id, projection_path) do
    Artifact
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.run_attempt_id == run_attempt_id and &1.projection_path == projection_path))
  end

  defp existing_evidence(run_attempt_id, patch_set_id) do
    Evidence
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.run_attempt_id == run_attempt_id and &1.patch_set_id == patch_set_id))
  end

  defp summary(%{status: :passed}), do: "Acceptance and verification evidence passed."
  defp summary(_acceptance), do: "Acceptance and verification evidence has blocking findings."

  defp normalize(%{suites: suites}), do: %{"suites" => suites}
  defp normalize(value), do: value

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)
end
