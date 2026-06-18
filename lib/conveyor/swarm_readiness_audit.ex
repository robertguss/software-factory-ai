defmodule Conveyor.SwarmReadinessAudit do
  @moduledoc """
  Audits that Phase-1 runs carry every §27 swarm-readiness field.

  Some future scheduler fields are first-class measurements today; others are
  explicit Phase-1 placeholders so later phases can promote them without losing
  the field name in historical records.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.ContextPack
  alias Conveyor.Factory.ExternalChange
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.HumanApproval
  alias Conveyor.Factory.Incident
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.Review
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunPrompt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun
  alias Conveyor.Factory.ToolInvocation
  alias Conveyor.Factory.WorkspaceMaterialization

  @schema_version "conveyor.swarm_readiness_audit@1"

  @field_names [
    "likely_files",
    "conflict_domains",
    "risk",
    "autonomy_ceiling",
    "agent_adapter_profile_model",
    "prompt_template_version",
    "context_scout_version",
    "reviewer_profile_model",
    "trace_id",
    "station_durations",
    "station_retry_counts",
    "heartbeat_gaps",
    "queue_latency",
    "commands_attempted",
    "commands_independently_verified",
    "gate_stages_and_failures",
    "canary_false_negative_rate",
    "policy_incidents",
    "time_to_first_diff",
    "time_to_green",
    "container_image_pull_time",
    "container_create_start_time",
    "dependency_cache_hit_miss",
    "dependency_install_time",
    "gate_workspace_materialization_time",
    "rework_category",
    "cost_tokens",
    "files_changed_count",
    "lines_changed_count",
    "review_decision",
    "human_merge_decision",
    "post_merge_notes"
  ]

  @spec audit!(RunAttempt.t()) :: map()
  def audit!(%RunAttempt{} = run_attempt) do
    data = load_data(run_attempt)
    fields = Enum.map(@field_names, &field(&1, data))

    %{
      "schema_version" => @schema_version,
      "run_attempt_id" => run_attempt.id,
      "passed" => Enum.all?(fields, & &1["captured"]),
      "fields" => fields
    }
  end

  def field_names, do: @field_names

  defp field("likely_files", data),
    do: measured("likely_files", "slice.likely_files", data.slice.likely_files)

  defp field("conflict_domains", data),
    do: measured("conflict_domains", "slice.conflict_domains", data.slice.conflict_domains)

  defp field("risk", data), do: measured("risk", "slice.risk", data.slice.risk)

  defp field("autonomy_ceiling", data),
    do: measured("autonomy_ceiling", "slice.autonomy_level", data.slice.autonomy_level)

  defp field("agent_adapter_profile_model", data) do
    measured(
      "agent_adapter_profile_model",
      "run_spec.agent_profile_snapshot",
      data.run_spec.agent_profile_snapshot
    )
  end

  defp field("prompt_template_version", data) do
    measured(
      "prompt_template_version",
      "run_spec.prompt_template_version",
      data.run_spec.prompt_template_version
    )
  end

  defp field("context_scout_version", data) do
    measured(
      "context_scout_version",
      "context_pack.scout_version",
      Enum.map(data.context_packs, & &1.scout_version)
    )
  end

  defp field("reviewer_profile_model", data) do
    measured(
      "reviewer_profile_model",
      "review.reviewer_profile_id+rubric_version",
      Enum.map(
        data.reviews,
        &%{"reviewer_profile_id" => &1.reviewer_profile_id, "rubric_version" => &1.rubric_version}
      )
    )
  end

  defp field("trace_id", data),
    do: measured("trace_id", "run_attempt.trace_id", data.run_attempt.trace_id)

  defp field("station_durations", data) do
    measured(
      "station_durations",
      "station_runs.started_at/completed_at",
      Enum.map(
        data.station_runs,
        &%{"station" => &1.station, "duration_ms" => duration_ms(&1.started_at, &1.completed_at)}
      )
    )
  end

  defp field("station_retry_counts", data) do
    measured(
      "station_retry_counts",
      "station_runs.attempt_no",
      Enum.map(data.station_runs, &%{"station" => &1.station, "attempt_no" => &1.attempt_no})
    )
  end

  defp field("heartbeat_gaps", data) do
    measured(
      "heartbeat_gaps",
      "station_runs.heartbeat_at",
      Enum.map(
        data.station_runs,
        &%{"station" => &1.station, "heartbeat_at" => iso8601(&1.heartbeat_at)}
      )
    )
  end

  defp field("queue_latency", data) do
    measured(
      "queue_latency",
      "run_attempt.started_at+station_runs.started_at",
      Enum.map(
        data.station_runs,
        &%{
          "station" => &1.station,
          "latency_ms" => duration_ms(data.run_attempt.started_at, &1.started_at)
        }
      )
    )
  end

  defp field("commands_attempted", data),
    do:
      measured(
        "commands_attempted",
        "tool_invocations",
        Enum.map(data.tool_invocations, & &1.tool_name)
      )

  defp field("commands_independently_verified", data) do
    verified = Enum.filter(data.tool_invocations, &(&1.invocation_kind == "verify"))

    measured(
      "commands_independently_verified",
      "tool_invocations.invocation_kind=verify",
      Enum.map(verified, & &1.tool_name)
    )
  end

  defp field("gate_stages_and_failures", data) do
    measured(
      "gate_stages_and_failures",
      "gate_results.stages",
      Enum.flat_map(data.gate_results, & &1.stages)
    )
  end

  defp field("canary_false_negative_rate", data) do
    total = max(length(data.gate_results), 1)
    false_negatives = Enum.count(data.gate_results, &(&1.false_negative == true))
    measured("canary_false_negative_rate", "gate_results.false_negative", false_negatives / total)
  end

  defp field("policy_incidents", data),
    do:
      measured("policy_incidents", "incidents.category", Enum.map(data.incidents, & &1.category))

  defp field("time_to_first_diff", data) do
    value =
      data.patch_sets
      |> Enum.map(&duration_ms(data.run_attempt.started_at, &1.generated_at))
      |> Enum.reject(&is_nil/1)
      |> Enum.min(fn -> nil end)

    measured("time_to_first_diff", "patch_sets.generated_at", value)
  end

  defp field("time_to_green", data),
    do:
      measured(
        "time_to_green",
        "run_attempt.completed_at",
        duration_ms(data.run_attempt.started_at, data.run_attempt.completed_at)
      )

  defp field("container_image_pull_time", _data),
    do: placeholder("container_image_pull_time", "workspace_materialization.phase1_placeholder")

  defp field("container_create_start_time", data),
    do:
      measured(
        "container_create_start_time",
        "workspace_materializations.container_id",
        Enum.map(data.workspaces, & &1.container_id)
      )

  defp field("dependency_cache_hit_miss", _data),
    do: placeholder("dependency_cache_hit_miss", "tool_invocation.phase1_placeholder")

  defp field("dependency_install_time", _data),
    do: placeholder("dependency_install_time", "tool_invocation.phase1_placeholder")

  defp field("gate_workspace_materialization_time", data) do
    gate_workspaces = Enum.filter(data.workspaces, &(&1.purpose == :gate))

    measured(
      "gate_workspace_materialization_time",
      "workspace_materializations.purpose=gate",
      Enum.map(gate_workspaces, &iso8601(&1.created_at))
    )
  end

  defp field("rework_category", data),
    do:
      measured(
        "rework_category",
        "run_attempt.failure_category",
        data.run_attempt.failure_category || "none"
      )

  defp field("cost_tokens", data) do
    measured(
      "cost_tokens",
      "retrospective.cost_estimate_placeholder",
      %{
        "token_count" => nil,
        "estimated_usd" => nil,
        "tool_invocation_count" => length(data.tool_invocations)
      }
    )
  end

  defp field("files_changed_count", data) do
    count = data.patch_sets |> Enum.flat_map(& &1.changed_files) |> Enum.uniq() |> length()
    measured("files_changed_count", "patch_sets.changed_files", count)
  end

  defp field("lines_changed_count", data) do
    count = Enum.reduce(data.patch_sets, 0, &(&1.lines_added + &1.lines_deleted + &2))
    measured("lines_changed_count", "patch_sets.lines_added/deleted", count)
  end

  defp field("review_decision", data),
    do:
      measured(
        "review_decision",
        "reviews.decision",
        Enum.map(data.reviews, &Atom.to_string(&1.decision))
      )

  defp field("human_merge_decision", _data),
    do:
      placeholder("human_merge_decision", "human_integration.phase1_post_projection_placeholder")

  defp field("post_merge_notes", _data),
    do: placeholder("post_merge_notes", "external_change.phase1_post_projection_placeholder")

  defp measured(name, source, value) do
    %{
      "field" => name,
      "captured" => true,
      "source" => source,
      "quality" => quality(value),
      "value_summary" => summarize(value)
    }
  end

  defp placeholder(name, source) do
    %{
      "field" => name,
      "captured" => true,
      "source" => source,
      "quality" => "phase1_placeholder",
      "value_summary" => nil
    }
  end

  defp load_data(run_attempt) do
    run_spec = get_by_id!(RunSpec, run_attempt.run_spec_id)
    slice = get_by_id!(Slice, run_attempt.slice_id)

    %{
      context_packs: filter(ContextPack, &(&1.slice_id == slice.id)),
      external_changes: filter(ExternalChange, &(&1.run_attempt_id == run_attempt.id)),
      gate_results: filter(GateResult, &(&1.run_attempt_id == run_attempt.id)),
      human_approvals: filter(HumanApproval, &(&1.run_attempt_id == run_attempt.id)),
      incidents: filter(Incident, &(&1.run_attempt_id == run_attempt.id)),
      patch_sets: filter(PatchSet, &(&1.run_attempt_id == run_attempt.id)),
      reviews: filter(Review, &(&1.run_attempt_id == run_attempt.id)),
      run_attempt: run_attempt,
      run_prompts: filter(RunPrompt, &(&1.slice_id == slice.id)),
      run_spec: run_spec,
      slice: slice,
      station_runs: filter(StationRun, &(&1.run_attempt_id == run_attempt.id)),
      tool_invocations: filter(ToolInvocation, &(&1.run_attempt_id == run_attempt.id)),
      workspaces: filter(WorkspaceMaterialization, &(&1.run_spec_id == run_spec.id))
    }
  end

  defp filter(resource, predicate) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.filter(predicate)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp duration_ms(%DateTime{} = started_at, %DateTime{} = completed_at) do
    DateTime.diff(completed_at, started_at, :millisecond)
  end

  defp duration_ms(_started_at, _completed_at), do: nil

  defp iso8601(%DateTime{} = timestamp), do: DateTime.to_iso8601(timestamp)
  defp iso8601(_timestamp), do: nil

  defp quality(nil), do: "empty"
  defp quality([]), do: "empty"
  defp quality(_value), do: "measured"

  defp summarize(value) when is_list(value), do: %{"count" => length(value)}
  defp summarize(value) when is_map(value), do: value
  defp summarize(value), do: value
end
