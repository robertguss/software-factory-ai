defmodule Conveyor.Demo do
  @moduledoc """
  Hermetic Phase-1 demo path.

  The demo intentionally avoids live provider credentials, CodeScent, and network
  egress. It seeds the sample task graph, runs a deterministic fake-runner station
  through the RunSlice orchestrator, and projects the static artifact bundle.
  """

  alias Conveyor.Artifacts.Projector
  alias Conveyor.Factory
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.RunAttemptLifecycle
  alias Conveyor.RunSlice
  alias Conveyor.SampleTasksSeed

  defmodule FakeRunnerStation do
    @moduledoc false
    use Conveyor.Station, station: "seed"

    @impl Conveyor.Station
    def run(input, _context) do
      artifact = %{
        kind: "evidence",
        media_type: "application/json",
        projection_path: "demo/fake-runner.json",
        content:
          Jason.encode!(
            %{
              schema_version: "conveyor.demo.fake_runner@1",
              adapter: "fake",
              network: "none",
              credentials_required: false,
              input_sha256: Conveyor.Station.digest(input)
            },
            pretty: true
          )
      }

      {:ok,
       %{
         "adapter" => "fake",
         "network" => "none",
         "credentials_required" => false,
         artifacts: [artifact]
       }}
    end
  end

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            run_attempt: RunAttempt.t(),
            run_slice: RunSlice.Result.t(),
            projection: Projector.Result.t()
          }

    @enforce_keys [:run_attempt, :run_slice, :projection]
    defstruct [:run_attempt, :run_slice, :projection]
  end

  @spec run!(keyword()) :: Result.t()
  def run!(opts \\ []) do
    seed = SampleTasksSeed.seed!(Keyword.take(opts, [:repo_root, :base_commit]))
    run_attempt = get_or_create_run_attempt!(seed)

    run_slice =
      RunSlice.run!(run_attempt,
        station_modules: %{"seed" => FakeRunnerStation},
        actor: Keyword.get(opts, :actor, "demo"),
        blob_root: Keyword.get(opts, :blob_root, ".conveyor/blobs")
      )

    reported_attempt = advance_to_reported!(run_slice.run_attempt, opts)

    projection =
      Projector.project_run!(
        reported_attempt,
        Keyword.take(opts, [:blob_root, :projection_root, :backend])
      )

    %Result{run_attempt: reported_attempt, run_slice: run_slice, projection: projection}
  end

  @spec summary(Result.t()) :: map()
  def summary(%Result{} = result) do
    %{
      "status" => Atom.to_string(result.run_slice.status),
      "adapter" => "fake",
      "network" => "none",
      "credentials_required" => false,
      "run_attempt_id" => result.run_attempt.id,
      "station_count" => length(result.run_slice.station_runs),
      "artifact_count" => result.projection.artifact_count,
      "projection_path" => result.projection.projection_path,
      "manifest_sha256" => result.projection.manifest_sha256,
      "bundle_root_sha256" => result.projection.bundle_root_sha256
    }
  end

  defp get_or_create_run_attempt!(seed) do
    existing =
      RunAttempt
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.slice_id == seed.slice.id and &1.run_spec_id == seed.run_spec.id))

    existing ||
      Ash.create!(
        RunAttempt,
        %{
          slice_id: seed.slice.id,
          run_spec_id: seed.run_spec.id,
          attempt_no: seed.run_spec.attempt_no,
          base_commit: seed.run_spec.base_commit,
          status: :planned,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-demo"
        },
        domain: Factory
      )
  end

  defp advance_to_reported!(%RunAttempt{status: :reported} = run_attempt, _opts), do: run_attempt

  defp advance_to_reported!(%RunAttempt{} = run_attempt, opts) do
    actor = Keyword.get(opts, :actor, "demo")

    run_attempt
    |> transition_unless(:evidence_recorded, :record_evidence, actor)
    |> transition_unless(:reviewed, :review, actor)
    |> transition_unless(:gated, :gate, actor)
    |> transition_unless(:reported, :report, actor)
  end

  defp transition_unless(%RunAttempt{status: status} = run_attempt, status, _action, _actor),
    do: run_attempt

  defp transition_unless(%RunAttempt{} = run_attempt, _status, action, actor) do
    RunAttemptLifecycle.transition!(run_attempt, action,
      actor: actor,
      reason: "hermetic demo lifecycle"
    )
  end
end
