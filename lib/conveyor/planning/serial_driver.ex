defmodule Conveyor.Planning.SerialDriver do
  @moduledoc """
  Width-1 driver for executing a frozen pilot selection serially.
  """

  alias Conveyor.AttemptLoop
  alias Conveyor.CanonicalJson
  alias Conveyor.ContractEvolution
  alias Conveyor.Factory

  alias Conveyor.Factory.{
    AgentBrief,
    Artifact,
    ContractLock,
    DiffPolicy,
    Epic,
    Evidence,
    PatchSet,
    Plan,
    Project,
    RunAttempt,
    Slice,
    TestPack
  }

  alias Conveyor.Ledger
  alias Conveyor.Gate
  alias Conveyor.Gate.Finalizer
  alias Conveyor.Gate.TrustEvidence
  alias Conveyor.Jobs.RunGate
  alias Conveyor.Planning.PilotExecution
  alias Conveyor.Planning.RunReconciliation
  alias Conveyor.Planning.RunReconstruction
  alias Conveyor.Planning.RunSpecAssembler
  alias Conveyor.RunSlice

  # M4-E: the static gate stages wired live on the production path, each gated on the green
  # reference. workspace_integrity, policy_compliance and acceptance_mapping are required —
  # all pass for the reference and all enforce in production:
  #   - workspace_integrity: base_commit match + clean apply + no locked-path touch + a
  #     recorded head-tree digest. base_commit is clean by construction (PatchSet.base_commit
  #     = run_attempt.base_commit) and the head-tree digest is produced here (the dormant
  #     PatchSetApplicator producer is never called in the live loop), so a real
  #     base/workspace tampering blocks.
  #   - policy_compliance: a forbidden policy-controlled-path edit blocks.
  #   - acceptance_mapping: a slice whose criterion lacks passing evidence for a required
  #     test blocks; reads agent_brief + verification_result, already in the context.
  # Other static stages (code_quality_delta, observed_risk, …) stay unwired until their
  # producers exist (analyzer results, review policy, …).
  @default_gate_stages [
    Conveyor.Gate.Stages.WorkspaceIntegrity,
    Conveyor.Gate.Stages.ContractLock,
    Conveyor.Gate.Stages.DiffScope,
    Conveyor.Gate.Stages.SecretSafety,
    Conveyor.Gate.Stages.PolicyCompliance,
    Conveyor.Gate.Stages.TestExecution,
    Conveyor.Gate.Stages.AcceptanceMapping
  ]

  # M6 stuck-slice/stuck-run reaper. Per-agent-call wall-clock is already bounded in the
  # adapter (Codex `run_with_timeout`, 15 min). What was missing is a clock-based bound on
  # the WHOLE slice (a slice that loops across rework attempts, or a non-agent station that
  # hangs) and on the WHOLE unattended run. These defaults are generous so they only catch
  # a genuinely stuck slice/run, never a slow-but-progressing one. Resolution precedence:
  # per-call opts > `:conveyor` app config > these code defaults. Disable with an explicit
  # `nil`/`false` (config/test.exs nils both so existing tests run inline — no Task boundary).
  @default_slice_wall_clock_ms 3_600_000
  @default_run_wall_clock_ms 28_800_000

  defmodule Result do
    @moduledoc """
    Serial driver execution result.

    `:passed` — every selected slice passed. `:partial` — the run carried on over
    the dependency subgraph past ≥1 parked/skipped slice (M3 skip-and-continue):
    independents completed, a parked slice's dependents were skipped.
    """

    @type t :: %__MODULE__{
            status: :passed | :partial,
            order: [String.t()],
            events: [map()],
            report: map()
          }

    @enforce_keys [:status, :order, :events, :report]
    defstruct [:status, :order, :events, :report]
  end

  @spec run!(map(), keyword()) :: Result.t()
  def run!(input, opts \\ []) when is_map(input) do
    work_graph = value(input, :work_graph) || input
    # Dedup so a duplicated slice id can't run (and accept-commit) twice — do_topo
    # keeps duplicates and a slice has no self-edge to block its own re-run.
    selected_slice_ids = input |> list(:selected_slice_ids) |> Enum.uniq()
    edges = work_edges(work_graph, selected_slice_ids)
    order = do_topo(selected_slice_ids, edges, [])

    # M3 skip-and-continue: a parked/failed slice no longer HALTS the run. We carry
    # on over the dep subgraph — independent slices still run; a parked slice's
    # transitive dependents are SKIPPED. A one-hop predecessor check suffices: topo
    # order visits every execution_hard dependency before its dependents, so a slice
    # blocked transitively always has a direct predecessor already in `blocked`.
    #
    # `agent_ran?` gates the per-slice workspace reset: we only reset once a prior
    # slice's agent has actually run (and may have left an uncommitted parked tree).
    # The FIRST agent run is never preceded by a reset, so a user's pre-run working
    # tree is never destroyed — the reset is the loop's own between-slice cleanup.
    reaper = build_reaper(opts)

    # M6 durability: a run-scoped event stream committed to the append-only ledger so a
    # crashed run can be detected and resumed. `ledger` is nil in map-fake unit tests where
    # no project resolves — then the loop behaves exactly as before (in-memory events only).
    ledger = run_ledger_context(input, opts)
    emit_run_started!(ledger, order, work_graph)

    events = execute_order(order, edges, work_graph, opts, reaper, ledger, %{}, false)

    emit_run_terminal!(ledger, events)
    build_result(order, events)
  end

  @doc """
  Resume an interrupted run (U4). Re-enters the loop from the committed ledger stream:
  a slice with a committed outcome is reused verbatim (never re-executed — passed slices
  are the durable boundary, U3); the first slice with no committed outcome is the in-flight
  slice, re-run from a clean base. `input` is the same work-graph map `run!/2` takes; the
  prior `run_id` is reused so re-emitted slice outcomes dedup. `opts[:outcomes]` injects the
  folded stream (tests); otherwise it is reconstructed from the ledger.
  """
  @spec resume!(String.t(), map(), keyword()) :: Result.t()
  def resume!(run_id, input, opts \\ []) when is_binary(run_id) and is_map(input) do
    opts = Keyword.put(opts, :run_id, run_id)
    work_graph = value(input, :work_graph) || input
    selected_slice_ids = input |> list(:selected_slice_ids) |> Enum.uniq()
    edges = work_edges(work_graph, selected_slice_ids)
    order = do_topo(selected_slice_ids, edges, [])
    reaper = build_reaper(opts)
    ledger = run_ledger_context(input, opts)

    state = RunReconstruction.reconstruct(run_id, order, Keyword.take(opts, [:outcomes]))

    # U5: before re-running the in-flight slice, reconcile whether its accept-commit already
    # landed in the workspace (the crash gap between git commit and the outcome ledger write).
    # If so, record it passed and reuse it — never produce a second accept-commit.
    resumed = reconcile_in_flight(state, ledger, opts)

    # Resume seeds agent_ran? = true: a prior slice ran in the now-dead process, so the
    # first re-executed slice resets to the committed base, discarding the crash's leftover tree.
    events = execute_order(order, edges, work_graph, opts, reaper, ledger, resumed, true)

    emit_run_terminal!(ledger, events)
    build_result(order, events)
  end

  # Shared reduce for run!/resume!. `resumed` maps slice_key => committed outcome payload;
  # those slices are reused verbatim (not re-executed, not re-committed — dedup would no-op
  # them anyway). `initial_agent_ran` seeds the between-slice reset gate (false for a fresh
  # run so a user's pre-run tree is never reset; true for a resume).
  defp execute_order(order, edges, work_graph, opts, reaper, ledger, resumed, initial_agent_ran) do
    order
    |> Enum.with_index(1)
    |> Enum.reduce({[], MapSet.new(), initial_agent_ran}, fn {slice_key, sequence},
                                                             {events, blocked, agent_ran?} ->
      {event, ran_now?} =
        cond do
          Map.has_key?(resumed, slice_key) ->
            {Map.fetch!(resumed, slice_key), false}

          true ->
            case blocking_predecessors(slice_key, edges, blocked) do
              [] -> run_one_guarded!(slice_key, work_graph, sequence, agent_ran?, opts, reaper)
              blockers -> {skipped_event(slice_key, sequence, blockers), false}
            end
        end

      unless Map.has_key?(resumed, slice_key), do: commit_slice_outcome!(ledger, event)

      next_blocked =
        if event["status"] == "passed", do: blocked, else: MapSet.put(blocked, slice_key)

      {events ++ [event], next_blocked, agent_ran? or ran_now?}
    end)
    |> elem(0)
  end

  defp build_result(order, events) do
    report =
      PilotExecution.summarize(%{
        implementation_width: 1,
        selected_slice_ids: order,
        events: events
      })
      |> Map.merge(replay_report(order, events))

    %Result{status: run_status(events), order: order, events: events, report: report}
  end

  # All-passed => :passed; any park/skip => :partial (the run advanced but did not
  # complete every slice). The run never bails early — the whole order is processed.
  defp run_status(events) do
    if Enum.all?(events, &(&1["status"] == "passed")), do: :passed, else: :partial
  end

  # Direct execution_hard predecessors of `slice_key` that are already blocked
  # (parked or skipped). Non-empty => this slice is skipped.
  defp blocking_predecessors(slice_key, edges, blocked) do
    edges
    |> Enum.filter(fn edge ->
      value(edge, :to) == slice_key and MapSet.member?(blocked, value(edge, :from))
    end)
    |> Enum.map(&value(&1, :from))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp skipped_event(slice_key, sequence, blockers) do
    %{
      "slice_id" => slice_key,
      "sequence" => sequence,
      "status" => "skipped",
      "gate_result" => "skipped_upstream_parked",
      "run_attempt_outcome" => :skipped,
      "findings" => [],
      "blocked_by" => blockers
    }
  end

  defp replay_report(order, events) do
    digest =
      CanonicalJson.digest(%{
        "schema_version" => "conveyor.serial_replay@1",
        "serial_order" => order,
        "events" => Enum.map(events, &normalize_replay_event/1)
      })

    %{
      "replay_digest" => digest,
      # No replay-divergence producer exists yet, so no comparison is performed.
      # Emit the honest "baseline_absent" (the gate's own vocabulary for "no
      # baseline to compare against") rather than an unearned "matched". The full
      # cross-run producer is deferred — see
      # docs/plans/2026-06-23-002-feat-replay-divergence-producer-plan.md.
      "replay_fidelity" => %{
        "schema_version" => "conveyor.replay_fidelity@1",
        "status" => "baseline_absent",
        "digest" => digest,
        "event_count" => length(events)
      }
    }
  end

  defp normalize_replay_event(event) do
    %{
      "slice_id" => value(event, :slice_id),
      "sequence" => value(event, :sequence),
      "status" => value(event, :status),
      "gate_result" => value(event, :gate_result),
      "run_attempt_outcome" => value(event, :run_attempt_outcome),
      "findings" => event |> list(:findings) |> Enum.map(&to_string/1)
    }
  end

  # --- M6 wall-clock reaper ----------------------------------------------------

  # Resolve the slice/run wall-clock budgets once per run. A monotonic run-start anchors
  # the run deadline; both budgets are `nil` when disabled (then `run_one_guarded!` runs the
  # slice inline with no Task boundary, exactly as before this milestone).
  defp build_reaper(opts) do
    run_started_ms = System.monotonic_time(:millisecond)

    slice_budget_ms =
      resolve_budget(
        opts,
        :slice_wall_clock_ms,
        :serial_driver_slice_wall_clock_ms,
        @default_slice_wall_clock_ms
      )

    run_budget_ms =
      resolve_budget(
        opts,
        :run_wall_clock_ms,
        :serial_driver_run_wall_clock_ms,
        @default_run_wall_clock_ms
      )

    %{
      slice_budget_ms: slice_budget_ms,
      run_budget_ms: run_budget_ms,
      run_started_ms: run_started_ms,
      run_deadline_ms: run_budget_ms && run_started_ms + run_budget_ms
    }
  end

  defp resolve_budget(opts, opt_key, config_key, code_default) do
    case Keyword.fetch(opts, opt_key) do
      {:ok, value} -> normalize_budget(value)
      :error -> normalize_budget(Application.get_env(:conveyor, config_key, code_default))
    end
  end

  defp normalize_budget(ms) when is_integer(ms) and ms > 0, do: ms
  defp normalize_budget(_), do: nil

  # Guarded slice execution. Three cases:
  #   1. the run budget is already spent  -> reap before starting (nothing runs)
  #   2. no budget applies                -> run inline (no Task, behaviour unchanged)
  #   3. a budget applies                 -> run in a Task, reaped at the effective deadline
  # A reaped slice parks (status != "passed"), so the existing skip-and-continue logic
  # blocks its dependents and the run advances instead of hanging.
  defp run_one_guarded!(slice_key, work_graph, sequence, reset?, opts, reaper) do
    now = System.monotonic_time(:millisecond)

    if reaper.run_deadline_ms != nil and now >= reaper.run_deadline_ms do
      {reaped_event(
         slice_key,
         sequence,
         "run_deadline",
         now - reaper.run_started_ms,
         reaper.run_budget_ms
       ), false}
    else
      case effective_timeout(reaper, now) do
        :none ->
          run_one!(slice_key, work_graph, sequence, reset?, opts)

        {reason, timeout_ms} ->
          reap_slice!(slice_key, work_graph, sequence, reset?, opts, reason, timeout_ms)
      end
    end
  end

  # The binding deadline for this slice is whichever is nearer: its own per-slice budget or
  # the time left on the whole-run budget. `:none` means neither is configured.
  defp effective_timeout(reaper, now) do
    remaining_run = reaper.run_deadline_ms && reaper.run_deadline_ms - now
    slice = reaper.slice_budget_ms

    cond do
      is_nil(slice) and is_nil(remaining_run) -> :none
      is_nil(remaining_run) -> {"slice_deadline", slice}
      is_nil(slice) -> {"run_deadline", remaining_run}
      slice <= remaining_run -> {"slice_deadline", slice}
      true -> {"run_deadline", remaining_run}
    end
  end

  # Run the slice in a linked Task and bound it by wall-clock. `Task.yield ||
  # Task.shutdown(:brutal_kill)` mirrors the adapter-level watchdog (Codex.run_with_timeout):
  # on timeout the in-flight slice is killed and reported as reaped. A slice that *raises* is
  # re-raised in the caller so the existing crash semantics are preserved exactly — only the
  # timeout path is new.
  defp reap_slice!(slice_key, work_graph, sequence, reset?, opts, reason, timeout_ms) do
    started_at = System.monotonic_time(:millisecond)

    task =
      Task.async(fn ->
        try do
          {:ok, run_one!(slice_key, work_graph, sequence, reset?, opts)}
        rescue
          error -> {:raise, error, __STACKTRACE__}
        end
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, {event, ran?}}} ->
        {event, ran?}

      {:ok, {:raise, error, stacktrace}} ->
        reraise(error, stacktrace)

      _timed_out_or_killed ->
        elapsed = System.monotonic_time(:millisecond) - started_at
        # A brutal-killed slice may have left an uncommitted tree, so the next independent
        # slice must reset to base — report `agent_ran? = true`.
        {reaped_event(slice_key, sequence, reason, elapsed, timeout_ms), true}
    end
  end

  defp reaped_event(slice_key, sequence, reason, elapsed_ms, budget_ms) do
    %{
      "slice_id" => slice_key,
      "sequence" => sequence,
      "status" => "parked",
      "gate_result" => "reaped_wall_clock",
      "run_attempt_outcome" => :parked,
      "findings" => ["wall_clock_exceeded", reason],
      "reaped" => %{
        "reason" => reason,
        "elapsed_ms" => elapsed_ms,
        "budget_ms" => budget_ms
      }
    }
  end

  # Returns {event, agent_ran?}. `agent_ran?` is true only when the slice's agent
  # actually executed (so it may have left an uncommitted tree); an interrogation
  # preflight park returns false (it touches nothing). `reset?` says whether a PRIOR
  # slice's agent already ran — only then do we reset this slice's workspace to base.
  defp run_one!(slice_key, work_graph, sequence, reset?, opts) do
    single_slice_graph = single_slice_graph!(work_graph, slice_key)

    case interrogate_slice(slice_key, single_slice_graph, sequence, opts) do
      {:park, event} ->
        {event, false}

      :continue ->
        # Option C: stage + commit this slice's locked acceptance tests into the
        # workspace BEFORE assembly, so base_commit (git HEAD at assemble time)
        # already contains them — the agent then diffs cleanly against a base that
        # holds the locked tests, and the calibration worktree sees them red at base.
        materialize_locked_tests!(slice_key, opts)
        run_spec = assemble_run_spec!(slice_key, single_slice_graph, opts)
        # M3 isolation: start this slice from the last ACCEPTED commit, discarding
        # any uncommitted leftovers from a prior parked slice so an independent slice
        # never builds on a half-applied/parked tree (no-op when the tree is clean;
        # skipped on the first agent run to protect the user's pre-run tree).
        if reset?, do: reset_workspace_to_base!(run_spec, opts)
        run_attempt = create_run_attempt!(run_spec, opts)

        event =
          if rework_enabled?(opts) do
            run_one_with_rework!(slice_key, sequence, run_spec, run_attempt, opts)
          else
            run_one_single_attempt!(slice_key, sequence, run_spec, run_attempt, opts)
          end

        {event, true}
    end
  end

  # Default (keystone) path — a single attempt, then park on non-accept. Behaviour
  # is UNCHANGED from before M2(b); rework is strictly opt-in (see rework_enabled?/1).
  defp run_one_single_attempt!(slice_key, sequence, run_spec, run_attempt, opts) do
    slice_result = run_slice!(run_attempt, opts)
    gate = run_gate!(run_spec, run_attempt, slice_result, opts)
    finalization = finalize_gate!(gate, run_spec, run_attempt, slice_result, opts)

    passed? =
      slice_result.status == :succeeded and gate_passed?(gate) and accepted?(finalization)

    head =
      if passed? do
        advance_workspace_base!(run_spec, slice_key, finalization, opts)
      end

    %{
      "slice_id" => slice_key,
      "sequence" => sequence,
      "status" => if(passed?, do: "passed", else: "parked"),
      "gate_result" => if(passed?, do: "first_pass", else: "eventual_pending"),
      "run_attempt_outcome" => final_outcome(finalization),
      "findings" => finding_categories(gate)
    }
    |> put_head_provenance(head)
  end

  # M2(b): opt-in rework-on-fail via `AttemptLoop` — a non-accepted slice reworks
  # within a bounded budget instead of parking + halting the plan. We INJECT this
  # driver's `run_slice!`/`run_gate!` (so the rich gate context + 4 wired stages are
  # preserved; AttemptLoop's own defaults are thinner) and let AttemptLoop use its
  # default finalize (== `default_finalize_gate!`) + the real ReworkSynthesizer/
  # RunSpecForge retry path. Enable with `rework: true` (+ optional `max_attempts`).
  defp run_one_with_rework!(slice_key, sequence, run_spec, run_attempt, opts) do
    loop_opts =
      opts
      |> Keyword.put(:run_slice, fn attempt -> run_slice!(attempt, opts) end)
      |> Keyword.put(:run_gate, fn rs, attempt, sr -> run_gate!(rs, attempt, sr, opts) end)
      |> Keyword.put_new(:actor, "serial-driver")
      |> Keyword.put_new(:max_attempts, 3)

    loop_result = AttemptLoop.run_to_done!(run_attempt, loop_opts)
    passed? = loop_result.status == :accepted
    last_attempt = List.last(loop_result.attempts)

    head =
      if passed? do
        advance_workspace_base!(run_spec, slice_key, loop_result, opts)
      end

    event =
      %{
        "slice_id" => slice_key,
        "sequence" => sequence,
        "status" => if(passed?, do: "passed", else: "parked"),
        "gate_result" => rework_gate_label(passed?, loop_result),
        "run_attempt_outcome" => last_attempt && last_attempt.outcome,
        "findings" => loop_findings(loop_result),
        "attempt_count" => loop_result.report["attempt_count"]
      }
      |> put_head_provenance(head)

    # ADR-26: a rework-exhausted slice whose contract is structurally broken parks
    # with the human-review amendment proposal attached, not as a blind failure.
    case loop_result.report["amendment_proposal"] do
      proposal when is_map(proposal) -> Map.put(event, "amendment_proposal", proposal)
      _ -> event
    end
  end

  # Rework is ON by default (the loop survives a non-first-pass slice); pass
  # `rework: false` to force the legacy single-attempt-then-park path.
  defp rework_enabled?(opts), do: Keyword.get(opts, :rework, true) == true

  defp rework_gate_label(false, %{status: :amendment_proposed}), do: "contract_amendment_proposed"
  defp rework_gate_label(false, _loop_result), do: "eventual_pending"

  defp rework_gate_label(true, loop_result) do
    if loop_result.report["rework_recovered"], do: "eventual_pass", else: "first_pass"
  end

  defp loop_findings(loop_result) do
    loop_result.events |> List.last(%{}) |> Map.get("finding_categories", [])
  end

  defp interrogate_slice(slice_key, single_slice_graph, sequence, opts) do
    case Keyword.get(opts, :interrogation_preflight) do
      fun when is_function(fun, 2) ->
        fun.(slice_key, single_slice_graph)
        |> interrogation_event(slice_key, sequence)

      _missing ->
        :continue
    end
  end

  defp interrogation_event(batch, slice_key, sequence) do
    if value(batch, :status) in [:questions_required, "questions_required"] do
      {:park,
       %{
         "slice_id" => slice_key,
         "sequence" => sequence,
         "status" => "parked",
         "gate_result" => "eventual_pending",
         "run_attempt_outcome" => :parked,
         "findings" => ["clarification", "interrogator_fired"],
         "interrogation" => %{
           "status" => "questions_required",
           "question_count" => length(list(batch, :questions))
         }
       }}
    else
      :continue
    end
  end

  defp assemble_run_spec!(slice_key, single_slice_graph, opts) do
    case Keyword.get(opts, :assemble_run_spec) do
      fun when is_function(fun, 2) ->
        fun.(slice_key, single_slice_graph)

      nil ->
        slice = slice_for!(slice_key, opts)

        assembler_opts =
          opts
          |> Keyword.get(:run_spec_opts, [])
          |> Keyword.merge(work_graph: single_slice_graph)
          |> maybe_put(:patch_ref, patch_ref_for(slice_key, opts))
          |> maybe_put(:patch_refs_by_attempt, patch_refs_by_attempt_for(slice_key, opts))

        RunSpecAssembler.assemble!(slice, assembler_opts)
    end
  end

  defp create_run_attempt!(run_spec, opts) do
    case Keyword.get(opts, :create_run_attempt) do
      fun when is_function(fun, 1) ->
        fun.(run_spec)

      nil ->
        Ash.create!(
          RunAttempt,
          %{
            slice_id: run_spec.slice_id,
            run_spec_id: run_spec.id,
            attempt_no: run_spec.attempt_no,
            base_commit: run_spec.base_commit,
            status: :planned,
            outcome: :none,
            orchestrator_version: Keyword.get(opts, :orchestrator_version, "conveyor@0.1.0"),
            trace_id: Keyword.get(opts, :trace_id, "serial-driver-#{run_spec.id}")
          },
          domain: Factory
        )
    end
  end

  defp run_slice!(run_attempt, opts) do
    case Keyword.get(opts, :run_slice) do
      fun when is_function(fun, 1) -> fun.(run_attempt)
      nil -> RunSlice.run!(run_attempt, run_slice_opts(opts))
    end
  end

  defp run_slice_opts(opts) do
    opts
    |> Keyword.take([:actor, :blob_root])
    |> maybe_put(:blob_root, Keyword.get(Keyword.get(opts, :run_spec_opts, []), :blob_root))
  end

  defp run_gate!(run_spec, run_attempt, slice_result, opts) do
    case Keyword.get(opts, :run_gate) do
      fun when is_function(fun, 3) ->
        fun.(run_spec, run_attempt, slice_result)

      nil ->
        context =
          %{
            run_attempt_id: run_attempt.id,
            run_attempt: run_attempt,
            run_spec: run_spec,
            verification_result: slice_result.output["verification_result"]
          }
          |> Map.merge(default_gate_context(run_spec, run_attempt, slice_result))
          |> Map.merge(extra_gate_context(run_spec, run_attempt, slice_result, opts))

        RunGate.run_gate_only!(
          context,
          Keyword.get(opts, :gate_stages, @default_gate_stages),
          gate_code_sha256: Keyword.get(opts, :gate_code_sha256, digest("gate")),
          policy_sha256: run_spec.policy_sha256,
          contract_lock_sha256: run_spec.contract_lock_sha256
        )
    end
  end

  defp default_gate_context(run_spec, run_attempt, slice_result) do
    patch_set = patch_set_for(slice_result)
    evidence = evidence_for(slice_result)
    contract = contract_for(run_spec)

    %{
      agent_brief: contract.agent_brief,
      artifacts: artifacts_for(run_attempt.id),
      contract_lock: contract.contract_lock,
      diff_policy: diff_policy_for(run_attempt.slice_id),
      evidence: evidence,
      head_tree_sha256: gate_head_tree_sha256(run_spec),
      patch_set: patch_set,
      security_findings: value(slice_result.output, :security_findings, []),
      test_pack: contract.test_pack
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  # M4-E producer for workspace_integrity: a non-mutating head-tree digest of the live
  # workspace at gate time. The dormant PatchSetApplicator producer (which would persist
  # run_attempt.head_tree_sha256) is never called in the production loop, so the digest is
  # computed here from the implement-station workspace. Staging happens in a throwaway index
  # (GIT_INDEX_FILE) so the real index stays clean for the later commit_workspace_changes! /
  # reset; `git add -A` respects .gitignore, so volatile ignored paths (venv, pytest caches)
  # are excluded and the digest is deterministic across a run and its replay (git trees are
  # content-addressed, so an identical post-patch tree yields an identical digest).
  defp gate_head_tree_sha256(run_spec) do
    case workspace_path(run_spec) do
      nil -> nil
      workspace_path -> head_tree_digest(workspace_path)
    end
  end

  defp head_tree_digest(workspace_path) do
    tmp_index =
      Path.join(System.tmp_dir!(), "conveyor-gate-index-#{System.unique_integer([:positive])}")

    env = [{"GIT_INDEX_FILE", tmp_index}]

    try do
      with {_add, 0} <- git_cmd(workspace_path, ["add", "-A"], env),
           {tree, 0} <- git_cmd(workspace_path, ["write-tree"], env) do
        digest(String.trim(tree))
      else
        _ -> nil
      end
    after
      File.rm(tmp_index)
    end
  end

  defp git_cmd(workspace_path, args, env) do
    System.cmd("git", ["-C", workspace_path | args], env: env, stderr_to_stdout: true)
  end

  defp extra_gate_context(run_spec, run_attempt, slice_result, opts) do
    case Keyword.get(opts, :gate_context) do
      fun when is_function(fun, 3) -> fun.(run_spec, run_attempt, slice_result)
      context when is_map(context) -> context
      _missing -> %{}
    end
  end

  defp patch_set_for(slice_result) do
    PatchSet
    |> find_by_id(value(slice_result.output, :patch_set_id))
  end

  defp evidence_for(slice_result) do
    Evidence
    |> find_by_id(value(slice_result.output, :evidence_id))
  end

  defp contract_for(run_spec) do
    contract_lock =
      ContractLock
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(ContractEvolution.contract_lock_sha256(&1) == run_spec.contract_lock_sha256))

    agent_brief = find_by_id(AgentBrief, contract_lock && contract_lock.agent_brief_id)

    test_pack =
      TestPack
      |> Ash.read!(domain: Factory)
      |> Enum.find(
        &(&1.slice_id == run_spec.slice_id and &1.test_pack_sha256 == run_spec.test_pack_sha256)
      )

    %{agent_brief: agent_brief, contract_lock: contract_lock, test_pack: test_pack}
  end

  defp diff_policy_for(slice_id) do
    slice = get_by_id!(Slice, slice_id)

    find_by_id(DiffPolicy, slice.diff_policy_id) ||
      DiffPolicy
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.slice_id == slice_id))
  end

  defp artifacts_for(run_attempt_id) do
    Artifact
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt_id))
  end

  defp find_by_id(_resource, nil), do: nil

  defp find_by_id(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end

  defp get_by_id!(resource, id) do
    find_by_id(resource, id) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp finalize_gate!(gate, run_spec, run_attempt, slice_result, opts) do
    case Keyword.get(opts, :finalize_gate) do
      fun when is_function(fun, 3) ->
        fun.(gate, run_spec, run_attempt)

      nil ->
        default_finalize_gate!(gate, run_spec, run_attempt, slice_result, opts)
    end
  end

  defp default_finalize_gate!(
         %Gate.Result{} = gate,
         run_spec,
         %RunAttempt{} = run_attempt,
         slice_result,
         opts
       ) do
    Finalizer.finalize!(
      gate,
      %{
        run_attempt: run_attempt,
        run_spec: run_spec,
        trust_evidence: trust_evidence(slice_result)
      },
      actor: Keyword.get(opts, :actor, "serial-driver")
    )
  end

  defp default_finalize_gate!(_gate, _run_spec, run_attempt, _slice_result, _opts) do
    %{run_attempt: run_attempt}
  end

  # ADR-23: thread the slice run's calibration/baseline signals into the gate
  # finalizer so a passed-but-unconfident run abstains. nil => no evidence =>
  # legacy auto-accept.
  defp trust_evidence(%{output: output}) when is_map(output),
    do: TrustEvidence.from_run_output(output)

  defp trust_evidence(_slice_result), do: nil

  # M3 isolation: reset the shared workspace tree to the last accepted commit (HEAD)
  # before a slice runs, discarding any uncommitted changes a prior PARKED slice left
  # behind. Injectable (`:reset_workspace_base`) and a no-op when there is no
  # workspace (map-fake unit tests) or the tree is already clean (accepted slices
  # committed, so HEAD already holds their work).
  # Option C seam: injectable like reset/advance. Default resolves the slice's locked
  # test refs from its TestPack and delegates to Conveyor.LockedTests, which no-ops
  # unless the workspace actually carries a `.conveyor/locked-tests` directory (so
  # runs without materialized tests — every existing flow — are unaffected).
  defp materialize_locked_tests!(slice_key, opts) do
    case Keyword.get(opts, :materialize_locked_tests) do
      fun when is_function(fun, 1) ->
        fun.(slice_key)
        :ok

      false ->
        :ok

      nil ->
        default_materialize_locked_tests!(slice_key, opts)
    end
  end

  defp default_materialize_locked_tests!(slice_key, opts) do
    workspace_path = opts |> Keyword.get(:run_spec_opts, []) |> Keyword.get(:workspace_path)

    # Gate on the locked-tests dir FIRST so runs without materialized tests never
    # touch the DB or require :slices_by_stable_key (keeps every existing flow inert).
    if is_binary(workspace_path) and
         File.dir?(Path.join(workspace_path, ".conveyor/locked-tests")) do
      slice = slice_for!(slice_key, opts)
      Conveyor.LockedTests.materialize!(workspace_path, locked_test_refs(slice.id), slice_key)
    end

    :ok
  end

  defp locked_test_refs(slice_id) do
    Conveyor.Factory.TestPack
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(&{&1.version, DateTime.to_unix(&1.locked_at, :microsecond)}, :desc)
    |> List.first()
    |> case do
      nil -> []
      test_pack -> test_pack.required_test_refs || []
    end
  end

  defp reset_workspace_to_base!(run_spec, opts) do
    case Keyword.get(opts, :reset_workspace_base) do
      fun when is_function(fun, 1) ->
        fun.(run_spec)

      false ->
        :ok

      nil ->
        default_reset_workspace_to_base!(run_spec)
    end
  end

  defp default_reset_workspace_to_base!(run_spec) do
    case workspace_path(run_spec) do
      nil ->
        :ok

      workspace_path ->
        git!(workspace_path, ["reset", "--hard", "HEAD"])
        # Drop untracked, non-ignored files (e.g. a parked slice's new modules);
        # ignored paths (venv, caches) are preserved (no -x).
        git!(workspace_path, ["clean", "-fdq"])
        :ok
    end
  end

  # Returns post-commit head provenance `%{"head_commit" => sha, "head_tree" => digest}`
  # for the accepted slice (or nil when there is no workspace / an injected fake), so the
  # caller can record it on the slice-outcome event for U5 exactly-once reconciliation.
  defp advance_workspace_base!(run_spec, slice_key, finalization, opts) do
    case Keyword.get(opts, :advance_workspace_base) do
      fun when is_function(fun, 3) ->
        fun.(run_spec, slice_key, finalization)
        nil

      false ->
        nil

      nil ->
        default_advance_workspace_base!(run_spec, slice_key)
    end
  end

  defp default_advance_workspace_base!(run_spec, slice_key) do
    case workspace_path(run_spec) do
      nil ->
        nil

      workspace_path ->
        commit_workspace_changes!(workspace_path, slice_key)
        head_provenance(workspace_path)
    end
  end

  # The committed HEAD commit sha and its tree digest, read AFTER the accept-commit
  # (commit-first ordering): the recorded sha reflects a landed commit, which is what U5
  # compares the live workspace against to decide whether a slice's side effect already
  # applied. `git clean -fdq` keeps .gitignore'd paths, so HEAD^{tree} excludes them
  # deterministically — the same property the gate head-tree digest relies on.
  defp head_provenance(workspace_path) do
    %{
      "head_commit" => git!(workspace_path, ["rev-parse", "HEAD"]),
      "head_tree" => digest(git!(workspace_path, ["rev-parse", "HEAD^{tree}"]))
    }
  end

  defp workspace_path(run_spec) do
    run_spec
    |> value(:station_plan, %{})
    |> list(:stations)
    |> Enum.find(&(value(&1, :key) == "implement"))
    |> value(:input, %{})
    |> value(:workspace_path)
  end

  defp commit_workspace_changes!(workspace_path, slice_key) do
    case git!(workspace_path, ["status", "--porcelain"]) do
      "" ->
        :ok

      _dirty ->
        git!(workspace_path, ["add", "-A"])

        git!(workspace_path, [
          "-c",
          "user.email=conveyor@example.invalid",
          "-c",
          "user.name=Conveyor Serial Driver",
          "commit",
          "-m",
          "conveyor: accept #{slice_key}"
        ])

        :ok
    end
  end

  # The execution_hard edges among the selected slices — used both to order the run
  # (do_topo) and to compute skip cascades (blocking_predecessors), so skip follows
  # the SAME edge kind that defines ordering (the one-hop==transitive-closure proof
  # only holds for that kind). execution_hard means "B's code depends on A", which is
  # what justifies skipping B when A parks; integration_order is a softer "integrate
  # after" constraint that does not imply a build dependency, so it is intentionally
  # excluded here. The ordering gap for integration_order is pre-existing; both are
  # tracked for reconciliation in br 9z4r.1.
  defp work_edges(work_graph, selected_slice_ids) do
    selected = MapSet.new(selected_slice_ids)

    work_graph
    |> list(:work_dependencies)
    |> Enum.filter(&(value(&1, :kind) in ["execution_hard", :execution_hard]))
    |> Enum.filter(&(value(&1, :from) in selected and value(&1, :to) in selected))
  end

  defp do_topo([], _edges, done), do: Enum.reverse(done)

  defp do_topo(remaining, edges, done) do
    done_set = MapSet.new(done)

    case Enum.find(remaining, &ready?(&1, edges, done_set)) do
      nil ->
        raise ArgumentError, "selected slice dependency cycle: #{Enum.join(remaining, " -> ")}"

      slice_key ->
        do_topo(List.delete(remaining, slice_key), edges, [slice_key | done])
    end
  end

  defp ready?(slice_key, edges, done_set) do
    edges
    |> Enum.filter(&(value(&1, :to) == slice_key))
    |> Enum.all?(&(value(&1, :from) in done_set))
  end

  defp single_slice_graph!(work_graph, slice_key) do
    slice =
      work_graph
      |> list(:slices)
      |> Enum.find(&(value(&1, :stable_key) == slice_key or value(&1, :key) == slice_key)) ||
        raise ArgumentError, "slice #{slice_key} was not found in work_graph"

    work_graph
    |> stringify_keys()
    |> Map.put("slices", [stringify_keys(slice)])
    |> Map.put("work_dependencies", [])
  end

  defp slice_for!(slice_key, opts) do
    case Keyword.get(opts, :slices_by_stable_key, %{}) do
      %{^slice_key => slice} ->
        slice

      _missing ->
        raise ArgumentError, "SerialDriver needs :slices_by_stable_key for #{slice_key}"
    end
  end

  defp patch_ref_for(slice_key, opts) do
    cond do
      is_function(Keyword.get(opts, :patch_ref), 1) ->
        Keyword.fetch!(opts, :patch_ref).(slice_key)

      is_map(Keyword.get(opts, :patch_refs_by_slice)) ->
        Map.get(Keyword.fetch!(opts, :patch_refs_by_slice), slice_key)

      true ->
        Keyword.get(opts, :patch_ref)
    end
  end

  # Reference/test-only: the %{attempt_no(string) => patch_path} map for one slice,
  # from a `:patch_refs_by_slice_attempt` opt. Lets a deterministic run apply a
  # failing patch on attempt 1 and a passing patch on attempt 2 (the M2-exit proof).
  defp patch_refs_by_attempt_for(slice_key, opts) do
    case Keyword.get(opts, :patch_refs_by_slice_attempt) do
      map when is_map(map) -> Map.get(map, slice_key)
      _ -> nil
    end
  end

  defp gate_passed?(gate), do: Map.get(gate, :passed?) || Map.get(gate, "passed?") || false

  defp accepted?(finalization), do: final_outcome(finalization) in [:accepted, "accepted"]

  defp final_outcome(finalization) do
    finalization
    |> value(:run_attempt)
    |> value(:outcome)
  end

  defp finding_categories(gate) do
    gate
    |> Map.get(:findings, Map.get(gate, "findings", []))
    |> Enum.map(&(value(&1, :category) || value(&1, :rule_key) || inspect(&1)))
  end

  # --- M6 run ledger (durable run-scoped event stream) -------------------------

  # Resolve the durable-run context once at run start: a minted run_id plus the
  # project_id every ledger event requires. Returns nil when no project resolves —
  # map-fake unit tests with no real Slice/DB then run exactly as before (no ledger
  # writes). `run_ledger: false` also disables it; `run_id:` seeds a fixed id (resume).
  defp run_ledger_context(input, opts) do
    if Keyword.get(opts, :run_ledger, true) do
      case resolve_project_id(input, opts) do
        nil -> nil
        project_id -> %{run_id: resolve_run_id(opts), project_id: project_id}
      end
    end
  end

  defp resolve_run_id(opts), do: Keyword.get(opts, :run_id) || Ecto.UUID.generate()

  # Walk the first selected slice to its project (slice -> epic -> plan -> project),
  # mirroring SliceLifecycle.context_for!. Any miss (fake slice, absent record, no DB)
  # degrades to nil so durability is skipped rather than crashing the run.
  defp resolve_project_id(input, opts) do
    with [slice_key | _] <- input |> list(:selected_slice_ids) |> Enum.uniq(),
         slice when is_map(slice) <- slice_by_stable_key(slice_key, opts),
         epic_id when is_binary(epic_id) <- value(slice, :epic_id),
         %Epic{} = epic <- find_by_id(Epic, epic_id),
         %Plan{} = plan <- find_by_id(Plan, epic.plan_id),
         %Project{} = project <- find_by_id(Project, plan.project_id) do
      project.id
    else
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp slice_by_stable_key(slice_key, opts) do
    opts |> Keyword.get(:slices_by_stable_key, %{}) |> Map.get(slice_key)
  end

  # U5: reconcile the in-flight slice against the live workspace before re-running it.
  # `workspace_path` is supplied by the resume caller (the reconciler / a test); without
  # it there is nothing to reconcile (map-fake resume) and the slice is simply re-run.
  defp reconcile_in_flight(state, ledger, opts) do
    workspace_path = Keyword.get(opts, :workspace_path)
    in_flight = state.in_flight_slice

    if workspace_path && in_flight do
      sequence = state.start_index + 1

      case RunReconciliation.reconcile_in_flight(
             state.run_id,
             in_flight,
             sequence,
             workspace_path
           ) do
        {:already_committed, outcome} ->
          commit_slice_outcome!(ledger, outcome)
          Map.put(state.outcomes_by_slice, in_flight, outcome)

        :rerun ->
          state.outcomes_by_slice
      end
    else
      state.outcomes_by_slice
    end
  end

  defp emit_run_started!(nil, _order, _work_graph), do: :ok

  defp emit_run_started!(ledger, order, work_graph) do
    write_run_event!(ledger, "run.started", "started", %{
      "slice_ids" => order,
      "work_graph" => jsonable(work_graph)
    })
  end

  defp emit_run_terminal!(nil, _events), do: :ok

  defp emit_run_terminal!(ledger, events) do
    {type, suffix} =
      if run_budget_reaped?(events),
        do: {"run.reaped", "reaped"},
        else: {"run.finished", "finished"}

    write_run_event!(ledger, type, suffix, %{
      "status" => to_string(run_status(events)),
      "slice_count" => length(events)
    })
  end

  # A run-level reap: the run-budget deadline was exhausted (reason "run_deadline"),
  # which the reaper applies to every remaining slice. Per-slice "slice_deadline" reaps
  # are normal parked slices the run continued past and do NOT make the run reaped.
  defp run_budget_reaped?(events) do
    Enum.any?(events, &(get_in(&1, ["reaped", "reason"]) == "run_deadline"))
  end

  defp write_run_event!(ledger, type, suffix, payload) do
    write_ledger_event!(ledger, "run:#{ledger.run_id}:#{suffix}", type, payload)
  end

  defp commit_slice_outcome!(nil, _event), do: :ok

  defp commit_slice_outcome!(ledger, event) do
    key = "run:#{ledger.run_id}:slice:#{event["slice_id"]}:#{event["sequence"]}"
    write_ledger_event!(ledger, key, "run.slice_outcome", slice_outcome_payload(event))
  end

  # Minimal resume-only vocabulary: exactly what reconstruction (U3) and exactly-once
  # reconciliation (U5) consume — not the richer per-attempt detail the deferred M4/eval
  # payoffs will want. head_commit/head_tree are present only on passed slices.
  defp slice_outcome_payload(event) do
    event
    |> Map.take([
      "slice_id",
      "sequence",
      "status",
      "gate_result",
      "run_attempt_outcome",
      "findings",
      "blocked_by",
      "head_commit",
      "head_tree",
      "reaped"
    ])
    |> jsonable()
  end

  # No `return_notifications?` — let Ledger.write! fan out the outbox notification
  # internally (we are not inside a notification-collecting transaction here).
  defp write_ledger_event!(ledger, idempotency_key, type, payload) do
    Ledger.write!(%{
      project_id: ledger.project_id,
      idempotency_key: idempotency_key,
      type: type,
      payload: Map.put(payload, "run_id", ledger.run_id)
    })

    :ok
  end

  defp put_head_provenance(event, %{"head_commit" => _} = head), do: Map.merge(event, head)
  defp put_head_provenance(event, _head), do: event

  # The ledger payload is an Ash `:map` (JSON); atom values (`run_attempt_outcome`,
  # finding categories) must be stringified so Jason can encode them.
  defp jsonable(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp jsonable(value) when is_list(value), do: Enum.map(value, &jsonable/1)

  defp jsonable(value) when is_map(value),
    do: Map.new(value, fn {key, val} -> {to_string(key), jsonable(val)} end)

  defp jsonable(value), do: value

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      nil -> []
      value -> [value]
    end
  end

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp value(_map, _key, default), do: default

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_nested(value)} end)
  end

  defp stringify_nested(value) when is_map(value), do: stringify_keys(value)
  defp stringify_nested(value) when is_list(value), do: Enum.map(value, &stringify_nested/1)
  defp stringify_nested(value), do: value

  defp git!(workspace_path, args) do
    case System.cmd("git", ["-C", workspace_path | args], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git #{Enum.join(args, " ")} failed (#{status}): #{output}"
    end
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
