defmodule Conveyor.Repo.Migrations.AddSliceAcceptanceCriteria do
  use Ecto.Migration

  def change do
    alter table(:slices) do
      add :acceptance_criteria, {:array, :map}, null: false, default: []
    end
  end
end
