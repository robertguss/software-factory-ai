defmodule Conveyor.Jobs.ReconcileStaleEffects do
  @moduledoc "Periodic stale side-effect reconciliation worker."

  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Conveyor.Effects.Reconciler

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args
    |> opts_from_args()
    |> Reconciler.reconcile!()

    :ok
  end

  defp opts_from_args(args) do
    case Map.get(args, "now") || Map.get(args, :now) do
      nil -> []
      now when is_binary(now) -> [now: parse_now!(now)]
      %DateTime{} = now -> [now: now]
    end
  end

  defp parse_now!(now) do
    case DateTime.from_iso8601(now) do
      {:ok, parsed, _offset} ->
        parsed

      {:error, reason} ->
        raise ArgumentError, "invalid reconciliation timestamp #{inspect(now)}: #{reason}"
    end
  end
end
