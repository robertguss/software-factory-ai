defmodule Conveyor.Repo.Migrations.CreateTaskDependencies do
  use Ecto.Migration

  def change do
    create table(:task_dependencies, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :from_slice_id, references(:slices, type: :uuid, on_delete: :delete_all), null: false
      add :to_slice_id, references(:slices, type: :uuid, on_delete: :delete_all), null: false

      add :kind, :text, null: false, default: "execution_hard"
    end

    create constraint(:task_dependencies, :task_dependencies_no_self_loop,
             check: "from_slice_id <> to_slice_id"
           )

    create unique_index(:task_dependencies, [:from_slice_id, :to_slice_id],
             name: :task_dependencies_unique_edge_index
           )

    create index(:task_dependencies, [:from_slice_id])
    create index(:task_dependencies, [:to_slice_id])
  end
end
