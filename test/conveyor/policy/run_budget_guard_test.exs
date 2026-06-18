defmodule Conveyor.Policy.RunBudgetGuardTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Config.CommandSpec
  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunBudget
  alias Conveyor.Factory.Slice
  alias Conveyor.Policy.NormalizedCommand
  alias Conveyor.Policy.RunBudgetGuard
  alias Conveyor.Sandbox.Runner
  alias Conveyor.ToolExecutor

  setup do
    blob_root = temp_dir!("budget-blobs")

    fixture =
      create_artifact_run!(
        blob_root: blob_root,
        artifact_content: "budget fixture\n"
      )

    slice = get_by_id!(Slice, fixture.run_attempt.slice_id)

    %{
      blob_root: blob_root,
      run_attempt: fixture.run_attempt,
      slice: slice,
      station_run: fixture.station_run
    }
  end

  test "tool execution that exceeds output budget stops the run with consumed-counter finding",
       %{
         blob_root: blob_root,
         run_attempt: run_attempt,
         slice: slice,
         station_run: station_run
       } do
    slice = Ash.update!(slice, %{state: :in_progress}, domain: Factory)
    run_attempt = Ash.update!(run_attempt, %{status: :running}, domain: Factory)
    budget = create_budget!(run_attempt, max_output_bytes: 4)
    command = normalized_command(["echo", "too-much"])
    policy = policy()

    result =
      ToolExecutor.execute!(command, policy,
        blob_root: blob_root,
        run_budget_id: budget.id,
        run_attempt_id: run_attempt.id,
        station_run_id: station_run.id,
        runner: fn _command ->
          %Runner.Result{exit_code: 0, stdout: "12345", stderr: "", duration_ms: 8}
        end
      )

    assert result.budget.status == :exhausted
    assert result.budget.exceeded_cap == :max_output_bytes

    exhausted_budget = get_by_id!(RunBudget, budget.id)
    assert exhausted_budget.status == :exhausted
    assert exhausted_budget.consumed_tool_calls == 1
    assert exhausted_budget.consumed_command_count == 1
    assert exhausted_budget.consumed_output_bytes == 5

    stopped_attempt = get_by_id!(RunAttempt, run_attempt.id)
    assert stopped_attempt.status == :failed
    assert stopped_attempt.outcome == :needs_rework
    assert stopped_attempt.failure_category == "budget_exhausted"

    assert get_by_id!(Slice, slice.id).state == :needs_rework

    assert [event] =
             LedgerEvent
             |> Ash.read!(domain: Factory)
             |> Enum.filter(&(&1.type == "budget.exhausted"))

    assert event.payload["finding"]["exceeded_cap"] == "max_output_bytes"
    assert event.payload["finding"]["consumed"]["output_bytes"] == 5
  end

  test "non-progress observations exhaust repeated command failure budget", %{
    run_attempt: run_attempt,
    slice: slice
  } do
    slice = Ash.update!(slice, %{state: :in_progress}, domain: Factory)
    run_attempt = Ash.update!(run_attempt, %{status: :running}, domain: Factory)
    budget = create_budget!(run_attempt, max_repeated_command_count: 2)

    result =
      RunBudgetGuard.record!(
        budget,
        %{repeated_command_count: 3, reason: "same command failed repeatedly"},
        slice_id: slice.id
      )

    assert result.status == :exhausted
    assert result.exceeded_cap == :max_repeated_command_count
    assert get_by_id!(RunBudget, budget.id).status == :exhausted
    assert get_by_id!(RunAttempt, run_attempt.id).failure_category == "budget_exhausted"
    assert get_by_id!(Slice, slice.id).state == :needs_rework
  end

  defp create_budget!(run_attempt, overrides) do
    attrs =
      %{
        run_attempt_id: run_attempt.id,
        max_wall_clock_ms: 900_000,
        max_idle_ms: 120_000,
        max_tool_calls: 200,
        max_command_count: 50,
        max_output_bytes: 10_000_000,
        max_repeated_command_count: 3,
        max_same_file_rewrites: 5,
        max_no_diff_progress_ms: 180_000
      }
      |> Map.merge(Map.new(overrides))

    Ash.create!(RunBudget, attrs, domain: Factory)
  end

  defp normalized_command(argv) do
    workspace_root = temp_dir!("budget-workspace")

    command_spec = %CommandSpec{
      key: List.first(argv),
      argv: argv,
      profile: :verify,
      network: :none,
      timeout_ms: 120_000
    }

    NormalizedCommand.normalize!(command_spec, workspace_root: workspace_root)
  end

  defp policy do
    %Conveyor.Factory.Policy{
      name: "verify",
      profile: :verify,
      allowlist: ["echo"],
      denylist: [],
      env_policy: %{"allowlist" => []},
      network_policy: %{"default" => "none"},
      budget_policy: %{},
      autonomy_ceiling: 1
    }
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
