defmodule Conveyor.Repo.Migrations.AddContextPackFileExcerpts do
  use Ecto.Migration

  def change do
    alter table(:context_packs) do
      add :file_excerpts, {:array, :map}, null: false, default: []
    end
  end
end
