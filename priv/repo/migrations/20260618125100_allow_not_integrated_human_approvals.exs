defmodule Conveyor.Repo.Migrations.AllowNotIntegratedHumanApprovals do
  use Ecto.Migration

  def up do
    drop constraint(:human_approvals, :human_approvals_decision_must_be_known)

    create constraint(:human_approvals, :human_approvals_decision_must_be_known,
             check:
               "decision IN ('approved', 'rejected', 'recorded_external_action', 'not_integrated')"
           )
  end

  def down do
    drop constraint(:human_approvals, :human_approvals_decision_must_be_known)

    create constraint(:human_approvals, :human_approvals_decision_must_be_known,
             check: "decision IN ('approved', 'rejected', 'recorded_external_action')"
           )
  end
end
