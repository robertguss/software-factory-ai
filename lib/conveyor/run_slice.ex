defmodule Conveyor.RunSlice do
  @moduledoc """
  Happy-path station-plan orchestrator for one RunAttempt.

  The station wrapper owns per-station mechanics such as idempotency, leases,
  heartbeats, effects, artifacts, and station ledger events. This module owns the
  thin conductor loop: load the immutable RunSpec, advance the RunAttempt to
  running, execute station definitions in order, and thread prior station output
  into later station input.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.RunAttemptLifecycle
  alias Conveyor.Station

  defmodule Result do
    @moduledoc "Aggregate result for one RunSlice orchestration pass."

    @type t :: %__MODULE__{
            run_attempt: RunAttempt.t(),
            status: :succeeded | :failed,
            station_results: [Station.Result.t()],
            station_runs: [struct()],
            output: map()
          }

    @enforce_keys [:run_attempt, :status, :station_results, :station_runs, :output]
    defstruct [:run_attempt, :status, :station_results, :station_runs, :output]
  end

  @spec run!(RunAttempt.t() | Ecto.UUID.t(), keyword()) :: Result.t()
  def run!(run_attempt_or_id, opts \\ [])

  def run!(%RunAttempt{} = run_attempt, opts) do
    run_attempt = ensure_running!(run_attempt, opts)
    run_spec = get_by_id!(RunSpec, run_attempt.run_spec_id)
    station_defs = stations!(run_spec)

    {station_results, output, status} =
      Enum.reduce_while(station_defs, {[], %{}, :succeeded}, fn station_def,
                                                                {results, output, _status} ->
        station_input =
          station_def
          |> Map.get("input", %{})
          |> Map.merge(output)

        station_module = station_module!(station_def, opts)
        station_result = Station.execute!(station_module, run_attempt, station_input, opts)
        station_output = station_output(station_result, station_def)
        next_results = results ++ [station_result]
        next_output = Map.merge(output, station_output)

        case station_result.station_run.status do
          :failed -> {:halt, {next_results, next_output, :failed}}
          _status -> {:cont, {next_results, next_output, :succeeded}}
        end
      end)

    %Result{
      run_attempt: get_by_id!(RunAttempt, run_attempt.id),
      status: status,
      station_results: station_results,
      station_runs: Enum.map(station_results, & &1.station_run),
      output: output
    }
  end

  def run!(run_attempt_id, opts) when is_binary(run_attempt_id) do
    run_attempt_id
    |> then(&get_by_id!(RunAttempt, &1))
    |> run!(opts)
  end

  defp ensure_running!(%RunAttempt{status: :planned} = run_attempt, opts) do
    lifecycle_opts =
      opts
      |> Keyword.take([:actor])
      |> Keyword.put(:reason, "run slice orchestration")
      |> maybe_put_occurred_at(opts)

    RunAttemptLifecycle.transition!(run_attempt, :start, lifecycle_opts)
  end

  defp ensure_running!(%RunAttempt{} = run_attempt, _opts), do: run_attempt

  defp maybe_put_occurred_at(lifecycle_opts, opts) do
    case Keyword.fetch(opts, :now) do
      {:ok, now} -> Keyword.put(lifecycle_opts, :occurred_at, now)
      :error -> lifecycle_opts
    end
  end

  defp stations!(%RunSpec{station_plan: %{"stations" => stations}}) when is_list(stations) do
    stations
  end

  defp stations!(%RunSpec{id: id}) do
    raise ArgumentError, "RunSpec #{id} has no station_plan.stations"
  end

  defp station_module!(station_def, opts) do
    key = Map.fetch!(station_def, "key")
    registry = Keyword.get(opts, :station_modules, %{})

    module =
      Map.get(registry, key) ||
        Map.get(registry, String.to_atom(key)) ||
        module_from_station_def(station_def)

    cond do
      is_nil(module) ->
        raise ArgumentError, "No station module registered for #{inspect(key)}"

      not Code.ensure_loaded?(module) ->
        raise ArgumentError, "Station module #{inspect(module)} is not loaded"

      not function_exported?(module, :station_key, 0) ->
        raise ArgumentError,
              "Station module #{inspect(module)} does not implement Conveyor.Station"

      module.station_key() != key ->
        raise ArgumentError,
              "Station module #{inspect(module)} key #{inspect(module.station_key())} does not match #{inspect(key)}"

      true ->
        module
    end
  end

  defp module_from_station_def(%{"module" => module_name}) when is_binary(module_name) do
    module_name
    |> String.trim_leading("Elixir.")
    |> String.split(".")
    |> Module.concat()
  end

  defp module_from_station_def(_station_def), do: nil

  defp station_output(%Station.Result{reused?: false, output: output}, _station_def), do: output

  defp station_output(%Station.Result{reused?: true}, station_def) do
    Map.get(station_def, "output", %{})
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end
end
