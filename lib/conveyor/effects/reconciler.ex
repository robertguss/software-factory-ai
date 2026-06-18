defmodule Conveyor.Effects.Reconciler do
  @moduledoc """
  Reconciles stale station effects against externally observed state.

  Phase 1 keeps the external inspection hook deliberately small: callers provide
  an `:inspector` function that receives a `StationEffect` and returns
  `{:ok, observed_status, observed_ref}` where `observed_status` is one of
  `:missing`, `:succeeded`, or `:failed`.
  """

  use Conveyor.Conductor.Child

  alias Conveyor.Factory
  alias Conveyor.Factory.StationEffect
  alias Conveyor.Factory.StationRun

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            checked_station_runs: non_neg_integer(),
            reconciled_effects: non_neg_integer(),
            failed_effects: non_neg_integer()
          }

    @enforce_keys [:checked_station_runs, :reconciled_effects, :failed_effects]
    defstruct [:checked_station_runs, :reconciled_effects, :failed_effects]
  end

  @stale_effect_statuses [:declared, :running, :unknown]

  @spec reconcile!(keyword()) :: Result.t()
  def reconcile!(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:microsecond) end)
    inspector = Keyword.get(opts, :inspector, &default_inspector/1)
    station_runs = stale_station_runs(now)
    station_run_ids = MapSet.new(station_runs, & &1.id)

    effects =
      StationEffect
      |> Ash.read!(domain: Factory)
      |> Enum.filter(
        &(&1.station_run_id in station_run_ids and &1.status in @stale_effect_statuses)
      )

    reconciled =
      Enum.map(effects, fn effect ->
        reconcile_effect!(effect, inspector.(effect), now)
      end)

    Enum.each(station_runs, &fail_station_run!(&1, now))

    %Result{
      checked_station_runs: length(station_runs),
      reconciled_effects: Enum.count(reconciled, &(&1.status == :reconciled)),
      failed_effects: Enum.count(reconciled, &(&1.status == :failed))
    }
  end

  defp stale_station_runs(now) do
    StationRun
    |> Ash.read!(domain: Factory)
    |> Enum.filter(fn station_run ->
      station_run.status == :running and stale_lease?(station_run, now)
    end)
  end

  defp stale_lease?(%StationRun{lease_expires_at: nil}, _now), do: true

  defp stale_lease?(%StationRun{lease_expires_at: expires_at}, now) do
    DateTime.compare(expires_at, now) in [:lt, :eq]
  end

  defp reconcile_effect!(effect, {:ok, :missing, observed_ref}, now) do
    update_effect!(effect, :reconciled, observed_ref, cleanup_status(effect, :completed), now)
  end

  defp reconcile_effect!(effect, {:ok, :succeeded, observed_ref}, now) do
    update_effect!(effect, :reconciled, observed_ref, cleanup_status(effect, :pending), now)
  end

  defp reconcile_effect!(effect, {:ok, :failed, observed_ref}, now) do
    update_effect!(effect, :failed, observed_ref, cleanup_status(effect, :failed), now)
  end

  defp reconcile_effect!(effect, other, now) do
    update_effect!(effect, :failed, inspect(other), cleanup_status(effect, :failed), now)
  end

  defp update_effect!(effect, status, observed_ref, cleanup_status, now) do
    Ash.update!(
      effect,
      %{
        status: status,
        observed_ref: observed_ref,
        cleanup_status: cleanup_status,
        completed_at: now
      },
      domain: Factory
    )
  end

  defp cleanup_status(%StationEffect{cleanup_required: true}, status), do: status
  defp cleanup_status(%StationEffect{cleanup_required: false}, _status), do: :not_required

  defp fail_station_run!(station_run, now) do
    Ash.update!(
      station_run,
      %{
        status: :failed,
        error_category: "effect_reconciled",
        error_message: "stale station effects were reconciled before retry",
        completed_at: now
      },
      domain: Factory
    )
  end

  defp default_inspector(_effect), do: {:ok, :missing, nil}
end
