defmodule Conveyor.Repo.Migrations.AddReviewRubricSha256 do
  use Ecto.Migration

  def change do
    alter table(:reviews) do
      add :rubric_sha256, :text
    end
  end
end
