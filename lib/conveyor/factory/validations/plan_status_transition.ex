defmodule Conveyor.Factory.Validations.PlanStatusTransition do
  @moduledoc false

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute
  alias Conveyor.Factory
  alias Conveyor.Factory.PlanAudit

  @allowed_transitions MapSet.new([
                         {:draft, :audited},
                         {:draft, :needs_clarification},
                         {:draft, :archived},
                         {:audited, :handoff_ready},
                         {:audited, :needs_clarification},
                         {:audited, :archived},
                         {:needs_clarification, :audited},
                         {:needs_clarification, :archived},
                         {:handoff_ready, :active},
                         {:handoff_ready, :archived},
                         {:active, :completed},
                         {:active, :archived},
                         {:completed, :archived}
                       ])

  @impl true
  def validate(changeset, _opts, _context) do
    old_status = changeset.data.status
    new_status = Ash.Changeset.get_attribute(changeset, :status)

    cond do
      old_status == new_status ->
        :ok

      not MapSet.member?(@allowed_transitions, {old_status, new_status}) ->
        invalid("illegal Plan status transition #{old_status} -> #{new_status}")

      new_status == :handoff_ready and not ready_audit?(changeset.data.id) ->
        invalid("Plan cannot reach handoff_ready without a ready PlanAudit")

      true ->
        :ok
    end
  end

  defp ready_audit?(plan_id) do
    PlanAudit
    |> Ash.read!(domain: Factory)
    |> Enum.any?(&(&1.plan_id == plan_id and &1.decision == :ready))
  end

  defp invalid(message) do
    {:error, InvalidAttribute.exception(field: :status, message: message)}
  end
end
