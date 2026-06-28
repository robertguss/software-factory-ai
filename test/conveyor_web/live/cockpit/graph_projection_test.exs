defmodule ConveyorWeb.Live.Cockpit.GraphProjectionTest do
  @moduledoc """
  U2 — the cockpit graph projection is the spine's correctness core, so the node
  taxonomy is exercised exhaustively against the PURE resolver (`resolve/3`, no
  DB), and `build/2` is covered with a smaller set of DB-backed wiring tests that
  prove the Plan-topology ↔ run-state join (live attempt rows by UUID, the
  run-scoped outcome fold by stable_key).
  """
  use Conveyor.DataCase, async: true

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

  alias Conveyor.CockpitFixtures
  alias Conveyor.Ledger
  alias ConveyorWeb.Live.Cockpit.GraphProjection

  @now ~U[2026-06-26 12:00:00Z]
  # The per-slice wall-clock cap (KTD4): a running station older than this is Stalled.
  @cap_ms 3_600_000

  # ─── Pure resolver: the node-state taxonomy (no DB) ────────────────────────

  describe "resolve/3 — derived states from edges + ready-set" do
    test "roots are ready-idle; a dependent with an unmet upstream is blocked and names it" do
      facts = [
        fact("a", stable_key: "SLICE-001", slice_state: :done),
        fact("b", stable_key: "SLICE-002"),
        fact("c", stable_key: "SLICE-003")
      ]

      edges = [edge("a", "b"), edge("b", "c")]

      %{nodes: nodes} = GraphProjection.resolve(facts, edges, now: @now)

      assert state(nodes, "a") == :done
      # b's only predecessor (a) is done → deps met, not running.
      assert state(nodes, "b") == :ready_idle
      # c's predecessor (b) is not done → blocked, naming the blocker (AE2).
      assert state(nodes, "c") == :blocked
      assert node(nodes, "c").blocked_by == ["SLICE-002"]
    end

    test "a dependent flips to ready-idle once every upstream is done" do
      facts = [
        fact("a", slice_state: :done),
        fact("b", slice_state: :done),
        fact("c")
      ]

      %{nodes: nodes} =
        GraphProjection.resolve(facts, [edge("a", "c"), edge("b", "c")], now: @now)

      assert state(nodes, "c") == :ready_idle
      assert node(nodes, "c").blocked_by == []
    end

    test "blocked names every unmet upstream, not the satisfied ones" do
      facts = [
        fact("a", stable_key: "A", slice_state: :done),
        fact("b", stable_key: "B"),
        fact("d")
      ]

      edges = [edge("a", "d"), edge("b", "d")]

      %{nodes: nodes} = GraphProjection.resolve(facts, edges, now: @now)

      assert state(nodes, "d") == :blocked
      assert node(nodes, "d").blocked_by == ["B"]
    end

    test "serial-tax: stats count how many nodes could run now (R12)" do
      facts = [fact("a"), fact("b"), fact("c")]
      %{stats: stats} = GraphProjection.resolve(facts, [], now: @now)
      assert stats.ready_idle_count == 3
    end
  end

  describe "resolve/3 — run-outcome states" do
    test "an upstream park skips its dependents; a skipped node surfaces its starved blast radius (AE3)" do
      facts = [
        fact("a", outcome_status: "parked"),
        fact("b", outcome_status: "skipped"),
        fact("c", outcome_status: "skipped")
      ]

      edges = [edge("a", "b"), edge("b", "c")]

      %{nodes: nodes} = GraphProjection.resolve(facts, edges, now: @now)

      assert state(nodes, "a") == :parked
      assert state(nodes, "b") == :skipped
      assert state(nodes, "c") == :skipped
      # b's transitive downstream that is also skipped = {c}: R13 starved count.
      assert node(nodes, "b").starved_dependents == 1
      assert node(nodes, "c").starved_dependents == 0
    end

    test "a passed outcome reads as done and satisfies downstream predecessors" do
      facts = [fact("a", outcome_status: "passed"), fact("b")]
      %{nodes: nodes} = GraphProjection.resolve(facts, [edge("a", "b")], now: @now)

      assert state(nodes, "a") == :done
      assert state(nodes, "b") == :ready_idle
    end
  end

  describe "resolve/3 — live attempt states + precedence (R10)" do
    test "a running station past its cap is Stalled; within its cap stays Running (AE4)" do
      facts = [
        fact("over", running_since: DateTime.add(@now, -2, :hour)),
        fact("under", running_since: DateTime.add(@now, -10, :minute))
      ]

      %{nodes: nodes} = GraphProjection.resolve(facts, [], now: @now, slice_cap_ms: @cap_ms)

      assert state(nodes, "over") == :stalled
      assert state(nodes, "under") == :running
    end

    test "a `false` wall-clock cap disables the Stalled signal, same as nil (#14)" do
      # `serial_driver_slice_wall_clock_ms` is documented as nil/false to disable
      # (config/config.exs). A long-running station must NOT read Stalled under a
      # `false` cap — and not merely by accident of number-vs-atom term ordering.
      over = fact("over", running_since: DateTime.add(@now, -5, :hour))

      %{nodes: nodes} = GraphProjection.resolve([over], [], now: @now, slice_cap_ms: false)

      assert state(nodes, "over") == :running
    end

    test "in_progress slice with no station row still reads Running" do
      %{nodes: nodes} =
        GraphProjection.resolve([fact("x", slice_state: :in_progress)], [], now: @now)

      assert state(nodes, "x") == :running
    end

    test "precedence: Stalled over Running over Skipped on one node" do
      stalled_and_skipped =
        fact("s", running_since: DateTime.add(@now, -2, :hour), outcome_status: "skipped")

      running_and_skipped =
        fact("r", running_since: DateTime.add(@now, -5, :minute), outcome_status: "skipped")

      %{nodes: nodes} =
        GraphProjection.resolve([stalled_and_skipped, running_and_skipped], [],
          now: @now,
          slice_cap_ms: @cap_ms
        )

      assert state(nodes, "s") == :stalled
      assert state(nodes, "r") == :running
    end

    test "precedence: Skipped over Blocked" do
      facts = [fact("a"), fact("b", outcome_status: "skipped")]
      %{nodes: nodes} = GraphProjection.resolve(facts, [edge("a", "b")], now: @now)
      # b has an unmet predecessor but its committed outcome is skipped → skipped wins.
      assert state(nodes, "b") == :skipped
    end
  end

  describe "resolve/3 — historical (live? false) and edge shapes" do
    test "historical ignores durable slice_state + live stations, using only the run's outcomes" do
      facts = [
        # Durable state and a running station belong to a LATER run; for a historical
        # run only the committed outcome counts.
        fact("a",
          slice_state: :in_progress,
          running_since: DateTime.add(@now, -2, :hour),
          outcome_status: "passed"
        ),
        fact("b", slice_state: :done)
      ]

      %{nodes: nodes} = GraphProjection.resolve(facts, [], now: @now, live?: false)

      assert state(nodes, "a") == :done
      # b has no outcome in this historical run and its durable :done is ignored → idle/ready.
      assert state(nodes, "b") == :ready_idle
    end

    test "empty graph yields no nodes and a zero serial-tax" do
      assert %{nodes: [], stats: %{ready_idle_count: 0}} =
               GraphProjection.resolve([], [], now: @now)
    end

    test "single isolated node with no run is ready-idle" do
      %{nodes: nodes} = GraphProjection.resolve([fact("solo")], [], now: @now)
      assert state(nodes, "solo") == :ready_idle
    end
  end

  # ─── DB-backed build/2: the topology ↔ run-state join ──────────────────────

  describe "build/2 — Plan topology joined with run state" do
    test "joins the plan's slices + TaskDependency edges + epics, keyed by slice UUID" do
      %{plan: plan, epic: epic, slices: s} =
        seed_plan([{"SLICE-001", :ready}, {"SLICE-002", :ready}], [{"SLICE-001", "SLICE-002"}])

      model = GraphProjection.build(plan.id, now: @now)

      ids = MapSet.new(model.nodes, & &1.id)
      assert MapSet.member?(ids, s["SLICE-001"].id)
      assert MapSet.member?(ids, s["SLICE-002"].id)
      assert [%{from: from, to: to}] = model.edges
      assert from == s["SLICE-001"].id
      assert to == s["SLICE-002"].id
      assert Enum.all?(model.nodes, &(&1.epic_id == epic.id))
      assert [%{id: epic_id}] = model.epics
      assert epic_id == epic.id
    end

    test "the run-scoped outcome fold (skipped/parked) joins by stable_key" do
      %{plan: plan, slices: s} =
        seed_plan(
          [{"SLICE-001", :parked}, {"SLICE-002", :ready}, {"SLICE-003", :ready}],
          [{"SLICE-001", "SLICE-002"}, {"SLICE-002", "SLICE-003"}]
        )

      run_id = "run-aaa"
      seed_run_started(run_id, ["SLICE-001", "SLICE-002", "SLICE-003"], @now)
      seed_outcome(run_id, "SLICE-001", "parked", 1)
      seed_outcome(run_id, "SLICE-002", "skipped", 2)
      seed_outcome(run_id, "SLICE-003", "skipped", 3)

      model = GraphProjection.build(plan.id, now: @now)

      assert node_state(model, s["SLICE-001"].id) == :parked
      assert node_state(model, s["SLICE-002"].id) == :skipped
      assert node_state(model, s["SLICE-003"].id) == :skipped
      assert node_for(model, s["SLICE-002"].id).starved_dependents == 1
    end

    test "overlays a running station: Stalled past cap, Running within cap (real stored rows)" do
      %{plan: plan, slices: s} =
        seed_plan([{"SLICE-001", :in_progress}, {"SLICE-002", :in_progress}], [])

      seed_running_station(s["SLICE-001"], DateTime.add(@now, -2, :hour))
      seed_running_station(s["SLICE-002"], DateTime.add(@now, -5, :minute))

      # The cap is disabled in test config, so pin production's per-slice cap.
      model = GraphProjection.build(plan.id, now: @now, slice_cap_ms: @cap_ms)

      assert node_state(model, s["SLICE-001"].id) == :stalled
      assert node_state(model, s["SLICE-002"].id) == :running
    end

    test "a historical run shows its own outcome fold, not the most-recent run's" do
      %{plan: plan, slices: s} = seed_plan([{"SLICE-001", :ready}], [])

      seed_run_started("run-old", ["SLICE-001"], DateTime.add(@now, -1, :hour))
      seed_outcome("run-old", "SLICE-001", "passed", 1)
      seed_run_started("run-new", ["SLICE-001"], @now)
      seed_outcome("run-new", "SLICE-001", "skipped", 1)

      newest = GraphProjection.build(plan.id, now: @now)
      assert newest.run_id == "run-new"
      assert newest.live? == true
      assert node_state(newest, s["SLICE-001"].id) == :skipped

      historical = GraphProjection.build(plan.id, run_id: "run-old", now: @now)
      assert historical.live? == false
      assert node_state(historical, s["SLICE-001"].id) == :done
    end
  end

  describe "run discovery" do
    test "most_recent_run_id/0 and list_runs/0 are ordered newest-first" do
      seed_run_started("run-1", ["SLICE-001"], DateTime.add(@now, -2, :hour))
      seed_run_started("run-2", ["SLICE-001"], @now)

      assert GraphProjection.most_recent_run_id() == "run-2"
      assert [%{run_id: "run-2"}, %{run_id: "run-1"}] = GraphProjection.list_runs()
    end
  end

  describe "recompute_slice/3 — the per-ping scoped entry point (U4 uses this)" do
    test "re-reads one slice, recomputes it + dependents, returns only changed nodes; idempotent" do
      %{plan: plan, slices: s} =
        seed_plan([{"SLICE-001", :ready}, {"SLICE-002", :ready}], [{"SLICE-001", "SLICE-002"}])

      model = GraphProjection.build(plan.id, now: @now)
      assert node_state(model, s["SLICE-001"].id) == :ready_idle
      assert node_state(model, s["SLICE-002"].id) == :blocked

      # The first slice completes; a ping for it arrives.
      Ash.update!(s["SLICE-001"], %{state: :done}, domain: Factory)

      {model2, changed} = GraphProjection.recompute_slice(model, s["SLICE-001"].id, now: @now)

      changed_ids = MapSet.new(changed, & &1.id)
      assert MapSet.member?(changed_ids, s["SLICE-001"].id)
      # The dependent flips blocked → ready-idle, so it is part of the targeted patch.
      assert MapSet.member?(changed_ids, s["SLICE-002"].id)
      assert node_state(model2, s["SLICE-001"].id) == :done
      assert node_state(model2, s["SLICE-002"].id) == :ready_idle

      # Idempotent: applying the same ping again changes nothing.
      {_model3, changed_again} =
        GraphProjection.recompute_slice(model2, s["SLICE-001"].id, now: @now)

      assert changed_again == []
    end
  end

  describe "node_detail/2 — read-only drill-down (R15, KTD2)" do
    test "a historical (finished) run omits live attempt/station/elapsed (#4, KTD2)" do
      %{plan: plan, slices: s} = seed_plan([{"SLICE-001", :in_progress}], [])

      # A running station exists — it is the LIVE run's state, not the historical
      # run's. A finished run is not running, so its panel must not borrow it.
      seed_running_station(s["SLICE-001"], DateTime.add(@now, -5, :minute))
      seed_run_started("run-old", ["SLICE-001"], DateTime.add(@now, -1, :hour))
      seed_outcome("run-old", "SLICE-001", "passed", 1)
      seed_run_started("run-new", ["SLICE-001"], @now)

      historical = GraphProjection.build(plan.id, run_id: "run-old", now: @now)
      assert historical.live? == false

      detail = GraphProjection.node_detail(historical, s["SLICE-001"].id)

      # The committed outcome still shows (passed → done), but no live attempt state.
      assert detail.state == :done
      assert detail.station == nil
      assert detail.attempt_no == nil
      assert detail.attempt_status == nil
      assert detail.started_at == nil
      assert detail.elapsed_seconds == nil
    end

    test "a live run loads the attempt's gate / review / evidence, reflecting verdicts (R7/R8)" do
      %{plan: plan, slices: s} = seed_plan([{"SLICE-001", :gated}], [])

      CockpitFixtures.seed_attempt_with_verdict(s["SLICE-001"],
        gate: %{
          passed: false,
          stages: [
            %{"name" => "tests", "status" => "no_go"},
            %{"name" => "coverage", "status" => "baseline_absent"}
          ],
          trust_score: %{"verdict" => "abstain"}
        },
        review: %{decision: :needs_rework, recommendation: :ask_human, summary: "needs a human"},
        evidence: %{summary: "did the thing", acceptance_results: [%{"name" => "AC1"}], risks: []}
      )

      model = GraphProjection.build(plan.id, now: @now)
      assert model.live? == true

      detail = GraphProjection.node_detail(model, s["SLICE-001"].id)

      assert detail.gate.passed == false
      # Abstain / baseline_absent are reflected verbatim — never upgraded to a pass.
      assert %{"name" => "coverage", "status" => "baseline_absent"} in detail.gate.stages
      assert detail.gate.trust_score == %{"verdict" => "abstain"}

      assert [review] = detail.reviews
      assert review.decision == :needs_rework
      assert review.recommendation == :ask_human

      assert [evidence] = detail.evidence
      assert evidence.summary == "did the thing"
    end

    test "a finished run projects the committed verdict from the outcome payload, not empty (AE11)" do
      %{plan: plan, slices: s} = seed_plan([{"SLICE-001", :in_progress}], [])
      seed_run_started("run-old", ["SLICE-001"], DateTime.add(@now, -1, :hour))
      seed_outcome("run-old", "SLICE-001", "parked", 1)
      seed_run_started("run-new", ["SLICE-001"], @now)

      historical = GraphProjection.build(plan.id, run_id: "run-old", now: @now)
      assert historical.live? == false

      detail = GraphProjection.node_detail(historical, s["SLICE-001"].id)

      # The committed verdict shows (not an empty panel); attempt-tied rows do not,
      # since the latest attempt belongs to a later run (KTD5).
      assert detail.gate.status == "parked"
      assert detail.reviews == []
      assert detail.evidence == []
    end

    test "elapsed never goes negative when a station started after the model's `now` (#10)" do
      %{plan: plan, slices: s} = seed_plan([{"SLICE-001", :in_progress}], [])

      # The model's `now` is captured, then a fresh DB read sees a station that
      # started slightly later — diff would be negative without a clamp.
      seed_running_station(s["SLICE-001"], DateTime.add(@now, 5, :second))

      model = GraphProjection.build(plan.id, now: @now, slice_cap_ms: @cap_ms)
      detail = GraphProjection.node_detail(model, s["SLICE-001"].id)

      assert detail.elapsed_seconds == 0
    end
  end

  describe "build/2 — query scoping (#15)" do
    test "another plan's slices, edges, attempts, and stations never leak into this plan's build" do
      %{plan: plan_a, slices: a} =
        seed_plan([{"A-1", :ready}, {"A-2", :ready}], [{"A-1", "A-2"}])

      # A second plan with its own edge + a running attempt/station. Pushing the
      # membership filter into the Ash query must still scope strictly to plan A.
      %{slices: b} = seed_plan([{"B-1", :ready}, {"B-2", :ready}], [{"B-1", "B-2"}])
      seed_running_station(b["B-1"], DateTime.add(@now, -2, :hour))

      model = GraphProjection.build(plan_a.id, now: @now, slice_cap_ms: @cap_ms)

      assert MapSet.new(model.nodes, & &1.id) == MapSet.new([a["A-1"].id, a["A-2"].id])
      # Only A's single edge survives — none of B's.
      assert [%{from: from, to: to}] = model.edges
      assert from == a["A-1"].id and to == a["A-2"].id
    end
  end

  # ─── helpers ───────────────────────────────────────────────────────────────

  defp fact(id, attrs \\ []) do
    %{
      id: id,
      stable_key: Keyword.get(attrs, :stable_key, id),
      title: Keyword.get(attrs, :title, id),
      epic_id: Keyword.get(attrs, :epic_id, "epic"),
      slice_state: Keyword.get(attrs, :slice_state, :ready),
      outcome_status: Keyword.get(attrs, :outcome_status),
      running_since: Keyword.get(attrs, :running_since)
    }
  end

  defp edge(from, to), do: %{from: from, to: to, kind: "execution_hard"}

  defp node(nodes, id), do: Enum.find(nodes, &(&1.id == id))
  defp state(nodes, id), do: node(nodes, id).state

  defp node_for(model, id), do: node(model.nodes, id)
  defp node_state(model, id), do: node_for(model, id).state

  defp seed_plan(slice_specs, edge_specs) do
    # Unique per call so a single test may seed more than one plan (e.g. the
    # cross-plan query-scoping test) without colliding on project/plan identities.
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
          intent: "Exercise the cockpit projection.",
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

  defp seed_run_started(run_id, slice_keys, occurred_at) do
    Ledger.write!(%{
      project_id: any_project_id(),
      idempotency_key: "#{run_id}:started",
      type: "run.started",
      payload: %{"run_id" => run_id, "slice_ids" => slice_keys},
      occurred_at: occurred_at
    })
  end

  defp seed_outcome(run_id, stable_key, status, sequence) do
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
      occurred_at: @now
    })
  end

  defp seed_running_station(slice, started_at) do
    run_spec =
      Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

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
