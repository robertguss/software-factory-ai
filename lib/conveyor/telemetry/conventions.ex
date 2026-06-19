defmodule Conveyor.Telemetry.Conventions do
  @moduledoc """
  OpenTelemetry-compatible naming and cardinality rules for Conveyor signals.

  Phase 1 keeps telemetry intentionally small: a required trace hierarchy, one
  trace context carried across persisted records and artifacts, and bounded
  metric labels.
  """

  @type span_key ::
          :run_slice
          | :station_readiness
          | :station_baseline
          | :station_scout
          | :station_prompt
          | :station_implement
          | :adapter_pi_session
          | :tool_command
          | :station_evidence
          | :station_review
          | :station_gate
          | :station_canary
          | :station_post_integration

  @type trace_context :: %{
          required(:trace_id) => String.t(),
          required(:span_id) => String.t(),
          required(:traceparent) => String.t()
        }

  @span_names %{
    run_slice: "conveyor.run_slice",
    station_readiness: "conveyor.station.readiness",
    station_baseline: "conveyor.station.baseline",
    station_scout: "conveyor.station.scout",
    station_prompt: "conveyor.station.prompt",
    station_implement: "conveyor.station.implement",
    adapter_pi_session: "conveyor.adapter.pi.session",
    tool_command: "conveyor.tool.command",
    station_evidence: "conveyor.station.evidence",
    station_review: "conveyor.station.review",
    station_gate: "conveyor.station.gate",
    station_canary: "conveyor.station.canary",
    station_post_integration: "conveyor.station.post_integration"
  }

  @span_parents %{
    station_readiness: :run_slice,
    station_baseline: :run_slice,
    station_scout: :run_slice,
    station_prompt: :run_slice,
    station_implement: :run_slice,
    adapter_pi_session: :station_implement,
    tool_command: :station_implement,
    station_evidence: :run_slice,
    station_review: :run_slice,
    station_gate: :run_slice,
    station_canary: :run_slice,
    station_post_integration: :run_slice
  }

  @span_hierarchy [
    {:run_slice,
     [
       :station_readiness,
       :station_baseline,
       :station_scout,
       :station_prompt,
       {:station_implement, [:adapter_pi_session, :tool_command]},
       :station_evidence,
       :station_review,
       :station_gate,
       :station_canary,
       :station_post_integration
     ]}
  ]

  @allowed_metric_dimensions MapSet.new([
                               "project_id",
                               "station",
                               "adapter",
                               "profile",
                               "status",
                               "failure_category",
                               "policy_profile",
                               "suite_kind",
                               # Eval program dimensions ([:conveyor, :eval, :result]).
                               "eval_suite",
                               "eval_case",
                               "archetype"
                             ])

  @required_trace_subjects [
    :ledger_event,
    :station_run,
    :tool_invocation,
    :artifact_manifest,
    :projected_report
  ]

  @spec span_name(span_key()) :: String.t()
  def span_name(span), do: Map.fetch!(@span_names, span)

  @spec span_parent(span_key()) :: span_key() | nil
  def span_parent(:run_slice), do: nil
  def span_parent(span), do: Map.fetch!(@span_parents, span)

  @spec child_span?(span_key(), span_key()) :: boolean()
  def child_span?(parent, child), do: span_parent(child) == parent

  @spec required_span_hierarchy() :: [{span_key(), [span_key() | {span_key(), [span_key()]}]}]
  def required_span_hierarchy, do: @span_hierarchy

  @spec allowed_metric_dimensions() :: [String.t()]
  def allowed_metric_dimensions do
    @allowed_metric_dimensions
    |> MapSet.to_list()
    |> Enum.sort()
  end

  @spec required_trace_subjects() :: [atom()]
  def required_trace_subjects, do: @required_trace_subjects

  @spec trace_context(String.t(), String.t()) :: trace_context()
  def trace_context(trace_id, span_id) do
    %{
      trace_id: trace_id,
      span_id: span_id,
      traceparent: "00-#{trace_id}-#{span_id}-01"
    }
  end

  @spec attach_trace_context(map(), trace_context()) :: map()
  def attach_trace_context(record, %{trace_id: trace_id, span_id: span_id}) do
    record
    |> Map.put(:trace_id, trace_id)
    |> Map.put(:span_id, span_id)
  end

  @spec validate_metric_dimensions(map()) ::
          :ok | {:error, {:disallowed_metric_dimensions, [String.t()]}}
  def validate_metric_dimensions(metadata) when is_map(metadata) do
    metadata
    |> Map.keys()
    |> Enum.map(&normalize_dimension/1)
    |> Enum.reject(&MapSet.member?(@allowed_metric_dimensions, &1))
    |> case do
      [] -> :ok
      disallowed -> {:error, {:disallowed_metric_dimensions, Enum.sort(disallowed)}}
    end
  end

  defp normalize_dimension(dimension) when is_atom(dimension), do: Atom.to_string(dimension)
  defp normalize_dimension(dimension), do: to_string(dimension)
end
