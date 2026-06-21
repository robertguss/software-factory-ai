defmodule Conveyor.Repo.Migrations.AddGateResultTrustScore do
  @moduledoc """
  ADR-23: persist the calibrated TrustScore verdict on each gate result so
  abstentions (and the score behind every auto-accept) are durable and queryable.
  """

  use Ecto.Migration

  def change do
    alter table(:gate_results) do
      add :trust_score, :map
    end
  end
end
