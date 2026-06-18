defmodule Conveyor.SliceLifecycle do
  @moduledoc """
  Guarded Slice lifecycle transitions with ledger events.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Ledger
  alias Conveyor.Repo

  @spec transition!(struct(), atom(), keyword()) :: struct()
  def transition!(%Slice{} = slice, action, opts \\ []) when is_atom(action) do
    previous_state = slice.state

    Repo.transaction(fn ->
      context = context_for!(slice)
      guard_transition!(slice, action, context, opts)

      {updated_slice, notifications} =
        Ash.update!(slice, %{},
          action: action,
          domain: Factory,
          return_notifications?: true
        )

      {_event, ledger_notifications} =
        write_transition_event!(updated_slice, previous_state, action, context.project, opts)

      {updated_slice, notifications ++ ledger_notifications}
    end)
    |> case do
      {:ok, {updated_slice, notifications}} ->
        Ash.Notifier.notify(notifications)
        updated_slice

      {:error, reason} ->
        raise reason
    end
  end

  defp context_for!(slice) do
    epic = get_by_id!(Epic, slice.epic_id)
    plan = get_by_id!(Plan, epic.plan_id)
    project = get_by_id!(Project, plan.project_id)
    latest_brief = latest_brief(slice.id)

    %{epic: epic, plan: plan, project: project, latest_brief: latest_brief}
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp latest_brief(slice_id) do
    AgentBrief
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(&{&1.version, &1.locked_at}, :desc)
    |> List.first()
  end

  defp guard_transition!(slice, :mark_ready, context, _opts) do
    require_plan_handoff_ready!(context.plan)
    require_locked_brief!(context.latest_brief)
    require_autonomy_within_policy!(slice, context.project)
  end

  defp guard_transition!(_slice, :start, context, opts) do
    brief = require_locked_brief!(context.latest_brief)
    actor = Keyword.get(opts, :actor)

    if is_nil(actor) or actor == "" do
      raise ArgumentError, "Slice cannot start without an implementation actor"
    end

    if actor == brief.locked_by do
      raise ArgumentError, "Slice actor must differ from the Brief locker"
    end
  end

  defp guard_transition!(_slice, :gate, _context, opts) do
    require_flag!(
      opts,
      :required_artifacts?,
      "Slice cannot enter gated without required artifacts"
    )

    require_flag!(
      opts,
      :gate_stage_complete?,
      "Slice cannot enter gated before gate checks complete"
    )
  end

  defp guard_transition!(_slice, :integrate, _context, opts) do
    require_flag!(opts, :required_artifacts?, "Slice cannot integrate without required artifacts")
  end

  defp guard_transition!(_slice, :complete, _context, opts) do
    require_flag!(
      opts,
      :gate_stage_complete?,
      "Slice cannot complete before gate checks complete"
    )
  end

  defp guard_transition!(_slice, _action, _context, _opts), do: :ok

  defp require_plan_handoff_ready!(%Plan{status: :handoff_ready}), do: :ok

  defp require_plan_handoff_ready!(%Plan{status: status}) do
    raise ArgumentError, "Slice cannot be ready until Plan is handoff_ready; got #{status}"
  end

  defp require_locked_brief!(%AgentBrief{} = brief), do: brief

  defp require_locked_brief!(nil) do
    raise ArgumentError, "Slice cannot transition without a locked AgentBrief"
  end

  defp require_autonomy_within_policy!(slice, project) do
    slice_level = autonomy_level!(slice.autonomy_level)
    project_level = project.default_autonomy_level

    if slice_level > project_level do
      raise ArgumentError,
            "Slice autonomy level #{slice.autonomy_level} exceeds Project default L#{project_level}"
    end
  end

  defp autonomy_level!("L" <> level), do: String.to_integer(level)

  defp autonomy_level!(level) do
    raise ArgumentError, "Slice autonomy level #{inspect(level)} must use L<n> format"
  end

  defp require_flag!(opts, key, message) do
    if Keyword.get(opts, key) == true do
      :ok
    else
      raise ArgumentError, message
    end
  end

  defp write_transition_event!(slice, previous_state, action, project, opts) do
    occurred_at = Keyword.get_lazy(opts, :occurred_at, fn -> DateTime.utc_now(:microsecond) end)
    actor = Keyword.get(opts, :actor, "system")
    reason = Keyword.get(opts, :reason, "slice transition")

    Ledger.write!(
      %{
        project_id: project.id,
        slice_id: slice.id,
        idempotency_key: idempotency_key(slice.id, previous_state, slice.state, occurred_at),
        type: "slice.transitioned",
        payload: %{
          "actor" => actor,
          "slice_id" => slice.id,
          "action" => Atom.to_string(action),
          "previous_state" => Atom.to_string(previous_state),
          "state" => Atom.to_string(slice.state),
          "reason" => reason
        },
        occurred_at: occurred_at
      },
      return_notifications?: true
    )
  end

  defp idempotency_key(slice_id, previous_state, state, occurred_at) do
    timestamp = DateTime.to_unix(occurred_at, :microsecond)
    "slice:#{slice_id}:#{previous_state}:#{state}:#{timestamp}"
  end
end
