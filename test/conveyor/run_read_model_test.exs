defmodule Conveyor.RunReadModelTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.FactoryFixtures
  alias Conveyor.RunReadModel

  # --- Pure projection (no DB, injected outcomes) ----------------------------
  #
  # Mirrors planning_run_reconstruction_test: build the outcomes map by hand and call the
  # pure projection directly. These assert the fold + stop-point + status skeleton.

  describe "project/4 (pure)" do
    defp outcome(slice_id, sequence, status, attempt_outcome \\ nil) do
      {slice_id,
       %{
         "run_id" => "r",
         "slice_id" => slice_id,
         "sequence" => sequence,
         "status" => status,
         "run_attempt_outcome" => attempt_outcome
       }}
    end

    defp project(order, outcomes, status) do
      RunReadModel.project("r", order, Map.new(outcomes), status: status)
    end

    test "(1) a 3-slice all-passed run folds to 3 passed slices, nil stop point, complete" do
      order = ["SLICE-001", "SLICE-002", "SLICE-003"]

      story =
        project(
          order,
          [
            outcome("SLICE-001", 1, "passed"),
            outcome("SLICE-002", 2, "passed"),
            outcome("SLICE-003", 3, "passed")
          ],
          :complete
        )

      assert story.status == :complete
      assert story.stop_point == nil
      assert story.slice_count == 3
      assert Enum.map(story.slices, & &1.slice_id) == order
      assert Enum.map(story.slices, & &1.outcome) == ["passed", "passed", "passed"]
      assert Enum.map(story.slices, & &1.sequence) == [1, 2, 3]
    end

    test "(2) slices 1-2 have outcomes, slice 3 has none -> stop point slice 3, interrupted" do
      order = ["SLICE-001", "SLICE-002", "SLICE-003"]

      story =
        project(
          order,
          [
            outcome("SLICE-001", 1, "passed"),
            outcome("SLICE-002", 2, "passed")
          ],
          :interrupted
        )

      assert story.status == :interrupted
      assert story.stop_point == "SLICE-003"
      # Slice 3 still appears in the ordered list, with a nil outcome.
      assert List.last(story.slices).slice_id == "SLICE-003"
      assert List.last(story.slices).outcome == nil
    end

    test "(3) a non-passed slice renders parked and later independents still appear" do
      order = ["SLICE-001", "SLICE-002", "SLICE-003"]

      story =
        project(
          order,
          [
            outcome("SLICE-001", 1, "passed"),
            outcome("SLICE-002", 2, "parked", "needs_rework"),
            outcome("SLICE-003", 3, "passed")
          ],
          :parked
        )

      assert story.status == :parked
      [_s1, s2, s3] = story.slices
      assert s2.outcome == "parked"
      assert s2.run_attempt_outcome == "needs_rework"
      # An independent slice after the parked one still appears with its outcome.
      assert s3.outcome == "passed"
    end

    test "(3b) findings and gate_result surface straight from the slice outcome payload" do
      order = ["SLICE-001"]

      payload = %{
        "run_id" => "r",
        "slice_id" => "SLICE-001",
        "sequence" => 1,
        "status" => "parked",
        "run_attempt_outcome" => "needs_rework",
        "gate_result" => "eventual_pending",
        "findings" => ["out_of_scope_path"]
      }

      [slice] = project(order, [{"SLICE-001", payload}], :parked).slices

      # The run-scoped "why" needs no DB join — it rides the ledger outcome event.
      assert slice.gate_result == "eventual_pending"
      assert slice.findings == ["out_of_scope_path"]
    end

    test "(3c) a slice with no findings defaults to an empty list, never nil" do
      [slice] = project(["SLICE-001"], [outcome("SLICE-001", 1, "passed")], :complete).slices

      assert slice.findings == []
      assert slice.gate_result == nil
    end

    test "(8) an unknown run_id -> empty slices, nil stop point, status :unknown, no crash" do
      story = RunReadModel.project("nope", [], %{}, status: :unknown)

      assert story.status == :unknown
      assert story.stop_point == nil
      assert story.slice_count == 0
      assert story.slices == []
    end
  end

  describe "classify_status/1 (pure)" do
    defp ev(type, run_id \\ "r"), do: %{type: type, payload: %{"run_id" => run_id}}

    test "finished -> complete; reaped -> reaped; parked -> parked; started-only -> interrupted; none -> unknown" do
      assert RunReadModel.classify_status([ev("run.started"), ev("run.finished")]) == :complete
      assert RunReadModel.classify_status([ev("run.started"), ev("run.reaped")]) == :reaped
      assert RunReadModel.classify_status([ev("run.started"), ev("run.parked")]) == :parked
      assert RunReadModel.classify_status([ev("run.started")]) == :interrupted
      assert RunReadModel.classify_status([]) == :unknown
    end
  end

  # --- DB-backed enrichment --------------------------------------------------

  describe "summarize/1 (DB-backed)" do
    test "(1) a 3-slice completed run -> status complete, nil stop point" do
      %{run_id: run_id, slices: slices} =
        FactoryFixtures.create_run_with_ledger!(
          terminal: :finished,
          slices: [
            %{status: "passed"},
            %{status: "passed"},
            %{status: "passed"}
          ]
        )

      story = RunReadModel.summarize(run_id)

      assert story.status == :complete
      assert story.stop_point == nil
      assert story.slice_count == 3
      assert Enum.map(story.slices, & &1.slice_id) == Enum.map(slices, & &1.stable_key)
      assert Enum.all?(story.slices, &(&1.outcome == "passed"))
    end

    test "(2) slices 1-2 committed, slice 3 none -> stop point slice 3, interrupted" do
      %{run_id: run_id, slices: [_s1, _s2, s3]} =
        FactoryFixtures.create_run_with_ledger!(
          terminal: :none,
          slices: [
            %{status: "passed"},
            %{status: "passed"},
            # No :status key -> no run.slice_outcome event -> this is the in-flight slice.
            %{}
          ]
        )

      story = RunReadModel.summarize(run_id)

      assert story.status == :interrupted
      assert story.stop_point == s3.stable_key
      assert List.last(story.slices).outcome == nil
    end

    test "(3) a needs_rework slice renders parked and later independents still appear" do
      %{run_id: run_id} =
        FactoryFixtures.create_run_with_ledger!(
          terminal: :none,
          slices: [
            %{status: "passed"},
            %{status: "parked", run_attempt_outcome: "needs_rework", outcome: :needs_rework},
            %{status: "passed"}
          ]
        )

      story = RunReadModel.summarize(run_id)
      [_s1, s2, s3] = story.slices

      assert s2.outcome == "parked"
      assert s2.run_attempt_outcome == "needs_rework"
      assert s3.outcome == "passed"
    end

    test "(4) a GateResult with a failing stage surfaces stage + status; abstain surfaces band/score" do
      %{run_id: run_id} =
        FactoryFixtures.create_run_with_ledger!(
          terminal: :finished,
          slices: [
            %{
              status: "parked",
              outcome: :abstained,
              gate_result: "eventual_pending",
              findings: ["acceptance_locked_failed"],
              gate: %{
                passed: false,
                stages: [
                  %{"key" => "static", "status" => "passed"},
                  %{"key" => "tests", "status" => "failed"},
                  %{"key" => "review", "status" => "skipped"}
                ],
                trust_score: %{"band" => "abstain", "score" => 0.42, "extra" => "ignored"}
              }
            }
          ]
        )

      story = RunReadModel.summarize(run_id)
      [slice] = story.slices

      # Run-scoped ledger truth (the "why") rides the outcome event...
      assert slice.findings == ["acceptance_locked_failed"]
      assert slice.gate_result == "eventual_pending"
      # ...and the DB enrichment (joined via the persisted stable key) adds the
      # failing gate STAGE and trust verdict. First non-passed stage is surfaced
      # (the later "skipped" one is not).
      assert slice.gate.failed_stage == "tests"
      assert slice.gate.failed_status == "failed"
      # Only band/score are taken from the trust_score map.
      assert slice.gate.verdict == %{"band" => "abstain", "score" => 0.42}
    end

    test "(9) a stable key shared across two runs is not DB-enriched, but ledger findings still surface" do
      # Same explicit stable key in two runs => the key resolves to two slice
      # rows. With no run_id->slice link yet, the read model refuses to DB-enrich
      # (a blended gate/rework number would be worse than none) — but the
      # run-scoped ledger outcome still tells the honest story.
      shared = [
        %{
          status: "parked",
          outcome: :abstained,
          stable_key: "SLICE-001",
          findings: ["out_of_scope_path"],
          gate_result: "eventual_pending",
          gate: %{
            passed: false,
            stages: [%{"key" => "diff_scope", "status" => "failed"}],
            trust_score: %{"band" => "abstain", "score" => 0.1}
          }
        }
      ]

      %{run_id: run_a} =
        FactoryFixtures.create_run_with_ledger!(terminal: :finished, slices: shared)

      %{run_id: _run_b} =
        FactoryFixtures.create_run_with_ledger!(terminal: :finished, slices: shared)

      [slice] = RunReadModel.summarize(run_a).slices

      # Ledger truth still surfaces (run-scoped, no join):
      assert slice.findings == ["out_of_scope_path"]
      assert slice.gate_result == "eventual_pending"
      # DB enrich suppressed because "SLICE-001" is ambiguous across runs:
      assert slice.gate.failed_stage == nil
      assert slice.rework_attempts == 0
    end

    test "(5) a slice with two RunAttempt rows -> rework_attempts 2" do
      %{run_id: run_id} =
        FactoryFixtures.create_run_with_ledger!(
          terminal: :finished,
          slices: [
            %{status: "passed", attempts: 2}
          ]
        )

      story = RunReadModel.summarize(run_id)
      [slice] = story.slices

      assert slice.rework_attempts == 2
    end

    test "(6) all-nil AgentSession tokens -> spend :unknown; a non-nil value sums" do
      %{run_id: nil_run} =
        FactoryFixtures.create_run_with_ledger!(
          terminal: :finished,
          slices: [
            %{status: "passed", session: %{tokens: nil, cost_estimate: nil}}
          ]
        )

      %{run_id: real_run} =
        FactoryFixtures.create_run_with_ledger!(
          terminal: :finished,
          slices: [
            %{status: "passed", session: %{tokens: 1234, cost_estimate: Decimal.new("0.50")}}
          ]
        )

      [nil_slice] = RunReadModel.summarize(nil_run).slices
      [real_slice] = RunReadModel.summarize(real_run).slices

      # All-nil tokens -> unknown, NEVER 0.
      assert nil_slice.spend == :unknown
      assert real_slice.spend.tokens == 1234
      assert Decimal.equal?(real_slice.spend.cost_estimate, Decimal.new("0.50"))
    end

    test "(7) a run.reaped terminal -> status :reaped" do
      %{run_id: run_id} =
        FactoryFixtures.create_run_with_ledger!(
          terminal: :reaped,
          slices: [
            %{status: "passed"},
            %{status: "parked", run_attempt_outcome: "reaped"}
          ]
        )

      story = RunReadModel.summarize(run_id)

      assert story.status == :reaped
    end

    test "(8) an unknown run_id -> empty result, no crash" do
      story = RunReadModel.summarize(Ecto.UUID.generate())

      assert story.status == :unknown
      assert story.stop_point == nil
      assert story.slice_count == 0
      assert story.slices == []
    end
  end
end
