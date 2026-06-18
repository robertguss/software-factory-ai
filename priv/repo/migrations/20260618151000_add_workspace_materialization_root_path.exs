defmodule Conveyor.Repo.Migrations.AddWorkspaceMaterializationRootPath do
  @moduledoc """
  Persists the deletable temp root for a materialized workspace. The SandboxReaper
  only has the DB record (not the in-memory Materialized struct), so without this the
  reaper deleted the project subdirectory and leaked the parent temp directory for
  subdirectory projects.
  """

  use Ecto.Migration

  def up do
    alter table(:workspace_materializations) do
      add :root_path, :text
    end
  end

  def down do
    alter table(:workspace_materializations) do
      remove :root_path
    end
  end
end
