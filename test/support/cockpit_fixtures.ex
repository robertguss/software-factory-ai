defmodule Conveyor.CockpitFixtures do
  @moduledoc """
  Seed helpers for the cockpit LiveView tests (U3–U6): a Plan with epics, slices,
  and `TaskDependency` edges, plus the run-state overlays — `run.started`/
  `run.slice_outcome` ledger events and a running `StationRun` (via the full
  RunSpec → RunAttempt → StationRun chain).
  """

  alias Conveyor.Factory

  alias Conveyor.Factory.{
    Epic,
    Plan,
    Project,
    RunAttempt,
    RunSpec,
    Slice,
    StationRun,
    TaskDependency
  }

  alias Conveyor.Ledger

  @doc """
  Create a plan with slices and edges.

  `slice_specs` is a list of `{stable_key, state}`; `edge_specs` is a list of
  `{from_stable_key, to_stable_key}` (from → to means *to depends on from*).
  Returns `%{project:, plan:, epic:, slices: %{stable_key => Slice}}`.
  """
  def seed_plan(slice_specs, edge_specs \\ []) do
    # Unique per call so a test may seed more than one plan (e.g. a second plan to
    # exercise the out-of-plan ping filter) without colliding on project/plan
    # identities.
    uid = System.unique_integer([:positive])

    project =
      Ash.create!(
        Project,
        %{name: "Cockpit proj #{uid}", local_path: "/tmp/cockpit-#{uid}", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Cockpit plan #{uid}",
          intent: "Exercise the cockpit.",
          source_document: "docs/cockpit-plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan-#{uid}"),
          status: :active
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{
          plan_id: plan.id,
          title: "Cockpit epic",
          description: "Graph slices.",
          status: :in_progress
        },
        domain: Factory
      )

    slices =
      slice_specs
      |> Enum.with_index(1)
      |> Map.new(fn {{stable_key, state}, position} ->
        slice =
          Ash.create!(
            Slice,
            %{
              epic_id: epic.id,
              title: "Slice #{stable_key}",
              stable_key: stable_key,
              position: position,
              state: state
            },
            domain: Factory
          )

        {stable_key, slice}
      end)

    Enum.each(edge_specs, fn {from, to} ->
      Ash.create!(
        TaskDependency,
        %{from_slice_id: slices[from].id, to_slice_id: slices[to].id, kind: :execution_hard},
        domain: Factory
      )
    end)

    %{project: project, plan: plan, epic: epic, slices: slices}
  end

  def seed_run_started(run_id, slice_keys, occurred_at) do
    Ledger.write!(%{
      project_id: any_project_id(),
      idempotency_key: "#{run_id}:started",
      type: "run.started",
      payload: %{"run_id" => run_id, "slice_ids" => slice_keys},
      occurred_at: occurred_at
    })
  end

  def seed_outcome(run_id, stable_key, status, sequence, occurred_at) do
    Ledger.write!(%{
      project_id: any_project_id(),
      idempotency_key: "#{run_id}:#{stable_key}:#{sequence}",
      type: "run.slice_outcome",
      payload: %{
        "run_id" => run_id,
        "slice_id" => stable_key,
        "sequence" => sequence,
        "status" => status,
        "blocked_by" => [],
        "findings" => []
      },
      occurred_at: occurred_at
    })
  end

  @doc """
  Seed a completed `RunAttempt` for `slice` carrying a gate verdict — the
  gate-waiting attention signal (`outcome` is one of `RunAttempt`'s human-routing
  verdicts). No running station; just the attempt + its RunSpec.
  """
  def seed_attempt_outcome(slice, outcome, status \\ :gated) do
    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

    Ash.create!(
      RunAttempt,
      %{
        slice_id: slice.id,
        run_spec_id: run_spec.id,
        attempt_no: 1,
        base_commit: run_spec.base_commit,
        status: status,
        outcome: outcome,
        orchestrator_version: "conveyor@0.1.0",
        trace_id: "trace-cockpit",
        started_at: DateTime.utc_now()
      },
      domain: Factory
    )
  end

  @doc "Seed a running StationRun for `slice`, started at `started_at`, plus its RunAttempt/RunSpec."
  def seed_running_station(slice, started_at) do
    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: run_spec.base_commit,
          status: :running,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-cockpit",
          started_at: started_at
        },
        domain: Factory
      )

    Ash.create!(
      StationRun,
      %{
        run_attempt_id: run_attempt.id,
        slice_id: slice.id,
        station: "implement",
        attempt_no: 1,
        station_spec_sha256: digest("station"),
        idempotency_key: "#{run_attempt.id}:implement:1",
        input_sha256: digest("input"),
        status: :running,
        started_at: started_at
      },
      domain: Factory
    )
  end

  defp any_project_id do
    case Ash.read!(Project, domain: Factory) do
      [project | _] ->
        project.id

      [] ->
        Ash.create!(
          Project,
          %{name: "Ledger proj", local_path: "/tmp/ledger", default_branch: "main"},
          domain: Factory
        ).id
    end
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec:#{slice_id}")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/attempt-1.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: %{
        "schema_version" => "conveyor.station_plan@1",
        "stations" => [
          %{
            "key" => "implement",
            "input" => %{"run_spec_sha256" => run_spec_sha256},
            "output" => %{"run_spec_sha256" => run_spec_sha256}
          }
        ]
      },
      station_plan_sha256: digest("station-plan"),
      container_image_ref: "ghcr.io/conveyor/runner:latest",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
