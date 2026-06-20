defmodule Conveyor.Eval.GateContext do
  @moduledoc """
  Assembles the gate `context` for a completed `RunSlice` from the data the pipeline
  **already produces** — the seed of the missing slice→gate conductor.

  The integration audit showed only 3/14 gate stages pass on the bare eval context
  (`verification_result` + calibration); the rest fail-closed for lack of inputs that
  the run actually has but never threaded. `assemble/4` threads them: the captured
  `PatchSet`, the workspace tree hash, a real build/install check, the acceptance
  mapping (from the brief + verification result), the provenance digests (from the
  RunSpec), and a minimal content-addressed RunBundle — taking the gate to **9/14**
  (adds `workspace_integrity`, `policy_compliance`, `build_install`,
  `acceptance_mapping`, `provenance_attestation`, `run_check`). That is the wiring
  ceiling: the remaining 5 — `contract_lock` / `diff_scope` / `observed_risk` /
  `reviewer_aggregation` / `canary_freshness` — need subsystems that don't exist yet
  (the Contract Forge, diff/review policies, a review pipeline, canary health) and stay
  fail-closed by design.
  """

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Eval.Workspace
  alias Conveyor.Factory
  alias Conveyor.Factory.PatchSet

  @calibration %{status: :valid, expected_failures: ["acceptance_red_on_base"]}

  @doc """
  Build the richest honest gate context from a slice result. `opts`: `:workspace_path`
  (required), `:agent_brief`, `:run_prompt`.
  """
  @spec assemble(struct(), struct(), struct(), keyword()) :: map()
  def assemble(slice, run_attempt, run_spec, opts) do
    ws = Keyword.fetch!(opts, :workspace_path)
    brief = Keyword.get(opts, :agent_brief)
    run_prompt = Keyword.get(opts, :run_prompt)
    verification_result = slice.output["verification_result"]
    patch_set = load_patch_set(slice.output["patch_set_id"])
    bundle = run_bundle(run_attempt, verification_result)

    %{
      # core (already passed: test_execution, secret_safety)
      verification_result: verification_result,
      test_pack_calibration: @calibration,
      # workspace_integrity
      patch_set: patch_set,
      run_spec: run_spec,
      run_attempt: run_attempt,
      run_attempt_id: run_attempt.id,
      head_tree_sha256: head_tree_sha256(ws),
      # build_install
      build_install_result: build_install_result(ws),
      # acceptance_mapping
      agent_brief: brief,
      acceptance_criteria: brief && brief.acceptance_criteria,
      # provenance_attestation (digests from the real RunSpec + PatchSet + RunPrompt)
      patch_sha256: patch_set && patch_set.patch_sha256,
      base_commit: run_attempt.base_commit,
      container_image_digest: run_spec.container_image_digest,
      test_pack_sha256: run_spec.test_pack_sha256,
      run_spec_sha256: run_spec.run_spec_sha256,
      policy_sha256: run_spec.policy_sha256,
      prompt_sha256: run_prompt && run_prompt.body_sha256,
      provenance_subjects: provenance_subjects(patch_set, verification_result),
      # run_check: a minimal content-addressed RunBundle (dossier + verification log +
      # manifest), hashed exactly as the stage expects. Productionizing this is the
      # Artifacts.Projector's job; this is the audit-scoped seed.
      artifacts: bundle.artifacts,
      artifact_contents: bundle.contents,
      manifest: bundle.manifest,
      run_bundle: bundle.run_bundle
    }
  end

  defp load_patch_set(nil), do: nil

  defp load_patch_set(id) do
    PatchSet |> Ash.read!(domain: Factory) |> Enum.find(&(&1.id == id))
  end

  # A genuine, deterministic digest of the (post-fix) workspace tree.
  defp head_tree_sha256(ws) do
    System.cmd("git", ["-C", ws, "add", "-A"], stderr_to_stdout: true)

    case System.cmd("git", ["-C", ws, "write-tree"], stderr_to_stdout: true) do
      {tree, 0} ->
        "sha256:" <> Base.encode16(:crypto.hash(:sha256, String.trim(tree)), case: :lower)

      _ ->
        nil
    end
  end

  # Real build/install evidence: import the app under the sample's venv.
  defp build_install_result(ws) do
    argv = ["-c", "import tasks_service.main"]

    {output, exit_code} =
      case Workspace.venv_opts()[:venv_bin] do
        nil -> {"no venv", 127}
        bin -> System.cmd(Path.join(bin, "python"), argv, cd: ws, stderr_to_stdout: true)
      end

    %{
      "status" => if(exit_code == 0, do: "passed", else: "failed"),
      "commands" => [
        %{
          "argv" => ["python" | argv],
          "exit_code" => exit_code,
          "stdout" => output,
          "stderr" => ""
        }
      ]
    }
  end

  defp provenance_subjects(nil, _vr), do: []

  defp provenance_subjects(patch_set, verification_result) do
    [
      %{"name" => "diff.patch", "digest" => %{"sha256" => strip(patch_set.patch_sha256)}},
      %{
        "name" => "evidence.json",
        "digest" => %{"sha256" => strip(verification_result["result_digest"])}
      }
    ]
  end

  # A minimal, content-addressed RunBundle: a dossier + the verification log, plus a
  # manifest whose root/entry digests are computed exactly as RunCheck recomputes them.
  defp run_bundle(run_attempt, verification_result) do
    dossier =
      "# Run Dossier\n\nrun_attempt: #{run_attempt.id}\nverdict: #{verification_result["status"]}\n"

    vlog =
      Jason.encode!(%{
        "schema_version" => "conveyor.verification_log@1",
        "verification" => verification_result
      })

    specs = [
      {"dossier.md", "evidence_packet", "conveyor.evidence_packet@1", dossier},
      {"logs/verification.json", "log", "conveyor.verification_log@1", vlog}
    ]

    artifacts =
      Enum.map(specs, fn {path, kind, schema_version, content} ->
        %{
          projection_path: path,
          kind: kind,
          schema_version: schema_version,
          sha256: sha256(content),
          size_bytes: byte_size(content),
          sensitivity: :internal
        }
      end)

    entries = Enum.map(artifacts, &manifest_entry/1)

    manifest = %{
      "schema_version" => "conveyor.run_bundle@1",
      "run_attempt_id" => run_attempt.id,
      "entries" => entries,
      "bundle_root_sha256" => bundle_root_sha256(entries)
    }

    %{
      artifacts: artifacts,
      contents:
        Enum.map(specs, fn {path, _k, _s, content} ->
          %{projection_path: path, content: content}
        end),
      manifest: manifest,
      run_bundle: %{
        "manifest_ref" => "manifest.json",
        "manifest_sha256" => sha256(canonical_json(manifest)),
        "bundle_root_sha256" => bundle_root_sha256(entries),
        "schema_version" => "conveyor.run_bundle@1"
      }
    }
  end

  defp manifest_entry(artifact) do
    %{
      "path" => artifact.projection_path,
      "kind" => artifact.kind,
      "sha256" => artifact.sha256,
      "size_bytes" => artifact.size_bytes,
      "sensitivity" => Atom.to_string(artifact.sensitivity),
      "schema_version" => artifact.schema_version
    }
  end

  defp bundle_root_sha256(entries) do
    entries
    |> Enum.map(
      &Map.take(&1, ["path", "kind", "sha256", "size_bytes", "sensitivity", "schema_version"])
    )
    |> canonical_json()
    |> sha256()
  end

  # Mirrors Conveyor.Gate.Stages.RunCheck.canonical_json/1 exactly (sorted keys).
  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map_join(",", fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value), do: Jason.encode!(value)

  defp sha256(content), do: BlobStore.sha256(content)

  defp strip("sha256:" <> rest), do: rest
  defp strip(other), do: other
end
