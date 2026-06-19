defmodule Conveyor.Eval.LiftDuelLiveTest do
  @moduledoc """
  R5 seed run (M3): the real Codex lift duel. Excluded from CI (`:live_agent`); run
  manually to (re)seed the committed `eval/lift/seed.json` real-lift report:

      PGPORT=5433 MIX_ENV=test mix test test/conveyor/eval/lift_duel_live_test.exs --include live_agent

  Both arms get the same broken workspace and the same pytest failure output; the only
  difference is the prompt — the treatment ("conveyor") gets the structured brief
  (acceptance criterion + constraints + interface), the baseline ("vanilla") gets a
  naive "make them pass". Reasoning effort is held constant (`medium`) across arms — it
  is a confound, not an arm. Cassettes are recorded per cell for provenance (they
  reproduce the recorded agent output; cassette-based re-grading is approach B, deferred).
  """
  use ExUnit.Case, async: false

  alias Conveyor.AgentRunner.Codex
  alias Conveyor.Eval.{BridgeFixtures, LiftDuel, ToolchainRunner, Workspace}
  alias Conveyor.Factory.RunPrompt

  @moduletag :live_agent
  @moduletag timeout: 1_800_000

  # A real Codex run easily exceeds the default 120s sandbox ownership timeout, so the
  # owning test process would lose the DB connection mid-run. Extend it to cover all
  # six cells. (Custom setup instead of Conveyor.DataCase, which hardcodes the default.)
  setup do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Conveyor.Repo,
        shared: true,
        ownership_timeout: :timer.minutes(60)
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  @reasoning "medium"
  @canary "samples/tasks_service/.conveyor/canary"
  @plan_path Path.expand("samples/tasks_service/conveyor.plan.yml", File.cwd!())

  @tasks [
    "patch_unknown_id_returns_200",
    "completed_not_persisted_to_list",
    "default_completed_missing"
  ]

  @desired %{
    "patch_unknown_id_returns_200" =>
      "Completing a task whose id does not exist must return HTTP 404 (Task not found), not a 200 with a fabricated task.",
    "completed_not_persisted_to_list" =>
      "Completing a task must persist the change so the task appears as completed when the task list is fetched.",
    "default_completed_missing" =>
      "A newly created Task must default its `completed` field to False when it is not provided."
  }

  test "seed the real-Codex lift duel (writes eval/lift/seed.json)" do
    clear_cassettes()

    cells =
      Enum.map(@tasks, fn task ->
        failures = failing_tests_summary(task)
        treatment = live_cell(task, "conveyor", rich_brief(task, failures))
        vanilla = live_cell(task, "vanilla", naive_prompt(failures))
        {treatment, vanilla}
      end)

    treatment = LiftDuel.summarize_arm("conveyor", "codex", Enum.map(cells, &elem(&1, 0)))
    vanilla = LiftDuel.summarize_arm("vanilla", "codex", Enum.map(cells, &elem(&1, 1)))
    report = LiftDuel.report([vanilla, treatment], tasks: @tasks, reasoning_effort: @reasoning)

    path = LiftDuel.write_report!(report, name: "seed")

    IO.puts("\n=== R5 LIFT DUEL (real Codex, reasoning=#{@reasoning}) ===")
    IO.inspect(report["lift"], label: "lift")
    for arm <- [treatment, vanilla], do: IO.inspect(arm_summary(arm), label: arm["arm"])
    IO.puts("seed written: #{path}\n")

    assert length(cells) == 3
    assert File.exists?(path)
    # Provenance: a cassette per cell was recorded.
    for arm <- ["conveyor", "vanilla"], task <- @tasks do
      assert File.exists?(Path.join("eval/cassettes", "lift-#{arm}-#{task}.json"))
    end
  end

  defp live_cell(task, arm, body) do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "live-#{arm}-#{task}",
        adapter_name: "codex",
        break_with: mutant(task)
      )

    LiftDuel.run_cell(task, fixture, %{
      arm: arm,
      adapter: Codex,
      run_prompt: prompt_struct(body),
      reasoning_effort: @reasoning,
      cassette_key: "lift-#{arm}-#{task}"
    })
  end

  defp rich_brief(task, failures) do
    """
    You are an implementer fixing a single behavioral bug in a FastAPI tasks service (Python).

    # Acceptance criterion
    #{@desired[task]}

    # Current (incorrect) behavior — these tests are RED:
    #{failures}

    # Constraints
    - Fix by editing the application code under tasks_service/. Do NOT modify, weaken,
      delete, or skip any test. Change only what the acceptance criterion requires.
    - You cannot execute the test suite in this environment; reason about the code.

    # Key interface
    tasks_service/main.py
    """
  end

  defp naive_prompt(failures) do
    """
    Some tests are failing in this Python project:

    #{failures}

    Fix the code so all tests pass. Do not modify the tests. You cannot run the tests here.
    """
  end

  defp failing_tests_summary(task) do
    ws = Workspace.setup!()
    Workspace.apply_patch!(ws, mutant(task))
    plan = YamlElixir.read_from_file!(@plan_path)
    vr = ToolchainRunner.verification_result(ws, plan, Workspace.venv_opts())
    Workspace.cleanup(ws)

    (vr["suites"] || [])
    |> Enum.find(%{}, &(&1["suite_kind"] == "baseline_regression"))
    |> suite_tests()
    |> Enum.filter(&(&1["status"] == "failed"))
    |> Enum.map_join("\n", &"- #{&1["id"]}: #{String.slice(&1["message"] || "", 0, 240)}")
  end

  defp suite_tests(suite) do
    (suite["commands"] || [])
    |> Enum.flat_map(&(&1["attempts"] || []))
    |> Enum.flat_map(&(&1["tests"] || []))
  end

  defp prompt_struct(body) do
    %RunPrompt{
      body: body,
      body_sha256: "sha256:" <> Base.encode16(:crypto.hash(:sha256, body), case: :lower)
    }
  end

  defp arm_summary(arm) do
    Map.take(arm, [
      "pass_at_1",
      "ci",
      "passes",
      "trials",
      "verified_acs_total",
      "tokens_total",
      "cost_usd_total",
      "cost_per_verified_ac"
    ])
  end

  defp mutant(task), do: "#{@canary}/mutants/#{task}.patch"

  defp clear_cassettes do
    for arm <- ["conveyor", "vanilla"], task <- @tasks do
      File.rm(Path.join("eval/cassettes", "lift-#{arm}-#{task}.json"))
    end
  end
end
