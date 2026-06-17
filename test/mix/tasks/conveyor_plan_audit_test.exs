defmodule Mix.Tasks.ConveyorPlanAuditTest do
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  @valid_example Path.expand("../../../docs/schemas/examples/conveyor.plan.valid.json", __DIR__)

  test "prints readiness report and exits zero for handoff-ready plan" do
    path = copy_valid_contract!()
    put_exit_fun()

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.plan_audit")
        Mix.Task.run("conveyor.plan_audit", [path])
      end)

    assert output =~ "Clarity: 100%"
    assert output =~ "Acceptance coverage: 100%"
    assert output =~ "Requirement traceability: 100%"
    assert output =~ "Decision: handoff_ready"
    assert_received {:exit_code, 0}
  after
    Process.delete(:conveyor_plan_audit_exit_fun)
  end

  test "prints blocking findings and exits two for blocked plan" do
    path = blocked_contract!()
    put_exit_fun()

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.plan_audit")
        Mix.Task.run("conveyor.plan_audit", [path])
      end)

    assert output =~ "Decision: blocked"
    assert output =~ "Blocking findings:"
    assert output =~ "Requirement REQ-002 has no acceptance criteria."
    assert output =~ "NextAction:"
    assert_received {:exit_code, 2}
  after
    Process.delete(:conveyor_plan_audit_exit_fun)
  end

  defp put_exit_fun do
    test_pid = self()
    Process.put(:conveyor_plan_audit_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)
  end

  defp copy_valid_contract! do
    path = Path.join(temp_dir!(), "conveyor.plan.json")
    File.cp!(@valid_example, path)
    path
  end

  defp blocked_contract! do
    path = Path.join(temp_dir!(), "conveyor.plan.json")

    contract =
      @valid_example
      |> File.read!()
      |> Jason.decode!()
      |> update_in(["requirements"], fn requirements ->
        requirements ++
          [
            %{
              "key" => "REQ-002",
              "text" => "Incomplete tasks remain visible in list responses.",
              "risk" => "medium",
              "source_ref" => "plan.md#requirement-req-002",
              "status" => "open"
            }
          ]
      end)

    File.write!(path, Jason.encode!(contract))
    path
  end

  defp temp_dir! do
    path =
      Path.join(System.tmp_dir!(), "conveyor-plan-audit-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    path
  end
end
