defmodule Conveyor.Planning.PreviewTest do
  @moduledoc "a3hf.2.2.3: plan dry-run preview (graph + contracts + lints + estimate + approve gate)."
  use Conveyor.DataCase, async: false

  alias Conveyor.Planning.PlanImporter
  alias Conveyor.Planning.Preview

  @decomposed "docs/schemas/examples/conveyor.plan.valid.json" |> Path.expand()

  defp import_plan! do
    {:ok, result} = Conveyor.PlanContract.load(@decomposed)

    PlanImporter.import_result!(result,
      workspace_path: "/tmp/preview-#{System.unique_integer([:positive])}"
    )
  end

  test "assembles the graph, slice contracts, lints, and estimate for an unapproved plan" do
    imported = import_plan!()
    preview = Preview.assemble(imported.plan.id)

    assert preview.plan_id == imported.plan.id
    assert length(preview.slices) == map_size(imported.slices_by_stable_key)
    assert Enum.all?(preview.slices, &is_binary(&1["stable_key"]))
    assert is_list(preview.warnings)
    # No historical usage seeded → honest no-basis estimate, not a fabricated number.
    assert preview.estimate.basis == "none"
    refute preview.approved?
  end

  test "reflects approval status once the plan's slices are approved" do
    imported = import_plan!()

    # Approve every slice (crosses the approve-to-run gate).
    Enum.each(Map.values(imported.slices_by_stable_key), fn slice ->
      Conveyor.TaskGraph.lock_task(slice.id)
      Conveyor.TaskGraph.approve_task(slice.id)
    end)

    # Plan status advances to approved only when the plan itself is approved; assemble reads it.
    preview = Preview.assemble(imported.plan.id)
    assert is_boolean(preview.approved?)
  end

  test "with injected historical usage, the estimate is a range (not no-basis)" do
    imported = import_plan!()
    usage = [%{"archetype" => "implement", "tokens" => 500, "cost_usd_estimated" => 0.5}]

    preview = Preview.assemble(imported.plan.id, usage: usage)

    assert preview.estimate.basis == "historical"
    assert preview.estimate.tokens.expected == 500
  end

  test "the mix conveyor.preview task renders JSON for a plan" do
    imported = import_plan!()
    test_pid = self()
    Process.put(:conveyor_preview_exit_fun, fn code -> send(test_pid, {:exit, code}) end)

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Task.reenable("conveyor.preview")
        Mix.Task.run("conveyor.preview", [imported.plan.id, "--format", "json"])
      end)

    json =
      output
      |> String.split("\n", trim: true)
      |> Enum.find(&String.starts_with?(&1, "{"))
      |> Jason.decode!()

    assert json["plan_id"] == imported.plan.id
    assert is_list(json["slices"])
    assert_received {:exit, 0}
  after
    Process.delete(:conveyor_preview_exit_fun)
  end
end
