defmodule Conveyor.Jobs.RunGate do
  @moduledoc """
  Deterministic gate composition worker and gate-only facade.
  """

  use Oban.Worker, queue: :gate, max_attempts: 1

  alias Conveyor.Gate

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    :ok
  end

  @spec run_gate_only!(map(), list(), keyword()) :: Gate.Result.t()
  def run_gate_only!(context, stages, opts \\ []) when is_map(context) and is_list(stages) do
    context
    |> Map.put_new(:mode, :gate_only)
    |> Gate.run!(stages, opts)
  end
end
