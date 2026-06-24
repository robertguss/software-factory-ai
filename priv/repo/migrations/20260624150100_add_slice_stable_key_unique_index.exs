defmodule Conveyor.Repo.Migrations.AddSliceStableKeyUniqueIndex do
  use Ecto.Migration

  def change do
    # KTD7 enforcement: stable keys are unique per epic. NULL stable_keys stay distinct under a
    # Postgres unique index, so pre-existing rows without a stable key are unaffected.
    create unique_index(:slices, [:epic_id, :stable_key],
             name: :slices_unique_epic_stable_key_index
           )
  end
end
