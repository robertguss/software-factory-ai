defmodule Conveyor.Repo.Migrations.EnforceLedgerEventsAppendOnly do
  use Ecto.Migration

  @function_name "prevent_ledger_event_mutation"
  @trigger_name "ledger_events_append_only"

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION #{@function_name}()
    RETURNS trigger AS $$
    BEGIN
      RAISE EXCEPTION 'ledger_events are append-only and cannot be %', TG_OP
        USING ERRCODE = 'check_violation';
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER #{@trigger_name}
    BEFORE UPDATE OR DELETE ON ledger_events
    FOR EACH ROW
    EXECUTE FUNCTION #{@function_name}();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS #{@trigger_name} ON ledger_events;")
    execute("DROP FUNCTION IF EXISTS #{@function_name}();")
  end
end
