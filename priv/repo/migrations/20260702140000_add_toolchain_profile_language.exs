defmodule Conveyor.Repo.Migrations.AddToolchainProfileLanguage do
  use Ecto.Migration

  # tt6v.2: runner identity on the toolchain profile. Append-only — existing rows default to the
  # python profile (language/env_prep/result_format), preserving the current pytest path.
  def change do
    alter table(:toolchain_profiles) do
      add :language, :text, null: false, default: "python"
      add :env_prep, :text, null: false, default: "python_venv"
      add :default_result_format, :text, null: false, default: "junit"
    end
  end
end
