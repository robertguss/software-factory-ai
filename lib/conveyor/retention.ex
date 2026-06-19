defmodule Conveyor.Retention do
  @moduledoc """
  Deterministic retention and GC decisions for artifact-like records.
  """

  @protected_holds MapSet.new([:legal, :audit])
  @erasable_classes MapSet.new([:ephemeral])

  @spec gc_plan([map()], keyword()) :: map()
  def gc_plan(records, _opts \\ []) when is_list(records) do
    {erase, keep} = Enum.split_with(records, &erasable?/1)

    %{
      erase: erase,
      keep: keep,
      tombstones: Enum.map(erase, &tombstone/1)
    }
  end

  defp erasable?(record) do
    MapSet.member?(@erasable_classes, Map.get(record, :retention_class)) and
      Map.get(record, :availability) in [:available, :cold, :redacted] and
      not Map.get(record, :active_authority?, false) and
      MapSet.disjoint?(MapSet.new(Map.get(record, :holds, [])), @protected_holds)
  end

  defp tombstone(record) do
    record
    |> Map.take([:id])
    |> Map.put(:availability, :erased)
    |> Map.put(:tombstone?, true)
  end
end
