defmodule Conveyor.Replay do
  @moduledoc """
  R0 replay helpers for rebuilding the human timeline from the append-only ledger.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent

  @spec timeline!() :: [map()]
  def timeline! do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.sort_by(&{DateTime.to_unix(&1.occurred_at, :microsecond), &1.id})
    |> Enum.map(&timeline_entry/1)
  end

  @spec format_timeline([map()]) :: String.t()
  def format_timeline(entries) do
    entries
    |> Enum.map(&Jason.encode!/1)
    |> Enum.join("\n")
  end

  defp timeline_entry(event) do
    %{
      "id" => event.id,
      "occurred_at" => DateTime.to_iso8601(event.occurred_at),
      "type" => event.type,
      "project_id" => event.project_id,
      "slice_id" => event.slice_id,
      "run_attempt_id" => event.run_attempt_id,
      "agent_session_id" => event.agent_session_id,
      "station_run_id" => event.station_run_id,
      "trace_id" => event.trace_id,
      "span_id" => event.span_id,
      "idempotency_key" => event.idempotency_key,
      "payload" => event.payload
    }
  end
end
