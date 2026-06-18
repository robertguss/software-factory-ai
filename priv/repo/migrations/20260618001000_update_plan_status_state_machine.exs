defmodule Conveyor.Repo.Migrations.UpdatePlanStatusStateMachine do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE plans DROP CONSTRAINT IF EXISTS plans_status_must_be_known")

    execute("""
    UPDATE plans
    SET status = CASE status
      WHEN 'imported' THEN 'draft'
      WHEN 'auditing' THEN 'audited'
      WHEN 'ready' THEN 'handoff_ready'
      WHEN 'blocked' THEN 'needs_clarification'
      ELSE status
    END
    """)

    alter table(:plans) do
      modify :status, :text, null: false, default: "draft"
    end

    create constraint(:plans, :plans_status_must_be_known,
             check:
               "status IN ('draft', 'audited', 'handoff_ready', 'active', 'completed', 'needs_clarification', 'archived')"
           )
  end

  def down do
    execute("ALTER TABLE plans DROP CONSTRAINT IF EXISTS plans_status_must_be_known")

    execute("""
    UPDATE plans
    SET status = CASE status
      WHEN 'draft' THEN 'imported'
      WHEN 'audited' THEN 'auditing'
      WHEN 'handoff_ready' THEN 'ready'
      WHEN 'active' THEN 'ready'
      WHEN 'completed' THEN 'ready'
      WHEN 'needs_clarification' THEN 'blocked'
      ELSE status
    END
    """)

    alter table(:plans) do
      modify :status, :text, null: false, default: "imported"
    end

    create constraint(:plans, :plans_status_must_be_known,
             check: "status IN ('imported', 'auditing', 'ready', 'blocked', 'archived')"
           )
  end
end
