defmodule Conveyor.Repo.Migrations.AddCreatedAtToGateResults do
  @moduledoc """
  enjh: add a `created_at` timestamp to gate_results so verdict selection (conveyor.show,
  ParkedQueue) can resolve multiple verdicts per attempt by true recency instead of the
  deterministic-but-arbitrary uuid-id fallback. Backfills any pre-existing rows with now();
  Ash's `create_timestamp` supplies the value on every new insert thereafter.
  """

  use Ecto.Migration

  def up do
    alter table(:gate_results) do
      add :created_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end
  end

  def down do
    alter table(:gate_results) do
      remove :created_at
    end
  end
end
