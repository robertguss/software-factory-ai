defmodule Conveyor.PlanLifecycle do
  @moduledoc """
  Guarded Plan lifecycle transitions with ledger events.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.Plan
  alias Conveyor.Ledger
  alias Conveyor.Repo

  @spec transition!(struct(), atom(), keyword()) :: struct()
  def transition!(%Plan{} = plan, target_status, opts \\ []) when is_atom(target_status) do
    previous_status = plan.status

    Repo.transaction(fn ->
      {updated_plan, notifications} =
        Ash.update!(plan, %{status: target_status},
          domain: Factory,
          return_notifications?: true
        )

      {_event, ledger_notifications} =
        write_transition_event!(updated_plan, previous_status, target_status, opts)

      {updated_plan, notifications ++ ledger_notifications}
    end)
    |> case do
      {:ok, {updated_plan, notifications}} ->
        Ash.Notifier.notify(notifications)
        updated_plan

      {:error, reason} ->
        raise reason
    end
  end

  defp write_transition_event!(plan, previous_status, target_status, opts) do
    occurred_at = Keyword.get_lazy(opts, :occurred_at, fn -> DateTime.utc_now(:microsecond) end)
    actor = Keyword.get(opts, :actor, "system")
    reason = Keyword.get(opts, :reason, "plan transition")

    Ledger.write!(
      %{
        project_id: plan.project_id,
        idempotency_key: idempotency_key(plan.id, previous_status, target_status, occurred_at),
        type: "plan.transitioned",
        payload: %{
          "actor" => actor,
          "plan_id" => plan.id,
          "previous_status" => Atom.to_string(previous_status),
          "status" => Atom.to_string(target_status),
          "reason" => reason
        },
        occurred_at: occurred_at
      },
      return_notifications?: true
    )
  end

  defp idempotency_key(plan_id, previous_status, target_status, occurred_at) do
    timestamp = DateTime.to_unix(occurred_at, :microsecond)
    "plan:#{plan_id}:#{previous_status}:#{target_status}:#{timestamp}"
  end
end
