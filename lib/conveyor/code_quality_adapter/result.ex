defmodule Conveyor.CodeQualityAdapter.Result do
  @moduledoc """
  Structured output emitted by code-quality adapters.
  """

  @schema_version "conveyor.quality_result@1"
  @statuses [:succeeded, :failed, :blocked]
  @summary_keys ["critical", "high", "medium", "low", "info"]

  @type status :: :succeeded | :failed | :blocked

  @type t :: %__MODULE__{
          schema_version: String.t(),
          adapter: String.t(),
          profile: String.t(),
          status: status(),
          findings: [map()],
          findings_summary: map(),
          new_high_risk_findings: non_neg_integer(),
          risks: [String.t()],
          suggested_validation: [String.t()],
          metadata: map()
        }

  @enforce_keys [:adapter, :profile, :status]
  defstruct schema_version: @schema_version,
            adapter: nil,
            profile: nil,
            status: nil,
            findings: [],
            findings_summary: %{},
            new_high_risk_findings: 0,
            risks: [],
            suggested_validation: [],
            metadata: %{}

  @spec new!(map() | keyword()) :: t()
  def new!(attrs) do
    attrs
    |> Map.new()
    |> then(fn attrs ->
      struct!(
        __MODULE__,
        Map.update(attrs, :findings_summary, empty_summary(), &normalize_summary/1)
      )
    end)
    |> validate!()
  end

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{
      "schema_version" => result.schema_version,
      "adapter" => result.adapter,
      "profile" => result.profile,
      "status" => Atom.to_string(result.status),
      "findings" => result.findings,
      "findings_summary" => result.findings_summary,
      "new_high_risk_findings" => result.new_high_risk_findings,
      "risks" => result.risks,
      "suggested_validation" => result.suggested_validation,
      "metadata" => result.metadata
    }
  end

  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = result) do
    require_non_empty_string!(result.schema_version, "schema_version")
    require_non_empty_string!(result.adapter, "adapter")
    require_non_empty_string!(result.profile, "profile")
    require_status!(result.status)
    require_list!(result.findings, "findings")
    require_list!(result.risks, "risks")
    require_list!(result.suggested_validation, "suggested_validation")
    require_map!(result.findings_summary, "findings_summary")
    require_non_negative_integer!(result.new_high_risk_findings, "new_high_risk_findings")

    result
  end

  @spec empty_summary() :: map()
  def empty_summary do
    Map.new(@summary_keys, &{&1, 0})
  end

  @spec summary_from_findings([map()]) :: map()
  def summary_from_findings(findings) do
    Enum.reduce(findings, empty_summary(), fn finding, summary ->
      severity = finding[:severity] || finding["severity"] || "info"
      key = normalize_severity(severity)
      Map.update!(summary, key, &(&1 + 1))
    end)
  end

  defp normalize_summary(summary) when is_map(summary) do
    Enum.reduce(@summary_keys, %{}, fn key, normalized ->
      Map.put(normalized, key, non_negative_count(summary[key] || summary[String.to_atom(key)]))
    end)
  end

  defp normalize_summary(_summary), do: empty_summary()

  defp normalize_severity(severity) when severity in [:critical, :high, :medium, :low, :info] do
    Atom.to_string(severity)
  end

  defp normalize_severity(severity) when severity in @summary_keys, do: severity
  defp normalize_severity(_severity), do: "info"

  defp non_negative_count(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_count(_value), do: 0

  defp require_non_empty_string!(value, _field) when is_binary(value) and value != "",
    do: value

  defp require_non_empty_string!(_value, field) do
    raise ArgumentError, "#{field} must be a non-empty string"
  end

  defp require_status!(status) when status in @statuses, do: status

  defp require_status!(_status) do
    raise ArgumentError, "status must be one of #{inspect(@statuses)}"
  end

  defp require_list!(value, _field) when is_list(value), do: value

  defp require_list!(_value, field) do
    raise ArgumentError, "#{field} must be a list"
  end

  defp require_map!(value, _field) when is_map(value), do: value

  defp require_map!(_value, field) do
    raise ArgumentError, "#{field} must be a map"
  end

  defp require_non_negative_integer!(value, _field) when is_integer(value) and value >= 0,
    do: value

  defp require_non_negative_integer!(_value, field) do
    raise ArgumentError, "#{field} must be a non-negative integer"
  end
end
