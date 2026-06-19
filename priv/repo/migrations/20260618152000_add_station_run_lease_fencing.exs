defmodule Conveyor.Repo.Migrations.AddStationRunLeaseFencing do
  use Ecto.Migration

  def change do
    alter table(:station_runs) do
      add :lease_epoch, :integer, null: false, default: 0
      add :lease_owner_instance_id, :text
      add :lease_acquired_at, :utc_datetime_usec
      add :trace_id, :text
    end

    create index(:station_runs, [:trace_id])
  end
end
