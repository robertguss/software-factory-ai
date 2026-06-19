defmodule Conveyor.Eval.LiftDuelTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.AgentRunner.ReferenceSolution
  alias Conveyor.Eval.{BridgeFixtures, LiftDuel, Scorecard, Schema}

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

    # Verified ACs: only the fixed arm restores the acceptance test.
    assert treatment["verified_acs_total"] > 0
    assert vanilla["verified_acs_total"] == 0

    # The headline lift.
    assert report["lift"]["treatment_arm"] == "conveyor"
    assert report["lift"]["pass_at_1_delta"] == 1.0
    assert report["lift"]["verified_acs_delta"] > 0

    # Schema-valid (report/2 already validated; assert explicitly for clarity).
    assert Schema.validate(report, "conveyor.eval_lift@1") == :ok
  end

  test "emit! writes the lift_duel scorecard inputs (lift_vs_vanilla, pass_at_1, cost_per_verified_ac)" do
    treatment =
      LiftDuel.summarize_arm(
        "conveyor",
        "reference_solution",
        arm_cells("conveyor", &mutant/1, true)
      )

    vanilla =
      LiftDuel.summarize_arm(
        "vanilla",
        "reference_solution",
        arm_cells("vanilla", fn _ -> @known_good end, false)
      )

    report = LiftDuel.report([vanilla, treatment], tasks: @tasks, reasoning_effort: "high")
    LiftDuel.emit!(report)

    path = Path.join(Scorecard.inputs_dir(), "lift_duel.json")
    assert File.exists?(path)

    keys = path |> File.read!() |> Jason.decode!() |> Enum.map(& &1["key"]) |> Enum.sort()
    assert keys == ["cost_per_verified_ac", "lift_vs_vanilla", "pass_at_1"]
  end
end
