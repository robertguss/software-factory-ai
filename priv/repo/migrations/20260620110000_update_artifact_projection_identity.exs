defmodule Conveyor.Repo.Migrations.UpdateArtifactProjectionIdentity do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:artifacts, [:sha256, :size_bytes],
                     name: :artifacts_unique_sha256_size_bytes_index
                   )

    create index(:artifacts, [:sha256, :size_bytes], name: :artifacts_sha256_size_bytes_index)

    # Dedupe pre-existing rows so the partial unique index can build on populated
    # data; keep the most-recent artifact per identity. No-op on an empty db
    # (the CI-covered path), data-defense for populated environments.
    execute("""
    DELETE FROM artifacts a USING (
      SELECT id, row_number() OVER (
        PARTITION BY run_attempt_id, projection_path ORDER BY created_at DESC, id DESC
      ) AS rn
      FROM artifacts WHERE run_attempt_id IS NOT NULL
    ) dups
    WHERE a.id = dups.id AND dups.rn > 1
    """)

    create unique_index(:artifacts, [:run_attempt_id, :projection_path],
             name: :artifacts_unique_run_attempt_projection_path_index,
             where: "run_attempt_id IS NOT NULL"
           )

    execute("""
    DELETE FROM artifacts a USING (
      SELECT id, row_number() OVER (
        PARTITION BY station_run_id, projection_path ORDER BY created_at DESC, id DESC
      ) AS rn
      FROM artifacts WHERE station_run_id IS NOT NULL
    ) dups
    WHERE a.id = dups.id AND dups.rn > 1
    """)

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

    # Dedupe by content identity before recreating the old unique index, which
    # would otherwise fail on duplicate (sha256, size_bytes) rows.
    execute("""
    DELETE FROM artifacts a USING (
      SELECT id, row_number() OVER (
        PARTITION BY sha256, size_bytes ORDER BY created_at DESC, id DESC
      ) AS rn
      FROM artifacts
    ) dups
    WHERE a.id = dups.id AND dups.rn > 1
    """)

    create unique_index(:artifacts, [:sha256, :size_bytes],
             name: :artifacts_unique_sha256_size_bytes_index
           )
  end
end
