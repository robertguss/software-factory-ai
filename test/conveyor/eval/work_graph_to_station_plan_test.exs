defmodule Conveyor.Eval.WorkGraphToStationPlanTest do
  use ExUnit.Case, async: true

  alias Conveyor.Eval.{CompilerProperties, WorkGraphToStationPlan}
  alias Conveyor.Planning.WorkGraphLowering

  @moduletag :eval

  defp single_slice_graph do
    {cand, spec} = CompilerProperties.candidate_fixture(1)
    {:ok, wg} = WorkGraphLowering.lower(cand, spec)
    wg
  end

  test "lowers a single-slice work_graph into an agent->verify station_plan bound to the run_spec" do
    {:ok, plan} = WorkGraphToStationPlan.lower(single_slice_graph(), "sha256:rs")

    assert plan["schema_version"] == "conveyor.station_plan@1"
    assert Enum.map(plan["stations"], & &1["key"]) == ["agent", "verify"]
    assert plan["slice_stable_key"] == "SLC-1"
    assert is_binary(plan["work_graph_digest"])

    for s <- plan["stations"] do
      assert s["input"]["run_spec_sha256"] == "sha256:rs"
      assert s["output"]["run_spec_sha256"] == "sha256:rs"
    end
  end

  test "lowering is pure and deterministic (identical output across calls)" do
    wg = single_slice_graph()
    {:ok, a} = WorkGraphToStationPlan.lower(wg, "sha256:rs")
    {:ok, b} = WorkGraphToStationPlan.lower(wg, "sha256:rs")
    assert a == b
  end

  test "rejects a multi-slice work_graph (tracer scope is one slice)" do
    {cand, spec} = CompilerProperties.candidate_fixture(2)
    {:ok, wg} = WorkGraphLowering.lower(cand, spec)

    assert {:error, %{reason: :multi_slice_unsupported}} =
             WorkGraphToStationPlan.lower(wg, "sha256:rs")
  end
end
