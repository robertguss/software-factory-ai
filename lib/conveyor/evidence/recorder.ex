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
  alias Conveyor.Security.Redactor

  @schema_version "conveyor.evidence_packet@1"

  defmodule Result do
    @moduledoc false
    @type t :: %__MODULE__{
            evidence: Evidence.t(),
            projection: Projector.Result.t(),
            artifacts: [Artifact.t()],
            security_findings: [map()]
          }
    @enforce_keys [:evidence, :projection]
    defstruct [:evidence, :projection, :artifacts, security_findings: []]
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
    redaction_policy = Keyword.get(opts, :redaction_policy, :redact)
    acceptance = AcceptanceMapper.map!(acceptance_criteria, verification_result)
    diff = BlobStore.read!(patch_set.patch_ref, blob_opts)
    logs_json = logs_json(verification_result)

    initial_security_findings =
      [
        artifact_spec("manifest", "text/markdown", "dossier.md", fn ->
          dossier_markdown(run_attempt, patch_set, acceptance, [])
        end),
        artifact_spec("diff", "text/x-diff", "diff.patch", diff),
        artifact_spec("log", "application/json", "logs/verification.json", logs_json)
      ]
      |> security_findings(redaction_policy)

    evidence_json =
      evidence_json(
        run_attempt,
        patch_set,
        acceptance,
        verification_result,
        initial_security_findings,
        redaction_policy
      )

    dossier = dossier_markdown(run_attempt, patch_set, acceptance, initial_security_findings)

    artifact_specs = [
      artifact_spec(
        "evidence",
        "application/json",
        "evidence.json",
        evidence_json
      ),
      artifact_spec("manifest", "text/markdown", "dossier.md", dossier),
      artifact_spec("diff", "text/x-diff", "diff.patch", diff),
      artifact_spec("log", "application/json", "logs/verification.json", logs_json)
    ]

    redacted_artifacts = Enum.map(artifact_specs, &redact_artifact(&1, redaction_policy))
    security_findings = Enum.flat_map(redacted_artifacts, & &1.redaction.findings)
    security_blocked? = Enum.any?(redacted_artifacts, & &1.redaction.blocked?)

    artifacts =
      Enum.map(redacted_artifacts, fn artifact ->
        write_artifact!(run_attempt, artifact, blob_opts)
      end)

    evidence =
      upsert_evidence!(
        run_attempt,
        patch_set,
        acceptance,
        "diff.patch",
        security_findings,
        security_blocked?
      )

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

    %Result{
      evidence: evidence,
      projection: projection,
      artifacts: artifacts,
      security_findings: security_findings
    }
  end

  defp artifact_spec(kind, media_type, projection_path, content_fun)
       when is_function(content_fun, 0) do
    artifact_spec(kind, media_type, projection_path, content_fun.())
  end

  defp artifact_spec(kind, media_type, projection_path, content) do
    %{
      kind: kind,
      media_type: media_type,
      projection_path: projection_path,
      content: content
    }
  end

  defp security_findings(artifact_specs, redaction_policy) do
    artifact_specs
    |> Enum.flat_map(fn artifact ->
      Redactor.scan(artifact.content, source: artifact.projection_path, policy: redaction_policy)
    end)
  end

  defp redact_artifact(artifact, redaction_policy) do
    Map.put(
      artifact,
      :redaction,
      Redactor.redact!(artifact.content,
        source: artifact.projection_path,
        policy: redaction_policy
      )
    )
  end

  defp evidence_json(
         run_attempt,
         patch_set,
         acceptance,
         verification_result,
         security_findings,
         redaction_policy
       ) do
    %{
      "schema_version" => @schema_version,
      "run_attempt_id" => run_attempt.id,
      "patch_set_id" => patch_set.id,
      "status" => evidence_status(acceptance, security_findings),
      "acceptance_results" => acceptance.acceptance_results,
      "findings" => acceptance.findings,
      "security" => security_summary(security_findings, redaction_policy),
      "verification" => normalize(verification_result)
    }
    |> canonical_json()
  end

  defp dossier_markdown(run_attempt, patch_set, acceptance, security_findings) do
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

    ## Security

    #{security_lines(security_findings)}
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

  defp upsert_evidence!(
         run_attempt,
         patch_set,
         acceptance,
         diff_ref,
         security_findings,
         security_blocked?
       ) do
    attrs = %{
      run_attempt_id: run_attempt.id,
      patch_set_id: patch_set.id,
      changed_files: patch_set.changed_files,
      diff_ref: diff_ref,
      tool_invocation_refs: [],
      acceptance_results: acceptance.acceptance_results,
      risks: acceptance.findings ++ security_findings,
      summary: summary(acceptance, security_blocked?)
    }

    case existing_evidence(run_attempt.id, patch_set.id) do
      nil -> Ash.create!(Evidence, attrs, domain: Factory)
      evidence -> Ash.update!(evidence, attrs, domain: Factory)
    end
  end

  defp write_artifact!(
         run_attempt,
         %{
           kind: kind,
           media_type: media_type,
           projection_path: projection_path,
           redaction: redaction
         },
         blob_opts
       ) do
    blob = BlobStore.write!(redaction.content, blob_opts)

    attrs = %{
      run_attempt_id: run_attempt.id,
      kind: kind,
      media_type: media_type,
      projection_path: projection_path,
      blob_ref: blob.ref,
      sha256: blob.sha256,
      raw_sha256: redaction.raw_sha256,
      redacted_sha256: redaction.redacted_sha256,
      redaction_findings: redaction.findings,
      size_bytes: blob.size_bytes,
      subject_kind: "run_attempt",
      producer: "evidence-recorder",
      schema_version: @schema_version,
      sensitivity: redaction.sensitivity
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

  defp evidence_status(acceptance, security_findings) when is_list(security_findings) do
    cond do
      Enum.any?(security_findings, &(&1["severity"] == "blocking")) -> "blocked"
      security_findings != [] and acceptance.status == :passed -> "redacted"
      true -> Atom.to_string(acceptance.status)
    end
  end

  defp evidence_status(acceptance, _security_findings), do: Atom.to_string(acceptance.status)

  defp security_summary(security_findings, redaction_policy) do
    %{
      "policy" => Atom.to_string(redaction_policy),
      "status" => security_status(security_findings),
      "findings" => security_findings
    }
  end

  defp security_status([]), do: "clear"

  defp security_status(security_findings) do
    if Enum.any?(security_findings, &(&1["severity"] == "blocking")) do
      "blocked"
    else
      "redacted"
    end
  end

  defp security_lines([]), do: "- none"

  defp security_lines(security_findings) do
    Enum.map_join(security_findings, "\n", fn finding ->
      "- #{finding["severity"]}: #{finding["classifier"]} in #{finding["source"]}"
    end)
  end

  defp summary(_acceptance, true), do: "Security redaction found blocking secret exposure."

  defp summary(%{status: :passed}, false), do: "Acceptance and verification evidence passed."

  defp summary(_acceptance, false),
    do: "Acceptance and verification evidence has blocking findings."

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
