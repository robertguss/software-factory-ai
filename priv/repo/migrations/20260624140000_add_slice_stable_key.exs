defmodule Conveyor.Repo.Migrations.AddSliceStableKey do
  @moduledoc """
  Persist the plan-authored stable key (e.g. "SLICE-005") on each slice. The
  ledger run-story keys slices by this stable key while DB rows key by UUID;
  storing it lets the run-story read-back (Conveyor.RunReadModel) join the two,
  so a slice's gate verdict / rework count surface honestly instead of as nil.
  """

  use Ecto.Migration

  def change do
    alter table(:slices) do
      add :stable_key, :string
    end
  end
end
