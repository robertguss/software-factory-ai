defmodule Conveyor.Repo.Migrations.AddImmutableFieldGuards do
  use Ecto.Migration

  @trigger_function "prevent_immutable_column_update"

  @guards [
    plans: [:contract_sha256],
    requirements: [:contract_sha256],
    agent_briefs: [:contract_sha256],
    contract_locks: [
      :plan_contract_sha256,
      :brief_sha256,
      :acceptance_criteria_sha256,
      :required_tests_sha256,
      :test_pack_sha256,
      :verification_commands_sha256,
      :agents_md_sha256,
      :policy_sha256
    ],
    test_packs: [:test_pack_sha256],
    test_pack_calibrations: [:base_commit],
    run_specs: [
      :run_spec_sha256,
      :base_commit,
      :contract_lock_sha256,
      :policy_sha256,
      :diff_policy_sha256,
      :test_pack_sha256,
      :station_plan_sha256,
      :container_image_digest,
      :budget_sha256
    ],
    run_attempts: [:base_commit],
    agent_sessions: [:base_commit],
    patch_sets: [:base_commit, :patch_ref, :patch_sha256],
    workspace_materializations: [:base_commit],
    reviews: [:dossier_sha256],
    gate_results: [:gate_code_sha256, :policy_sha256, :contract_lock_sha256],
    artifacts: [:blob_ref, :sha256],
    run_bundles: [:manifest_ref, :manifest_sha256, :bundle_root_sha256],
    gate_health: [
      :freshness_key_sha256,
      :gate_code_sha256,
      :policy_sha256,
      :test_pack_sha256,
      :container_image_digest,
      :code_quality_profile_sha256
    ],
    human_approvals: [:external_tree_sha256],
    external_changes: [:external_patch_sha256],
    patch_equivalences: [:accepted_patch_sha256, :external_patch_sha256],
    ledger_events: [:idempotency_key, :type, :payload, :occurred_at]
  ]

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION #{@trigger_function}()
    RETURNS trigger AS $$
    DECLARE
      column_name text;
    BEGIN
      FOREACH column_name IN ARRAY TG_ARGV LOOP
        IF to_jsonb(OLD) -> column_name IS DISTINCT FROM to_jsonb(NEW) -> column_name THEN
          RAISE EXCEPTION 'immutable column %.% cannot be updated', TG_TABLE_NAME, column_name
            USING ERRCODE = 'check_violation';
        END IF;
      END LOOP;

      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    for {table, columns} <- @guards do
      trigger_name = trigger_name(table)
      column_args = columns |> Enum.map(&"'#{&1}'") |> Enum.join(", ")

      execute("""
      CREATE TRIGGER #{trigger_name}
      BEFORE UPDATE ON #{table}
      FOR EACH ROW
      EXECUTE FUNCTION #{@trigger_function}(#{column_args});
      """)
    end
  end

  def down do
    for {table, _columns} <- @guards do
      execute("DROP TRIGGER IF EXISTS #{trigger_name(table)} ON #{table};")
    end

    execute("DROP FUNCTION IF EXISTS #{@trigger_function}();")
  end

  defp trigger_name(table), do: "#{table}_prevent_immutable_update"
end
