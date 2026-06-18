defmodule Conveyor.Retrospective do
  @moduledoc """
  Builds the structured retrospective record for a run attempt.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.Incident
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.StationRun
  alias Conveyor.Factory.ToolInvocation
  alias Conveyor.SwarmReadinessAudit

  @schema_version "conveyor.retrospective@1"
  @handoff_template_version "conveyor.rework_handoff@1"

  @spec build!(RunAttempt.t()) :: map()
  def build!(%RunAttempt{} = run_attempt) do
    station_runs = station_runs(run_attempt.id)
    tool_invocations = tool_invocations(run_attempt.id)
    gate_results = gate_results(run_attempt.id)
    incidents = incidents(run_attempt.id)

    %{
      "schema_version" => @schema_version,
      "run_attempt_id" => run_attempt.id,
      "slice_id" => run_attempt.slice_id,
      "attempt_no" => run_attempt.attempt_no,
      "status" => Atom.to_string(run_attempt.status),
      "outcome" => Atom.to_string(run_attempt.outcome),
      "timings" => timings(run_attempt, station_runs, tool_invocations),
      "cost_estimate" => cost_estimate(tool_invocations),
      "adapter_friction" => adapter_friction(tool_invocations),
      "failure_taxonomy" => failure_taxonomy(run_attempt, station_runs, incidents),
      "gate_canary" => gate_canary(gate_results),
      "schema_friction" => schema_friction(incidents),
      "swarm_readiness" => SwarmReadinessAudit.audit!(run_attempt),
      "rework_handoff" => rework_handoff(run_attempt, station_runs, incidents)
    }
  end

  defp timings(run_attempt, station_runs, tool_invocations) do
    %{
      "run_duration_ms" => duration_ms(run_attempt.started_at, run_attempt.completed_at),
      "stations" =>
        Enum.map(station_runs, fn station_run ->
          %{
            "station" => station_run.station,
            "status" => Atom.to_string(station_run.status),
            "duration_ms" => duration_ms(station_run.started_at, station_run.completed_at),
            "started_at" => iso8601(station_run.started_at),
            "completed_at" => iso8601(station_run.completed_at),
            "error_category" => station_run.error_category
          }
        end),
      "tool_invocations" =>
        Enum.map(tool_invocations, fn invocation ->
          %{
            "tool_name" => invocation.tool_name,
            "invocation_kind" => invocation.invocation_kind,
            "duration_ms" => invocation.duration_ms,
            "status" => Atom.to_string(invocation.status)
          }
        end)
    }
  end

  defp cost_estimate(tool_invocations) do
    %{
      "token_count" => nil,
      "estimated_usd" => nil,
      "tool_invocation_count" => length(tool_invocations),
      "measured_duration_ms" =>
        tool_invocations
        |> Enum.map(&(&1.duration_ms || 0))
        |> Enum.sum()
    }
  end

  defp adapter_friction(tool_invocations) do
    failed = Enum.filter(tool_invocations, &(&1.status in [:failed, :blocked]))

    %{
      "failed_tool_invocations" => length(failed),
      "blocked_tool_invocations" => Enum.count(tool_invocations, &(&1.status == :blocked)),
      "network_modes" =>
        tool_invocations |> Enum.map(&Atom.to_string(&1.network_mode)) |> Enum.uniq()
    }
  end

  defp failure_taxonomy(run_attempt, station_runs, incidents) do
    station_categories =
      station_runs
      |> Enum.map(& &1.error_category)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    incident_categories = incidents |> Enum.map(& &1.category) |> Enum.uniq()

    %{
      "run_category" => run_attempt.failure_category || "none",
      "station_categories" => station_categories,
      "incident_categories" => incident_categories,
      "primary_station" => primary_failed_station(station_runs)
    }
  end

  defp gate_canary(gate_results) do
    %{
      "gate_result_count" => length(gate_results),
      "false_negative_count" => Enum.count(gate_results, &(&1.false_negative == true)),
      "canary_suite_versions" =>
        gate_results
        |> Enum.map(& &1.canary_suite_version)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
    }
  end

  defp schema_friction(incidents) do
    schema_incidents = Enum.filter(incidents, &(&1.category == "schema_friction"))

    %{
      "incident_count" => length(schema_incidents),
      "open_incident_count" => Enum.count(schema_incidents, &(&1.status == :open)),
      "evidence_refs" => schema_incidents |> Enum.flat_map(& &1.evidence_refs) |> Enum.uniq()
    }
  end

  defp rework_handoff(run_attempt, station_runs, incidents) do
    %{
      "template_version" => @handoff_template_version,
      "summary" => handoff_summary(run_attempt),
      "next_actions" => next_actions(run_attempt, station_runs, incidents),
      "evidence_refs" => incidents |> Enum.flat_map(& &1.evidence_refs) |> Enum.uniq()
    }
  end

  defp handoff_summary(%RunAttempt{failure_category: nil}), do: "No rework required."

  defp handoff_summary(%RunAttempt{failure_category: category}),
    do: "Rework run category: #{category}."

  defp next_actions(%RunAttempt{failure_category: nil}, _station_runs, _incidents) do
    [%{"kind" => "observe", "label" => "No failed category recorded"}]
  end

  defp next_actions(_run_attempt, station_runs, incidents) do
    station_actions =
      station_runs
      |> Enum.filter(&(&1.status == :failed))
      |> Enum.map(fn station_run ->
        %{
          "kind" => "rerun_station",
          "label" => "Inspect and rerun station #{station_run.station}",
          "error_category" => station_run.error_category
        }
      end)

    incident_actions =
      incidents
      |> Enum.filter(&(&1.status == :open))
      |> Enum.map(fn incident ->
        %{
          "kind" => "inspect_artifact",
          "label" => "Resolve incident #{incident.category}",
          "evidence_refs" => incident.evidence_refs
        }
      end)

    case station_actions ++ incident_actions do
      [] -> [%{"kind" => "inspect_artifact", "label" => "Review retrospective context"}]
      actions -> actions
    end
  end

  defp primary_failed_station(station_runs) do
    station_runs
    |> Enum.find(&(&1.status == :failed))
    |> case do
      nil -> nil
      station_run -> station_run.station
    end
  end

  defp duration_ms(%DateTime{} = started_at, %DateTime{} = completed_at) do
    DateTime.diff(completed_at, started_at, :millisecond)
  end

  defp duration_ms(_started_at, _completed_at), do: nil

  defp iso8601(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)
  defp iso8601(_timestamp), do: nil

  defp station_runs(run_attempt_id) do
    StationRun
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt_id))
    |> Enum.sort_by(& &1.station)
  end

  defp tool_invocations(run_attempt_id) do
    ToolInvocation
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt_id))
    |> Enum.sort_by(& &1.started_at, DateTime)
  end

  defp gate_results(run_attempt_id) do
    GateResult
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt_id))
  end

  defp incidents(run_attempt_id) do
    Incident
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt_id))
    |> Enum.sort_by(& &1.category)
  end
end
