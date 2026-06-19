defmodule Conveyor.PlanningContextAssemblyTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.ContextAssemblyManifest

  test "fails before provider call when critical content is shed and records noncritical shed reasons" do
    manifest =
      ContextAssemblyManifest.assemble(
        [
          %{ref: "source://critical-plan", priority: :critical, estimated_tokens: 80},
          %{ref: "source://supporting-note", priority: :supporting, estimated_tokens: 60}
        ],
        token_budget: 100,
        estimator_version: "estimator@1"
      )

    assert manifest.status == :ready
    assert manifest.provider_call_allowed? == true

    assert manifest.shed_reasons == [
             %{ref: "source://supporting-note", reason: :budget_exceeded, priority: :supporting}
           ]

    failed =
      ContextAssemblyManifest.assemble(
        [
          %{ref: "source://critical-plan", priority: :critical, estimated_tokens: 120}
        ],
        token_budget: 100,
        estimator_version: "estimator@1"
      )

    assert failed.status == :failed_pre_provider
    assert failed.provider_call_allowed? == false

    assert failed.shed_reasons == [
             %{ref: "source://critical-plan", reason: :critical_content_shed, priority: :critical}
           ]
  end
end
