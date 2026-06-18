defmodule Conveyor.Gate.Stages.SecretSafety do
  @moduledoc """
  Gate stage 5: verifies that gate-visible artifacts contain no unredacted secrets.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Gate.StageResult
  alias Conveyor.Security.Redactor

  @impl true
  def run(context, _opts \\ []) do
    redaction_policy = value(context, :redaction_policy) || :block
    allow_redacted? = value(context, :allow_redacted_continuation) != false

    findings =
      context
      |> existing_findings()
      |> Kernel.++(artifact_findings(value(context, :artifacts) || []))
      |> Kernel.++(
        scan_content_findings(value(context, :artifact_contents) || [], redaction_policy)
      )
      |> normalize_findings(allow_redacted?)

    %StageResult{
      key: "secret_safety",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(context),
      input_digests: %{
        "redaction_policy" => Atom.to_string(redaction_policy),
        "finding_count" => length(findings)
      }
    }
  end

  defp existing_findings(context) do
    (value(context, :security_findings) || []) ++ evidence_risks(value(context, :evidence))
  end

  defp evidence_risks(nil), do: []
  defp evidence_risks(evidence), do: value(evidence, :risks) || []

  defp artifact_findings(artifacts) do
    artifacts
    |> Enum.flat_map(fn artifact ->
      findings = value(artifact, :redaction_findings) || []

      if value(artifact, :sensitivity) in [:quarantined, "quarantined"] and findings == [] do
        [
          %{
            "category" => "secret_exposure",
            "severity" => "blocking",
            "source" => value(artifact, :projection_path),
            "policy" => "block"
          }
        ]
      else
        findings
      end
    end)
  end

  defp scan_content_findings(contents, redaction_policy) do
    Enum.flat_map(contents, fn content ->
      source = value(content, :source) || value(content, :projection_path) || "artifact"
      body = value(content, :content) || ""
      Redactor.scan(body, source: source, policy: redaction_policy)
    end)
  end

  defp normalize_findings(findings, allow_redacted?) do
    findings
    |> Enum.filter(&secret_finding?/1)
    |> Enum.map(&normalize_finding(&1, allow_redacted?))
  end

  defp secret_finding?(finding), do: value(finding, :category) == "secret_exposure"

  defp normalize_finding(finding, allow_redacted?) do
    severity = value(finding, :severity)
    policy = value(finding, :policy)

    blocking? =
      severity == "blocking" or policy == "block" or
        (severity == "warning" and not allow_redacted?)

    finding
    |> Map.put("category", "unredacted_secret")
    |> Map.put("severity", if(blocking?, do: "blocking", else: "warning"))
    |> Map.put_new("message", message(blocking?))
  end

  defp message(true),
    do: "Gate-visible artifact contains an unredacted or blocking secret finding."

  defp message(false), do: "Gate-visible artifact was redacted and may continue by policy."

  defp status(findings) do
    if Enum.any?(findings, &(&1["severity"] == "blocking")), do: :failed, else: :passed
  end

  defp evidence_refs(context) do
    artifact_refs =
      context
      |> value(:artifacts)
      |> List.wrap()
      |> Enum.map(&value(&1, :projection_path))

    content_refs =
      context
      |> value(:artifact_contents)
      |> List.wrap()
      |> Enum.map(&(value(&1, :source) || value(&1, :projection_path)))

    (artifact_refs ++ content_refs)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
