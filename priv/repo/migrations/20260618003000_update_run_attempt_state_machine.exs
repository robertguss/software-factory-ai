defmodule Conveyor.Repo.Migrations.UpdateRunAttemptStateMachine do
  use Ecto.Migration

  @new_statuses [
    "planned",
    "running",
    "evidence_recorded",
    "reviewed",
    "gated",
    "reported",
    "failed",
    "cancelled",
    "stale",
    "needs_rework",
    "rejected"
  ]

  @old_statuses ["planned", "running", "succeeded", "failed", "cancelled", "stale"]
  @active_statuses ["planned", "running", "evidence_recorded", "reviewed", "gated"]

  def up do
    drop_if_exists index(:run_attempts, [:slice_id],
                     name: :run_attempts_one_active_per_slice_index
                   )

    execute(
      "ALTER TABLE run_attempts DROP CONSTRAINT IF EXISTS run_attempts_status_must_be_known"
    )

    execute("""
    UPDATE run_attempts
    SET status = CASE status
      WHEN 'succeeded' THEN 'reported'
      ELSE status
    END
    """)

    create constraint(:run_attempts, :run_attempts_status_must_be_known,
             check: "status IN (#{quoted_values(@new_statuses)})"
           )

    create unique_index(:run_attempts, [:slice_id],
             name: :run_attempts_one_active_per_slice_index,
             where: "status IN (#{quoted_values(@active_statuses)})"
           )
  end

  def down do
    drop_if_exists index(:run_attempts, [:slice_id],
                     name: :run_attempts_one_active_per_slice_index
                   )

    execute(
      "ALTER TABLE run_attempts DROP CONSTRAINT IF EXISTS run_attempts_status_must_be_known"
    )

    execute("""
    UPDATE run_attempts
    SET status = CASE status
      WHEN 'evidence_recorded' THEN 'running'
      WHEN 'reviewed' THEN 'running'
      WHEN 'gated' THEN 'running'
      WHEN 'reported' THEN 'succeeded'
      WHEN 'needs_rework' THEN 'failed'
      WHEN 'rejected' THEN 'failed'
      ELSE status
    END
    """)

    create constraint(:run_attempts, :run_attempts_status_must_be_known,
             check: "status IN (#{quoted_values(@old_statuses)})"
           )

    create unique_index(:run_attempts, [:slice_id],
             name: :run_attempts_one_active_per_slice_index,
             where: "status IN ('planned', 'running')"
           )
  end

  defp quoted_values(values) do
    values
    |> Enum.map(&"'#{&1}'")
    |> Enum.join(", ")
  end
end
