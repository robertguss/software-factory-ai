defmodule Conveyor.FactoryFixtures do
  @moduledoc false

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun
  alias Conveyor.Ledger

  def create_artifact_run!(opts \\ []) do
    blob_root = Keyword.fetch!(opts, :blob_root)
    artifact_content = Keyword.get(opts, :artifact_content, "artifact\n")
    projection_path = Keyword.get(opts, :projection_path, "evidence.json")
    sha256 = digest_bytes(artifact_content)

    project =
      Ash.create!(
        Project,
        %{
          name: Keyword.get(opts, :project_name, "Replay fixture"),
          local_path: Keyword.get(opts, :local_path, "/tmp/replay-fixture"),
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Replay fixture plan",
          intent: "Regenerate artifacts.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Replay fixture epic", description: "Artifacts."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Replay fixture slice", position: 1},
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id, opts), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: run_spec.base_commit,
          status: :planned,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-replay"
        },
        domain: Factory
      )

    station_run =
      Ash.create!(
        StationRun,
        %{
          run_attempt_id: run_attempt.id,
          slice_id: slice.id,
          station: "artifact",
          attempt_no: 1,
          station_spec_sha256: digest("station"),
          idempotency_key: "#{run_attempt.id}:artifact:#{digest("station")}:1",
          input_sha256: digest("input")
        },
        domain: Factory
      )

    blob = BlobStore.write!(artifact_content, blob_root: blob_root)

    artifact =
      Ash.create!(
        Artifact,
        %{
          run_attempt_id: run_attempt.id,
          station_run_id: station_run.id,
          kind: "run-log",
          media_type: "text/plain",
          projection_path: projection_path,
          blob_ref: blob.ref,
          sha256: sha256,
          size_bytes: byte_size(artifact_content),
          subject_kind: "run_attempt",
          producer: "gate",
          schema_version: "conveyor.artifact@1",
          sensitivity: :internal
        },
        domain: Factory
      )

    %{
      artifact: artifact,
      artifact_content: artifact_content,
      project: project,
      projection_path: projection_path,
      run_attempt: run_attempt,
      station_run: station_run
    }
  end

  @doc """
  Build an N-slice run with a committed ledger stream, for `Conveyor.RunReadModel` tests.

  Builds Project -> Plan -> Epic -> N Slices, and per slice a `RunAttempt` (plus optional
  extra attempts for rework, an optional `GateResult` carrying `stages`/`trust_score`, and an
  optional `AgentSession`). Emits the run ledger stream via `Conveyor.Ledger.write!`:

    * one `run.started` (payload `"run_id"` + `"slice_ids"` in order),
    * one `run.slice_outcome` per slice that has one (payload `"run_id"`, `"slice_id"`,
      `"sequence"`, `"status"`, `"run_attempt_outcome"`, ...),
    * a terminal `run.finished` / `run.reaped` (or none, for the interrupted case).

  `opts`:
    * `:slices` (required) — a list of per-slice spec maps, in run order. Each may carry:
        * `:status` — the `run.slice_outcome` "status" (e.g. "passed", "parked"); when omitted
          the slice emits NO outcome event (the interrupted / stop-point case).
        * `:run_attempt_outcome` — the attempt outcome string in the outcome payload.
        * `:attempts` — number of `RunAttempt` rows to build for the slice (default 1; >1 for
          rework). The last/highest `attempt_no` is the "latest".
        * `:outcome` — the `RunAttempt.outcome` atom for the latest attempt (default `:none`).
        * `:gate` — a map `%{stages: [...], trust_score: %{...}}` to build a `GateResult` on the
          latest attempt (string-keyed stage maps, as persisted). Either key is optional.
        * `:session` — a map `%{tokens: int | nil, cost_estimate: term | nil}` to build an
          `AgentSession` on the latest attempt. `nil` values exercise the spend-unknown path.
    * `:terminal` — `:finished` (default), `:reaped`, or `:none` (no terminal event).
    * `:run_id` — override the generated run id.

  Returns `%{run_id:, project:, plan:, epic:, slices: [%Slice{}], run_attempts: %{slice_id => [%RunAttempt{}]}}`.
  """
  def create_run_with_ledger!(opts \\ []) do
    slice_specs = Keyword.fetch!(opts, :slices)
    terminal = Keyword.get(opts, :terminal, :finished)
    run_id = Keyword.get(opts, :run_id, Ecto.UUID.generate())

    project =
      Ash.create!(
        Project,
        %{
          name: Keyword.get(opts, :project_name, "Run read-model fixture #{run_id}"),
          # `projects_local_path_index` is unique, so a test that builds two runs needs a
          # distinct path per run.
          local_path: Keyword.get(opts, :local_path, "/tmp/run-read-model-fixture-#{run_id}"),
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Run read-model fixture plan",
          intent: "Exercise the run read-model.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan-#{run_id}")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Run read-model fixture epic", description: "Slices."},
        domain: Factory
      )

    built =
      slice_specs
      |> Enum.with_index(1)
      |> Enum.map(fn {spec, sequence} ->
        build_run_slice!(epic.id, run_id, spec, sequence)
      end)

    slices = Enum.map(built, & &1.slice)
    # Production keys the ledger run story by the slice's STABLE KEY (the
    # `run.started`/`run.slice_outcome` payloads carry "SLICE-005", not the UUID),
    # while DB rows key by UUID. The fixture mirrors that so the read model's
    # stable-key -> UUID join is actually exercised.
    order = Enum.map(slices, & &1.stable_key)

    Ledger.write!(%{
      project_id: project.id,
      idempotency_key: "run:#{run_id}:started",
      type: "run.started",
      payload: %{"run_id" => run_id, "slice_ids" => order}
    })

    for %{slice: slice, spec: spec, sequence: sequence} <- built, Map.has_key?(spec, :status) do
      Ledger.write!(%{
        project_id: project.id,
        idempotency_key: "run:#{run_id}:slice:#{slice.stable_key}:#{sequence}",
        type: "run.slice_outcome",
        payload: %{
          "run_id" => run_id,
          "slice_id" => slice.stable_key,
          "sequence" => sequence,
          "status" => Map.fetch!(spec, :status),
          "run_attempt_outcome" => Map.get(spec, :run_attempt_outcome),
          "gate_result" => Map.get(spec, :gate_result),
          "findings" => Map.get(spec, :findings, [])
        }
      })
    end

    emit_run_terminal!(project.id, run_id, terminal)

    %{
      run_id: run_id,
      project: project,
      plan: plan,
      epic: epic,
      slices: slices,
      run_attempts: Map.new(built, &{&1.slice.id, &1.run_attempts})
    }
  end

  defp build_run_slice!(epic_id, run_id, spec, sequence) do
    stable_key = Map.get(spec, :stable_key, default_stable_key(run_id, sequence))

    slice =
      Ash.create!(
        Slice,
        %{
          epic_id: epic_id,
          title: "Slice #{sequence}",
          stable_key: stable_key,
          position: sequence
        },
        domain: Factory
      )

    attempt_count = Map.get(spec, :attempts, 1)

    run_attempts =
      for attempt_no <- 1..attempt_count do
        run_spec =
          Ash.create!(
            RunSpec,
            run_spec_attrs(slice.id, base_commit: "abc#{run_id}", attempt_no: attempt_no),
            domain: Factory
          )

        latest? = attempt_no == attempt_count

        # `run_attempts_one_active_per_slice_index` allows only ONE *active*
        # (planned/running/evidence_recorded/reviewed/gated) attempt per slice, so earlier
        # rework attempts must rest in a non-active terminal state (:needs_rework). Only the
        # latest attempt — the one the read-model surfaces — stays active (:planned).
        status = if latest?, do: :planned, else: :needs_rework
        outcome = if latest?, do: Map.get(spec, :outcome, :none), else: :needs_rework

        Ash.create!(
          RunAttempt,
          %{
            slice_id: slice.id,
            run_spec_id: run_spec.id,
            attempt_no: attempt_no,
            base_commit: run_spec.base_commit,
            status: status,
            outcome: outcome,
            orchestrator_version: "conveyor@0.1.0",
            trace_id: "trace-#{run_id}-#{sequence}-#{attempt_no}"
          },
          domain: Factory
        )
      end

    latest = List.last(run_attempts)

    maybe_build_gate_result!(latest, Map.get(spec, :gate))
    maybe_build_session!(latest, Map.get(spec, :session))

    %{slice: slice, spec: spec, sequence: sequence, run_attempts: run_attempts}
  end

  # Stable keys are unique per fixture run by default so a test that builds two
  # runs doesn't make a key ambiguous (the read model refuses to DB-enrich an
  # ambiguous key). A test exercising the ambiguity guard passes an explicit
  # colliding `:stable_key`.
  defp default_stable_key(run_id, sequence) do
    "SLICE-" <>
      String.pad_leading(to_string(sequence), 3, "0") <> "-" <> binary_part(run_id, 0, 8)
  end

  defp maybe_build_gate_result!(_run_attempt, nil), do: :ok

  defp maybe_build_gate_result!(run_attempt, gate) do
    Ash.create!(
      GateResult,
      %{
        run_attempt_id: run_attempt.id,
        passed: Map.get(gate, :passed, false),
        stages: Map.get(gate, :stages, []),
        trust_score: Map.get(gate, :trust_score),
        gate_version: "gate@1",
        gate_code_sha256: digest("gate-code"),
        policy_sha256: digest("policy"),
        contract_lock_sha256: digest("contract-lock"),
        canary_suite_version: "canary@1"
      },
      domain: Factory
    )
  end

  defp maybe_build_session!(_run_attempt, nil), do: :ok

  defp maybe_build_session!(run_attempt, session) do
    Ash.create!(
      AgentSession,
      %{
        run_attempt_id: run_attempt.id,
        run_prompt_id: Ecto.UUID.generate(),
        agent_profile_id: Ecto.UUID.generate(),
        role: :implementer,
        base_commit: run_attempt.base_commit,
        status: :succeeded,
        tokens: Map.get(session, :tokens),
        cost_estimate: Map.get(session, :cost_estimate)
      },
      domain: Factory
    )
  end

  defp emit_run_terminal!(_project_id, _run_id, :none), do: :ok

  defp emit_run_terminal!(project_id, run_id, terminal) do
    {type, suffix} =
      case terminal do
        :reaped -> {"run.reaped", "reaped"}
        :finished -> {"run.finished", "finished"}
      end

    Ledger.write!(%{
      project_id: project_id,
      idempotency_key: "run:#{run_id}:#{suffix}",
      type: type,
      payload: %{"run_id" => run_id}
    })
  end

  def temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-#{label}-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    # System.unique_integer resets per VM, so without the timestamp + an explicit wipe a
    # fresh run can land on a leftover temp dir from a prior run (a populated git repo),
    # which surfaces as flaky "nothing to commit" / stale-stat git failures.
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp run_spec_attrs(slice_id, opts) do
    attempt_no = Keyword.get(opts, :attempt_no, 1)
    # `unique_run_spec_sha256` is a unique identity, so multi-slice / multi-attempt fixtures
    # must vary the digest per (slice, attempt) rather than reuse a single constant.
    run_spec_sha256 = digest("run-spec-replay:#{slice_id}:#{attempt_no}")
    base_commit = Keyword.get(opts, :base_commit, "abc123")

    %{
      slice_id: slice_id,
      attempt_no: attempt_no,
      run_spec_json_ref: "artifacts/run-specs/attempt-#{attempt_no}.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: base_commit,
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
            "key" => "artifact",
            "input" => %{"run_spec_sha256" => run_spec_sha256},
            "output" => %{"run_spec_sha256" => run_spec_sha256}
          }
        ]
      },
      station_plan_sha256: digest("station-plan"),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp digest(label), do: "sha256:" <> digest_bytes(label)
  defp digest_bytes(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
