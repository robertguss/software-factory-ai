defmodule Conveyor.Station do
  @moduledoc """
  Shared execution wrapper for station workers.

  Station modules keep their domain logic in `run/2`; this wrapper owns the
  common mechanics around idempotency, leases, declared effects, artifact rows,
  and station ledger events.
  """

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationEffect
  alias Conveyor.Factory.StationRun
  alias Conveyor.Ledger
  alias Conveyor.Repo

  defmodule Context do
    @moduledoc "Execution context passed to station logic."

    @type t :: %__MODULE__{
            run_attempt: struct(),
            station_run: struct(),
            input: map(),
            lease_owner: String.t()
          }

    @enforce_keys [:run_attempt, :station_run, :input, :lease_owner]
    defstruct [:run_attempt, :station_run, :input, :lease_owner]
  end

  defmodule Result do
    @moduledoc "Result returned by the station execution wrapper."

    @type t :: %__MODULE__{
            station_run: struct(),
            effects: [struct()],
            artifacts: [struct()],
            ledger_event: struct() | nil,
            output: map(),
            reused?: boolean()
          }

    @enforce_keys [:station_run, :effects, :artifacts, :output, :reused?]
    defstruct [:station_run, :effects, :artifacts, :ledger_event, :output, :reused?]
  end

  @callback station_key() :: String.t()
  @callback station_spec(map()) :: map()
  @callback station_spec_sha256(map()) :: String.t()
  @callback input_sha256(map()) :: String.t()
  @callback effects(map()) :: [atom() | map()]
  @callback run(map(), Context.t()) :: {:ok, map()} | {:error, term()}

  defmacro __using__(opts) do
    station_key = Keyword.fetch!(opts, :station)

    quote do
      @behaviour Conveyor.Station

      @impl Conveyor.Station
      def station_key, do: unquote(station_key)

      @impl Conveyor.Station
      def station_spec(input) do
        %{
          "station" => station_key(),
          "module" => inspect(__MODULE__),
          "input_sha256" => input_sha256(input)
        }
      end

      @impl Conveyor.Station
      def station_spec_sha256(input), do: Conveyor.Station.digest(station_spec(input))

      @impl Conveyor.Station
      def input_sha256(input), do: Conveyor.Station.digest(input)

      @impl Conveyor.Station
      def effects(_input), do: []

      def execute!(run_attempt, input \\ %{}, opts \\ []) do
        Conveyor.Station.execute!(__MODULE__, run_attempt, input, opts)
      end

      defoverridable station_spec: 1, station_spec_sha256: 1, input_sha256: 1, effects: 1
    end
  end

  @spec execute!(module(), RunAttempt.t(), map(), keyword()) :: Result.t()
  def execute!(station_module, %RunAttempt{} = run_attempt, input \\ %{}, opts \\ [])
      when is_atom(station_module) and is_map(input) do
    lease_owner = Keyword.get(opts, :lease_owner) || Keyword.get(opts, :actor) || "station"
    station_run = acquire_station_run!(station_module, run_attempt, input, lease_owner, opts)

    if station_run.status == :succeeded do
      %Result{
        station_run: station_run,
        effects: effects_for(station_run.id),
        artifacts: artifacts_for(station_run.id),
        ledger_event: ledger_event_for(station_run.id),
        output: %{},
        reused?: true
      }
    else
      effects = declare_effects!(station_module, station_run, input)

      context = %Context{
        run_attempt: run_attempt,
        station_run: station_run,
        input: input,
        lease_owner: lease_owner
      }

      case station_module.run(input, context) do
        {:ok, output} when is_map(output) ->
          complete_station!(station_run, run_attempt, output, opts)

        {:error, reason} ->
          fail_station!(station_run, run_attempt, reason, opts)
      end
      |> Map.put(:effects, effects)
    end
  end

  @spec heartbeat!(StationRun.t(), keyword()) :: StationRun.t()
  def heartbeat!(%StationRun{} = station_run, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:microsecond) end)
    lease_seconds = Keyword.get(opts, :lease_seconds, 60)

    Ash.update!(
      station_run,
      %{
        heartbeat_at: now,
        lease_expires_at: DateTime.add(now, lease_seconds, :second)
      },
      domain: Factory
    )
  end

  @spec idempotency_key(Ecto.UUID.t(), String.t(), String.t(), pos_integer()) :: String.t()
  def idempotency_key(run_attempt_id, station_key, station_spec_sha256, attempt_no) do
    "#{run_attempt_id}:#{station_key}:#{station_spec_sha256}:#{attempt_no}"
  end

  @spec digest(term()) :: String.t()
  def digest(value), do: value |> canonical_json() |> sha256()

  defp acquire_station_run!(station_module, run_attempt, input, lease_owner, opts) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:microsecond) end)
    lease_seconds = Keyword.get(opts, :lease_seconds, 60)
    station_key = station_module.station_key()
    station_spec_sha256 = station_module.station_spec_sha256(input)

    attrs = %{
      run_attempt_id: run_attempt.id,
      slice_id: run_attempt.slice_id,
      station: station_key,
      attempt_no: run_attempt.attempt_no,
      station_spec_sha256: station_spec_sha256,
      idempotency_key:
        idempotency_key(run_attempt.id, station_key, station_spec_sha256, run_attempt.attempt_no),
      input_sha256: station_module.input_sha256(input),
      status: :queued,
      artifact_refs: []
    }

    station_run =
      case find_one(StationRun, &(&1.idempotency_key == attrs.idempotency_key)) do
        nil -> Ash.create!(StationRun, attrs, domain: Factory)
        existing -> existing
      end

    if station_run.status == :succeeded do
      station_run
    else
      Ash.update!(
        station_run,
        %{
          status: :running,
          lease_owner: lease_owner,
          lease_expires_at: DateTime.add(now, lease_seconds, :second),
          heartbeat_at: now,
          started_at: station_run.started_at || now
        },
        domain: Factory
      )
    end
  end

  defp declare_effects!(station_module, station_run, input) do
    input
    |> station_module.effects()
    |> Enum.with_index(1)
    |> Enum.map(fn {effect, index} ->
      attrs = effect_attrs(effect, station_run.id, index)

      case find_one(StationEffect, &(&1.idempotency_key == attrs.idempotency_key)) do
        nil -> Ash.create!(StationEffect, attrs, domain: Factory)
        existing -> existing
      end
    end)
  end

  defp effect_attrs(effect_kind, station_run_id, index) when is_atom(effect_kind) do
    effect_attrs(%{effect_kind: effect_kind}, station_run_id, index)
  end

  defp effect_attrs(effect, station_run_id, index) when is_map(effect) do
    effect_kind = Map.get(effect, :effect_kind) || Map.fetch!(effect, "effect_kind")

    %{
      station_run_id: station_run_id,
      effect_kind: effect_kind,
      idempotency_key:
        Map.get(effect, :idempotency_key) ||
          Map.get(effect, "idempotency_key") ||
          "effect:#{station_run_id}:#{effect_kind}:#{index}",
      cleanup_required:
        Map.get(effect, :cleanup_required, Map.get(effect, "cleanup_required", false)),
      cleanup_status:
        Map.get(effect, :cleanup_status, Map.get(effect, "cleanup_status", :not_required))
    }
  end

  defp complete_station!(station_run, run_attempt, output, opts) do
    Repo.transaction(fn ->
      {artifacts, artifact_notifications} =
        write_artifacts!(
          station_run,
          run_attempt,
          Map.get(output, :artifacts, Map.get(output, "artifacts", [])),
          opts
        )

      artifact_refs = Enum.map(artifacts, & &1.projection_path)
      output_payload = Map.drop(output, [:artifacts, "artifacts"])
      output_sha256 = digest(%{"output" => output_payload, "artifact_refs" => artifact_refs})

      completed_at =
        Keyword.get_lazy(opts, :completed_at, fn -> DateTime.utc_now(:microsecond) end)

      {updated_station_run, station_notifications} =
        Ash.update!(
          station_run,
          %{
            status: :succeeded,
            output_sha256: output_sha256,
            artifact_refs: artifact_refs,
            completed_at: completed_at
          },
          domain: Factory,
          return_notifications?: true
        )

      project = project_for!(run_attempt.slice_id)

      {ledger_event, ledger_notifications} =
        Ledger.write!(
          %{
            project_id: project.id,
            slice_id: run_attempt.slice_id,
            run_attempt_id: run_attempt.id,
            station_run_id: station_run.id,
            idempotency_key: "station:#{station_run.id}:succeeded",
            type: "station.succeeded",
            payload: %{
              "station" => station_run.station,
              "station_run_id" => station_run.id,
              "run_attempt_id" => run_attempt.id,
              "output_sha256" => output_sha256,
              "artifact_refs" => artifact_refs
            },
            occurred_at: completed_at
          },
          return_notifications?: true
        )

      {updated_station_run, artifacts, ledger_event,
       artifact_notifications ++ station_notifications ++ ledger_notifications}
    end)
    |> case do
      {:ok, {updated_station_run, artifacts, ledger_event, notifications}} ->
        Ash.Notifier.notify(notifications)

        %Result{
          station_run: updated_station_run,
          effects: [],
          artifacts: artifacts,
          ledger_event: ledger_event,
          output: output,
          reused?: false
        }

      {:error, reason} ->
        raise reason
    end
  end

  defp fail_station!(station_run, run_attempt, reason, opts) do
    failed_at = Keyword.get_lazy(opts, :completed_at, fn -> DateTime.utc_now(:microsecond) end)
    message = Exception.message(normalize_error(reason))

    updated =
      Ash.update!(
        station_run,
        %{
          status: :failed,
          error_category: "station_error",
          error_message: message,
          completed_at: failed_at
        },
        domain: Factory
      )

    project = project_for!(run_attempt.slice_id)

    ledger_event =
      Ledger.write!(%{
        project_id: project.id,
        slice_id: run_attempt.slice_id,
        run_attempt_id: run_attempt.id,
        station_run_id: station_run.id,
        idempotency_key: "station:#{station_run.id}:failed",
        type: "station.failed",
        payload: %{
          "station" => station_run.station,
          "station_run_id" => station_run.id,
          "run_attempt_id" => run_attempt.id,
          "error_message" => message
        },
        occurred_at: failed_at
      })

    %Result{
      station_run: updated,
      effects: [],
      artifacts: [],
      ledger_event: ledger_event,
      output: %{"error" => message},
      reused?: false
    }
  end

  defp write_artifacts!(station_run, run_attempt, artifacts, opts) do
    artifacts
    |> Enum.map(&write_artifact!(station_run, run_attempt, &1, opts))
    |> Enum.unzip()
    |> then(fn {artifacts, notifications} -> {artifacts, List.flatten(notifications)} end)
  end

  defp write_artifact!(station_run, run_attempt, artifact, opts) do
    content = Map.get(artifact, :content) || Map.get(artifact, "content") || ""
    blob = BlobStore.write!(content, blob_root: Keyword.get(opts, :blob_root, ".conveyor/blobs"))
    sha256 = Map.get(artifact, :sha256, Map.get(artifact, "sha256", "sha256:#{blob.sha256}"))
    size_bytes = Map.get(artifact, :size_bytes, Map.get(artifact, "size_bytes", blob.size_bytes))

    attrs = %{
      run_attempt_id: run_attempt.id,
      station_run_id: station_run.id,
      kind: Map.get(artifact, :kind, Map.get(artifact, "kind", "station-output")),
      media_type:
        Map.get(artifact, :media_type, Map.get(artifact, "media_type", "application/json")),
      projection_path:
        Map.get(artifact, :projection_path) ||
          Map.get(artifact, "projection_path") ||
          "artifacts/stations/#{station_run.station}/#{blob.sha256}.json",
      blob_ref: Map.get(artifact, :blob_ref, Map.get(artifact, "blob_ref", blob.ref)),
      sha256: sha256,
      size_bytes: size_bytes,
      subject_kind:
        Map.get(artifact, :subject_kind, Map.get(artifact, "subject_kind", "station_run")),
      producer: Map.get(artifact, :producer, Map.get(artifact, "producer", station_run.station)),
      schema_version:
        Map.get(
          artifact,
          :schema_version,
          Map.get(artifact, "schema_version", "conveyor.artifact@1")
        ),
      sensitivity: Map.get(artifact, :sensitivity, Map.get(artifact, "sensitivity", :internal))
    }

    case find_one(Artifact, &(&1.sha256 == attrs.sha256 and &1.size_bytes == attrs.size_bytes)) do
      nil -> Ash.create!(Artifact, attrs, domain: Factory, return_notifications?: true)
      existing -> {existing, []}
    end
  end

  defp effects_for(station_run_id) do
    StationEffect
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.station_run_id == station_run_id))
    |> Enum.sort_by(& &1.idempotency_key)
  end

  defp artifacts_for(station_run_id) do
    Artifact
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.station_run_id == station_run_id))
    |> Enum.sort_by(& &1.projection_path)
  end

  defp ledger_event_for(station_run_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.station_run_id == station_run_id and &1.type == "station.succeeded"))
  end

  defp project_for!(slice_id) do
    slice = get_by_id!(Slice, slice_id)
    epic = get_by_id!(Epic, slice.epic_id)
    plan = get_by_id!(Plan, epic.plan_id)
    get_by_id!(Project, plan.project_id)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp find_one(resource, predicate) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(predicate)
  end

  defp normalize_error(%_{} = error), do: error
  defp normalize_error(reason), do: RuntimeError.exception(inspect(reason))

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp sha256(content) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)
  end
end
