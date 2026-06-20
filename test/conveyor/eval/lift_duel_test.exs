defmodule Conveyor.Eval.LiftDuelTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.AgentRunner.ReferenceSolution
  alias Conveyor.Eval.{BridgeFixtures, LiftDuel, Schema, Scorecard}

  @moduletag :eval
  @moduletag timeout: 600_000

  @canary "samples/tasks_service/.conveyor/canary"
  @known_good "#{@canary}/known_good.patch"

  # Each behavioral mutant is a broken→fix task: the bare sample is correct/green, so
  # `break_with: mutant` makes a broken base (one acceptance test red) and the agent
  # must restore green. Deterministic, $0: ReferenceSolution simulates the arms — the
  # treatment reverses the mutant (the fix → PASS); the baseline applies a behavioral
  # no-op (known_good's comment → still red → FAIL).
  @tasks [
    "patch_unknown_id_returns_200",
    "completed_not_persisted_to_list",
    "default_completed_missing"
  ]

  defp mutant(task), do: "#{@canary}/mutants/#{task}.patch"

  defp arm_cells(arm, reference_patch_fun, reverse) do
    for task <- @tasks do
      fixture =
        BridgeFixtures.sample_fixture!(
          label: "lift-#{arm}-#{task}",
          adapter_name: "reference_solution",
          break_with: mutant(task)
        )

      LiftDuel.run_cell(task, fixture, %{
        arm: arm,
        adapter: ReferenceSolution,
        reference_patch: reference_patch_fun.(task),
        reverse: reverse
      })
    end
  end

  test "lift duel: the full-loop arm fixes the broken tasks where the vanilla arm does not" do
    treatment_cells = arm_cells("conveyor", &mutant/1, true)
    vanilla_cells = arm_cells("vanilla", fn _task -> @known_good end, false)

    treatment = LiftDuel.summarize_arm("conveyor", "reference_solution", treatment_cells)
    vanilla = LiftDuel.summarize_arm("vanilla", "reference_solution", vanilla_cells)

    report = LiftDuel.report([vanilla, treatment], tasks: @tasks, reasoning_effort: nil)

    # Per-cell ground truth: treatment fixes (green), vanilla leaves it broken (red).
    assert Enum.all?(treatment_cells, & &1["gate_passed"])
    refute Enum.any?(vanilla_cells, & &1["gate_passed"])

    # Arm aggregates over ≥3 tasks, with exact CIs.
    assert treatment["pass_at_1"] == 1.0
    assert vanilla["pass_at_1"] == 0.0
    assert [lo, hi] = treatment["ci"]
    assert lo > 0.0 and hi == 1.0

    # Verified ACs (delivered through an accepted gate): only the fixed arm restores them.
    assert treatment["verified_acs_total"] > 0
    assert vanilla["verified_acs_total"] == 0

    # The headline lift.
    assert report["lift"]["treatment_arm"] == "conveyor"
    assert report["lift"]["pass_at_1_delta"] == 1.0
    assert report["lift"]["verified_acs_delta"] > 0

    # Schema-valid, and the report persists as the rich artifact (throwaway dir so the
    # deterministic run never collides with the committed real seed CI projects).
    assert Schema.validate(report, "conveyor.eval_lift@1") == :ok
    dir = Path.join(System.tmp_dir!(), "lift-report-#{System.unique_integer([:positive])}")
    path = LiftDuel.write_report!(report, dir: dir)
    assert File.exists?(path)
  end

  test "mix conveyor.eval.lift projects a report into scorecard inputs (DB-free)" do
    # A synthesized, schema-valid report (no agent run needed) exercises the
    # measurement→reporting seam the CI step relies on.
    cell = fn task, passed, verified ->
      %{
        "task" => task,
        "gate_passed" => passed,
        "false_pass" => false,
        "verified_acs" => verified,
        "tokens" => 1200,
        "cost_usd" => 0.01,
        "latency_ms" => 9000,
        "reasoning_effort" => "medium"
      }
    end

    treatment =
      LiftDuel.summarize_arm("conveyor", "codex", Enum.map(@tasks, &cell.(&1, true, 4)))

    vanilla =
      LiftDuel.summarize_arm("vanilla", "codex", Enum.map(@tasks, &cell.(&1, false, 0)))

    report = LiftDuel.report([vanilla, treatment], tasks: @tasks, reasoning_effort: "medium")

    # Project from a throwaway dir under a self-test name, and clean the scorecard
    # input on exit — so this never competes with the committed real seed
    # (eval/lift/seed.json), which is CI's sole lift source.
    dir = Path.join(System.tmp_dir!(), "lift-report-#{System.unique_integer([:positive])}")
    LiftDuel.write_report!(report, dir: dir, name: "lift_duel_selftest")
    path = Path.join(Scorecard.inputs_dir(), "lift_duel_selftest.json")
    on_exit(fn -> File.rm(path) end)

    Mix.Tasks.Conveyor.Eval.Lift.run([dir])
    assert File.exists?(path)

    metrics = path |> File.read!() |> Jason.decode!()

    assert Enum.map(metrics, & &1["key"]) |> Enum.sort() == [
             "cost_per_verified_ac",
             "lift_vs_vanilla",
             "pass_at_1"
           ]

    assert Enum.all?(metrics, &(&1["suite"] == "lift_duel"))

    # conveyor.agent_usage@1 cost records project per cell and are schema-valid.
    usages = LiftDuel.usage_records(report)
    assert length(usages) == 6
    assert Enum.all?(usages, &(Schema.validate(&1, "conveyor.agent_usage@1") == :ok))

    # cost-per-verified-AC is honest: the failing vanilla arm delivered 0 ACs.
    assert vanilla["cost_per_verified_ac"] == nil
    assert treatment["cost_per_verified_ac"] == Float.round(0.03 / 12, 6)
  end
end
