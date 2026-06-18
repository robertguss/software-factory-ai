defmodule Conveyor.Repo.Migrations.AddRunPromptBodySha256 do
  use Ecto.Migration

  def up do
    alter table(:run_prompts) do
      add :body_sha256, :text
    end

    create index(:run_prompts, [:body_sha256])

    execute("""
    CREATE TRIGGER run_prompts_prevent_immutable_update
    BEFORE UPDATE ON run_prompts
    FOR EACH ROW
    EXECUTE FUNCTION prevent_immutable_column_update(
      'template_version',
      'body',
      'body_sha256',
      'output_schema_version'
    );
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS run_prompts_prevent_immutable_update ON run_prompts;")

    drop index(:run_prompts, [:body_sha256])

    alter table(:run_prompts) do
      remove :body_sha256
    end
  end
end
