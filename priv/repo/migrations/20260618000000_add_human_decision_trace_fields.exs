defmodule Conveyor.Repo.Migrations.AddHumanDecisionTraceFields do
  use Ecto.Migration

  def up do
    alter table(:human_decisions) do
      add :section_ref, :text
      add :source_span, :map, null: false, default: %{}
      add :contract_sha256, :text
    end

    execute("""
    UPDATE human_decisions AS human_decision
    SET section_ref = 'decisions/' || human_decision.stable_key,
        contract_sha256 = plans.contract_sha256
    FROM plans
    WHERE human_decision.plan_id = plans.id
    """)

    alter table(:human_decisions) do
      modify :section_ref, :text, null: false
      modify :contract_sha256, :text, null: false
    end

    create index(:human_decisions, [:contract_sha256])

    execute("DROP TRIGGER IF EXISTS human_decisions_prevent_immutable_update ON human_decisions;")

    execute("""
    CREATE TRIGGER human_decisions_prevent_immutable_update
    BEFORE UPDATE ON human_decisions
    FOR EACH ROW
    EXECUTE FUNCTION prevent_immutable_column_update('contract_sha256');
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS human_decisions_prevent_immutable_update ON human_decisions;")

    drop_if_exists index(:human_decisions, [:contract_sha256])

    alter table(:human_decisions) do
      remove :contract_sha256
      remove :source_span
      remove :section_ref
    end
  end
end
