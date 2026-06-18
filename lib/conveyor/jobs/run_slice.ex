defmodule Conveyor.Jobs.RunSlice do
  @moduledoc "Oban worker that advances one RunAttempt through its station plan."

  use Oban.Worker, queue: :conductor, max_attempts: 1

  alias Conveyor.RunSlice

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"run_attempt_id" => run_attempt_id} = args}) do
    run_attempt_id
    |> RunSlice.run!(run_opts(args))
    |> case do
      %RunSlice.Result{status: :succeeded} -> :ok
      %RunSlice.Result{status: :failed} -> {:error, :station_failed}
    end
  end

  def perform(%Oban.Job{}) do
    {:error, :missing_run_attempt_id}
  end

  defp run_opts(args) do
    [
      actor: Map.get(args, "actor", "run_slice"),
      blob_root: Map.get(args, "blob_root", ".conveyor/blobs"),
      station_modules: station_modules()
    ]
  end

  defp station_modules do
    Process.get(:conveyor_run_slice_station_modules) ||
      Application.get_env(:conveyor, :station_modules, %{})
  end
end
