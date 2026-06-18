defmodule Conveyor.Repo.Migrations.UpdateSliceStateMachine do
  use Ecto.Migration

  @new_states [
    "drafted",
    "approved",
    "ready",
    "in_progress",
    "gated",
    "integrated",
    "done",
    "needs_rework",
    "parked",
    "failed",
    "policy_blocked"
  ]

  @old_states ["planned", "ready", "running", "accepted", "blocked", "archived"]

  def up do
    execute("ALTER TABLE slices DROP CONSTRAINT IF EXISTS slices_state_must_be_known")

    execute("""
    UPDATE slices
    SET state = CASE state
      WHEN 'planned' THEN 'drafted'
      WHEN 'running' THEN 'in_progress'
      WHEN 'accepted' THEN 'done'
      WHEN 'blocked' THEN 'needs_rework'
      WHEN 'archived' THEN 'parked'
      ELSE state
    END
    """)

    alter table(:slices) do
      modify :state, :text, null: false, default: "drafted"
    end

    create constraint(:slices, :slices_state_must_be_known,
             check: "state IN (#{quoted_states(@new_states)})"
           )
  end

  def down do
    execute("ALTER TABLE slices DROP CONSTRAINT IF EXISTS slices_state_must_be_known")

    execute("""
    UPDATE slices
    SET state = CASE state
      WHEN 'drafted' THEN 'planned'
      WHEN 'approved' THEN 'planned'
      WHEN 'in_progress' THEN 'running'
      WHEN 'gated' THEN 'running'
      WHEN 'integrated' THEN 'accepted'
      WHEN 'done' THEN 'accepted'
      WHEN 'needs_rework' THEN 'blocked'
      WHEN 'parked' THEN 'archived'
      WHEN 'failed' THEN 'blocked'
      WHEN 'policy_blocked' THEN 'blocked'
      ELSE state
    END
    """)

    alter table(:slices) do
      modify :state, :text, null: false, default: "planned"
    end

    create constraint(:slices, :slices_state_must_be_known,
             check: "state IN (#{quoted_states(@old_states)})"
           )
  end

  defp quoted_states(states) do
    states
    |> Enum.map(&"'#{&1}'")
    |> Enum.join(", ")
  end
end
