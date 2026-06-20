defmodule Conveyor.Stations.ContextScout do
  @moduledoc "Station wrapper for building a cited implementation context pack."

  use Conveyor.Station, station: "context_scout"

  alias Conveyor.ContextScout

  @impl Conveyor.Station
  def run(_input, context) do
    context_pack = ContextScout.run!(context.run_attempt.slice_id)

    {:ok,
     %{
       "context_pack_id" => context_pack.id,
       "context_pack_confidence" => Decimal.to_string(context_pack.confidence)
     }}
  end
end
