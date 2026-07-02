defmodule Mix.Tasks.Conveyor.RunViewTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.FactoryFixtures

  setup do
    test_pid = self()
    Process.put(:conveyor_run_view_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)
    on_exit(fn -> Process.delete(:conveyor_run_view_exit_fun) end)
    :ok
  end

  defp run(args), do: capture_io(fn -> Mix.Tasks.Conveyor.RunView.run(args) end)

  test "(1) human output tells the per-slice story of a completed run" do
    %{run_id: run_id, slices: slices} =
      FactoryFixtures.create_run_with_ledger!(
        terminal: :finished,
        slices: [%{status: "passed"}, %{status: "passed"}, %{status: "passed"}]
      )

    out = run([run_id])

    assert out =~ "[complete]"
    assert out =~ "3 slice(s)"
    for slice <- slices, do: assert(out =~ slice.stable_key)
    assert out =~ "passed"

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
  end

  test "(2) --json emits the conveyor.run_view@1 envelope" do
    %{run_id: run_id, slices: slices} =
      FactoryFixtures.create_run_with_ledger!(
        terminal: :finished,
        slices: [%{status: "passed"}, %{status: "passed"}]
      )

    decoded = run([run_id, "--json"]) |> Jason.decode!()

    assert decoded["schema_version"] == "conveyor.run_view@1"
    assert decoded["run_id"] == run_id
    assert decoded["status"] == "complete"
    assert decoded["slice_count"] == 2
    assert Enum.map(decoded["slices"], & &1["slice_id"]) == Enum.map(slices, & &1.stable_key)

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
  end

  test "(3) a stopped run names the stop point and the failing gate stage; exit success" do
    %{run_id: run_id, slices: [_s1, _s2, s3]} =
      FactoryFixtures.create_run_with_ledger!(
        terminal: :none,
        slices: [
          %{status: "passed"},
          %{
            status: "parked",
            outcome: :abstained,
            gate: %{
              passed: false,
              stages: [%{"key" => "tests", "status" => "failed"}],
              trust_score: %{"band" => "abstain", "score" => 0.42}
            }
          },
          # No :status key -> no slice_outcome event -> the in-flight slice (stop point).
          %{}
        ]
      )

    out = run([run_id])

    assert out =~ "[interrupted]"
    assert out =~ "stopped at #{s3.stable_key}"
    assert out =~ "gate:tests=failed"
    assert out =~ "verdict:abstain"

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
  end

  test "(m4b2.4) the per-slice review decision + finding count surface in human and JSON" do
    %{run_id: run_id} =
      FactoryFixtures.create_run_with_ledger!(
        terminal: :finished,
        slices: [
          %{
            status: "passed",
            review: %{decision: :rejected, findings: [FactoryFixtures.finding()]}
          }
        ]
      )

    assert run([run_id]) =~ "review:rejected(1)"

    [slice] = run([run_id, "--json"]) |> Jason.decode!() |> Map.fetch!("slices")
    assert slice["review"] == %{"decision" => "rejected", "finding_count" => 1}
  end

  test "(4) unmeasured spend renders as unknown, not 0" do
    %{run_id: run_id} =
      FactoryFixtures.create_run_with_ledger!(
        terminal: :finished,
        slices: [%{status: "passed", session: %{tokens: nil, cost_estimate: nil}}]
      )

    out = run([run_id])

    assert out =~ "spend:unknown"
    refute out =~ "spend:0tok"
  end

  test "(5a) a nonexistent run id prints an unknown story and still exits success" do
    out = run([Ecto.UUID.generate()])

    assert out =~ "[unknown]"
    assert out =~ "0 slice(s)"

    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
  end

  test "(5b) a missing run id raises usage" do
    assert_raise Mix.Error, ~r/usage: mix conveyor\.run_view/, fn ->
      Mix.Tasks.Conveyor.RunView.run([])
    end
  end

  test "(5c) an unknown flag raises usage" do
    assert_raise Mix.Error, ~r/usage/, fn ->
      Mix.Tasks.Conveyor.RunView.run(["some-run", "--bogus"])
    end
  end
end
