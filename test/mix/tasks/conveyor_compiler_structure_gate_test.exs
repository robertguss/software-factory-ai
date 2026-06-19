defmodule Mix.Tasks.ConveyorCompilerStructureGateTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Conveyor.Planning.StaticDecisionPackage

  test "passes complete static packages without structural blockers or authority effects" do
    input_path = write_input!(complete_package(), [])
    put_exit_fun()

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.compiler_structure_gate")
        Mix.Task.run("conveyor.compiler_structure_gate", ["--input", input_path])
      end)

    assert output =~ "compiler_structure_gate: passed"
    assert output =~ "NON-authorizing"
    assert output =~ "Authority: none"
    assert_received {:exit_code, 0}
  after
    Process.delete(:conveyor_compiler_structure_gate_exit_fun)
  end

  test "blocks when static structural findings include hard blockers" do
    input_path =
      write_input!(complete_package(), [
        %{
          rule_key: "traceability_gap",
          severity: :blocking,
          subject_key: "SLC-A"
        }
      ])

    put_exit_fun()

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.compiler_structure_gate")
        Mix.Task.run("conveyor.compiler_structure_gate", ["--input", input_path])
      end)

    assert output =~ "compiler_structure_gate: blocked"
    assert output =~ "traceability_gap"
    assert_received {:exit_code, 2}
  after
    Process.delete(:conveyor_compiler_structure_gate_exit_fun)
  end

  test "blocks clean findings if the package creates execution authority" do
    package = Map.put(complete_package(), :creates_ready_slice?, true)
    input_path = write_input!(package, [])
    put_exit_fun()

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.compiler_structure_gate")
        Mix.Task.run("conveyor.compiler_structure_gate", ["--input", input_path])
      end)

    assert output =~ "compiler_structure_gate: blocked"
    assert output =~ "compiler_gate_authority_created"
    assert output =~ "ready_slice"
    assert_received {:exit_code, 2}
  after
    Process.delete(:conveyor_compiler_structure_gate_exit_fun)
  end

  defp put_exit_fun do
    test_pid = self()

    Process.put(:conveyor_compiler_structure_gate_exit_fun, fn code ->
      send(test_pid, {:exit_code, code})
    end)
  end

  defp complete_package do
    StaticDecisionPackage.build(%{
      normalized_plan: %{plan_key: "plan-1"},
      claims: [%{subject_pointer: "/requirements/0"}],
      constraints: [%{key: "CON-001"}],
      candidate_comparison: [%{candidate_key: "primary"}],
      work_graph: %{schema_version: "conveyor.work_graph@2"},
      interfaces: [%{interface_key: "db.tasks.completed"}],
      decisions: [%{human_decision_ref: "DEC-001"}],
      derivation_graph: [%{"consumer_artifact_id" => "work_graph:1"}],
      structural_dry_run: %{waves: [["SLC-A"]]},
      scope_delta: :scope_preserved,
      oracle_warnings: []
    })
  end

  defp write_input!(package, findings) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-compiler-structure-gate-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(%{package: package, findings: findings}))
    path
  end
end
