defmodule Conveyor.Repo.Migrations.AllowNotAssessedReviews do
  use Ecto.Migration

  # m4b2.2: a malformed reviewer output is recorded as a :not_assessed review (fail-closed).
  def up do
    drop constraint(:reviews, :reviews_decision_must_be_known)

    create constraint(:reviews, :reviews_decision_must_be_known,
             check: "decision IN ('accepted', 'needs_rework', 'rejected', 'not_assessed')"
           )
  end

  def down do
    drop constraint(:reviews, :reviews_decision_must_be_known)

    create constraint(:reviews, :reviews_decision_must_be_known,
             check: "decision IN ('accepted', 'needs_rework', 'rejected')"
           )
  end
end
