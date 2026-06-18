defmodule Conveyor.AgentRunner.EventRecorder do
  @moduledoc """
  Records normalized AgentRunner events into the append-only ledger.
  """

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Ledger

  @event_version "conveyor.agent_event@1"
  @event_types ~w(
    session_started
    message_delta
    message_completed
    command_requested
    command_policy_decision
    command_started
    command_completed
    file_change_observed
    heartbeat
    final_response
    cancel_requested
    cancel_acknowledged
    adapter_error
    session_completed
  )

  @spec record!(map() | keyword(), keyword()) :: LedgerEvent.t()
  def record!(attrs, opts \\ []) do
    attrs = attrs |> Map.new() |> normalize_attrs()
    context = context!(attrs)
    sequence_no = sequence_no!(attrs)
    idempotency_key = idempotency_key(context.agent_session.id, sequence_no)

    case existing_event(idempotency_key) do
      nil ->
        require_monotonic_sequence!(context.agent_session.id, sequence_no)
        append_event!(attrs, opts, context, sequence_no, idempotency_key)

      event ->
        event
    end
  end

  @spec event_version() :: String.t()
  def event_version, do: @event_version

  @spec event_types() :: [String.t()]
  def event_types, do: @event_types

  defp append_event!(attrs, opts, context, sequence_no, idempotency_key) do
    occurred_at = Map.get(attrs, :occurred_at, DateTime.utc_now(:microsecond))
    raw_ref = raw_ref(attrs, opts)
    event_type = event_type!(attrs)

    envelope = %{
      "event_version" => @event_version,
      "run_spec_sha256" => context.run_spec.run_spec_sha256,
      "run_attempt_id" => context.run_attempt.id,
      "agent_session_id" => context.agent_session.id,
      "adapter" => required_string!(attrs, :adapter),
      "session_id" => session_id(attrs, context.agent_session),
      "sequence_no" => sequence_no,
      "event_type" => event_type,
      "occurred_at" => DateTime.to_iso8601(occurred_at),
      "payload" => Map.get(attrs, :payload, %{}),
      "raw_ref" => raw_ref
    }

    Ledger.write!(%{
      project_id: context.project.id,
      slice_id: context.slice.id,
      run_attempt_id: context.run_attempt.id,
      agent_session_id: context.agent_session.id,
      idempotency_key: idempotency_key,
      type: "agent.event",
      payload: envelope,
      occurred_at: occurred_at
    })
  end

  defp raw_ref(attrs, opts) do
    case Map.fetch(attrs, :raw) do
      {:ok, raw} ->
        raw
        |> raw_content()
        |> BlobStore.write!(opts)
        |> Map.fetch!(:ref)

      :error ->
        Map.get(attrs, :raw_ref)
    end
  end

  defp raw_content(raw) when is_binary(raw), do: raw
  defp raw_content(raw), do: Jason.encode!(raw, pretty: true)

  defp context!(attrs) do
    agent_session =
      find!(AgentSession, required_string!(attrs, :agent_session_id), "agent session")

    run_attempt = find!(RunAttempt, agent_session.run_attempt_id, "run attempt")
    run_spec = find!(RunSpec, run_attempt.run_spec_id, "run spec")
    slice = find!(Slice, run_attempt.slice_id, "slice")
    epic = find!(Epic, slice.epic_id, "epic")
    plan = find!(Plan, epic.plan_id, "plan")
    project = find!(Project, plan.project_id, "project")

    %{
      agent_session: agent_session,
      run_attempt: run_attempt,
      run_spec: run_spec,
      slice: slice,
      project: project
    }
  end

  defp require_monotonic_sequence!(agent_session_id, sequence_no) do
    max_seen =
      agent_session_id
      |> events_for_session()
      |> Enum.map(&get_in(&1.payload, ["sequence_no"]))
      |> Enum.filter(&is_integer/1)
      |> Enum.max(fn -> 0 end)

    if sequence_no <= max_seen do
      raise ArgumentError,
            "agent event sequence_no #{sequence_no} must be greater than previous #{max_seen}"
    end
  end

  defp existing_event(idempotency_key) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.idempotency_key == idempotency_key))
  end

  defp events_for_session(agent_session_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.agent_session_id == agent_session_id and &1.type == "agent.event"))
  end

  defp event_type!(attrs) do
    event_type = required_string!(attrs, :event_type)

    if event_type in @event_types do
      event_type
    else
      raise ArgumentError, "unknown agent event_type #{inspect(event_type)}"
    end
  end

  defp sequence_no!(attrs) do
    case Map.fetch(attrs, :sequence_no) do
      {:ok, sequence_no} when is_integer(sequence_no) and sequence_no > 0 -> sequence_no
      _other -> raise ArgumentError, "sequence_no must be a positive integer"
    end
  end

  defp session_id(attrs, agent_session) do
    Map.get(attrs, :session_id) || agent_session.adapter_session_id || agent_session.id
  end

  defp required_string!(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{field} must be a non-empty string"
    end
  end

  defp find!(resource, id, label) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{label} #{id} was not found"
  end

  defp idempotency_key(agent_session_id, sequence_no) do
    "agent-event:#{agent_session_id}:#{sequence_no}"
  end

  defp normalize_attrs(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
  end
end
