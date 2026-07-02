defmodule Conveyor.Repo.Migrations.AllowReworkedHumanApprovals do
  use Ecto.Migration

  # uevc.2: the triage rework disposition records a :reworked human approval.
  def up do
    drop constraint(:human_approvals, :human_approvals_decision_must_be_known)

    create constraint(:human_approvals, :human_approvals_decision_must_be_known,
             check:
               "decision IN ('approved', 'rejected', 'reworked', 'recorded_external_action', 'not_integrated')"
           )
  end

  def down do
    drop constraint(:human_approvals, :human_approvals_decision_must_be_known)

    create constraint(:human_approvals, :human_approvals_decision_must_be_known,
             check:
               "decision IN ('approved', 'rejected', 'recorded_external_action', 'not_integrated')"
           )
  end
end
