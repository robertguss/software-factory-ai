defmodule Conveyor.Repo.Migrations.AddDiffPolicyAlwaysAllowedPathClasses do
  use Ecto.Migration

  def change do
    alter table(:diff_policies) do
      add :always_allowed_path_classes, {:array, :map}, null: false, default: []
    end
  end
end
