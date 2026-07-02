defmodule Conveyor.Repo.Migrations.AddGateResultParkReason do
  use Ecto.Migration

  # a3hf.1.3.1: typed park-reason on the gate result (nullable — only abstain/park results carry one).
  def change do
    alter table(:gate_results) do
      add :park_reason, :text
    end
  end
end
