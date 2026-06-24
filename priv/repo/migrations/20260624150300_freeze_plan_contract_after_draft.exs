defmodule Conveyor.Repo.Migrations.FreezePlanContractAfterDraft do
  use Ecto.Migration

  # KTD8 / rows-primary: a Plan's contract is compiled from rows at `lock` time, so it must be
  # writable while the plan is still being authored (`status = 'draft'`) and frozen the moment it
  # is handed to execution. This replaces the unconditional `plans` immutability guard on
  # `contract_sha256` with one that only fires once the plan has left `:draft`. Every plan that has
  # been audited/handed off/run stays immutable, exactly as before.
  def up do
    execute("DROP TRIGGER IF EXISTS plans_prevent_immutable_update ON plans;")

    execute("""
    CREATE TRIGGER plans_freeze_contract_after_draft
    BEFORE UPDATE ON plans
    FOR EACH ROW
    WHEN (OLD.status <> 'draft')
    EXECUTE FUNCTION prevent_immutable_column_update('contract_sha256');
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS plans_freeze_contract_after_draft ON plans;")

    execute("""
    CREATE TRIGGER plans_prevent_immutable_update
    BEFORE UPDATE ON plans
    FOR EACH ROW
    EXECUTE FUNCTION prevent_immutable_column_update('contract_sha256');
    """)
  end
end
