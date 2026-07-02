defmodule Conveyor.Planning.SerialDriverEmergencyStopTest do
  @moduledoc """
  a3hf.2.1.4: an engaged emergency stop halts the run at each slice's safe point — before any
  assemble/spend. The full trip-on-breach e2e is the Tests-sibling a3hf.2.1.5.
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.EmergencyStop.Store
  alias Conveyor.Factory
  alias Conveyor.Factory.Project
  alias Conveyor.Planning.SerialDriver

  test "halts every slice at its safe point when the project's emergency stop is engaged" do
    project = project!()

    Store.trip!(:project, project.id,
      project_id: project.id,
      actor: "budget-guard",
      reason: "budget_envelope_breach",
      trace_id: "t"
    )

    result =
      SerialDriver.run!(
        %{work_graph: work_graph(), selected_slice_ids: ["S1", "S2"]},
        project_id: project.id,
        rework: false,
        # the halt must short-circuit BEFORE run-spec assembly / any spend
        assemble_run_spec: fn _key, _graph ->
          raise "assemble must not run while the emergency stop is engaged"
        end
      )

    assert result.status == :partial
    assert length(result.events) == 2
    assert Enum.all?(result.events, &(&1["gate_result"] == "emergency_stopped"))
    assert Enum.all?(result.events, &(&1["status"] == "parked"))
  end

  test "does not halt when the stop is engaged for a DIFFERENT project (project-scoped)" do
    other = project!()

    Store.trip!(:project, other.id,
      project_id: other.id,
      actor: "op",
      reason: "budget_envelope_breach",
      trace_id: "t"
    )

    # This run's project has no engaged stop, so it does NOT halt — assembly is reached (the seam
    # raises a marker proving the safe-point did not short-circuit).
    assert_raise RuntimeError, "reached-assembly", fn ->
      SerialDriver.run!(
        %{work_graph: work_graph(), selected_slice_ids: ["S1"]},
        project_id: project!().id,
        rework: false,
        assemble_run_spec: fn _key, _graph -> raise "reached-assembly" end
      )
    end
  end

  defp project! do
    Ash.create!(
      Project,
      %{
        name: "EStop drive #{System.unique_integer([:positive])}",
        local_path: "/tmp/estop-drive-#{System.unique_integer([:positive])}",
        default_branch: "main"
      },
      domain: Factory
    )
  end

  defp work_graph do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [
        %{"stable_key" => "S1", "title" => "One"},
        %{"stable_key" => "S2", "title" => "Two"}
      ],
      "work_dependencies" => []
    }
  end
end
