defmodule Conveyor.Repo.Migrations.AddContextPackCreatedAt do
  @moduledoc """
  Adds a creation timestamp to context_packs so PromptBuilder can deterministically
  select the latest ContextPack for a slice instead of relying on read order.
  """

  use Ecto.Migration

  def up do
    alter table(:context_packs) do
      add :created_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end
  end

  def down do
    alter table(:context_packs) do
      remove :created_at
    end
  end
end
