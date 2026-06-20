defmodule Conveyor.Repo.Migrations.UpdateArtifactProjectionIdentity do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:artifacts, [:sha256, :size_bytes],
                     name: :artifacts_unique_sha256_size_bytes_index
                   )

    create index(:artifacts, [:sha256, :size_bytes], name: :artifacts_sha256_size_bytes_index)

    create unique_index(:artifacts, [:run_attempt_id, :projection_path],
             name: :artifacts_unique_run_attempt_projection_path_index,
             where: "run_attempt_id IS NOT NULL"
           )

    create unique_index(:artifacts, [:station_run_id, :projection_path],
             name: :artifacts_unique_station_run_projection_path_index,
             where: "station_run_id IS NOT NULL"
           )
  end

  def down do
    drop_if_exists unique_index(:artifacts, [:station_run_id, :projection_path],
                     name: :artifacts_unique_station_run_projection_path_index
                   )

    drop_if_exists unique_index(:artifacts, [:run_attempt_id, :projection_path],
                     name: :artifacts_unique_run_attempt_projection_path_index
                   )

    drop_if_exists index(:artifacts, [:sha256, :size_bytes],
                     name: :artifacts_sha256_size_bytes_index
                   )

    create unique_index(:artifacts, [:sha256, :size_bytes],
             name: :artifacts_unique_sha256_size_bytes_index
           )
  end
end
