defmodule Conveyor.Repo.Migrations.AddArtifactRedactionMetadata do
  use Ecto.Migration

  def change do
    alter table(:artifacts) do
      add :raw_sha256, :text
      add :redacted_sha256, :text
      add :redaction_findings, {:array, :map}, null: false, default: []
    end
  end
end
