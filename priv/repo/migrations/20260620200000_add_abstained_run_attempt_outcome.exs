defmodule Conveyor.Repo.Migrations.AddAbstainedRunAttemptOutcome do
  @moduledoc """
  ADR-23: the ternary gate verdict adds an `:abstained` run-attempt outcome (a
  passed gate the calibrated TrustScore was not confident enough to auto-accept).
  Widen the `outcome` check constraint to admit it.
  """

  use Ecto.Migration

  def up do
    drop constraint(:run_attempts, :run_attempts_outcome_must_be_known)

    create constraint(:run_attempts, :run_attempts_outcome_must_be_known,
             check:
               "outcome IN ('none', 'needs_rework', 'accepted', 'rejected', 'policy_blocked', 'abstained')"
           )
  end

  def down do
    drop constraint(:run_attempts, :run_attempts_outcome_must_be_known)

    create constraint(:run_attempts, :run_attempts_outcome_must_be_known,
             check:
               "outcome IN ('none', 'needs_rework', 'accepted', 'rejected', 'policy_blocked')"
           )
  end
end
