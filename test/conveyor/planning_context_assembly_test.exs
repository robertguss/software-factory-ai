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

  test "records deterministic authority-first manifest and sheds lowest-priority advisory content" do
    manifest =
      ContextAssemblyManifest.assemble(
        [
          %{
            ref: "advisory://nice-to-have",
            priority: :advisory,
            estimated_tokens: 60,
            content_kind: :advisory_note
          },
          %{
            ref: "authority://contract-lock",
            priority: :critical,
            estimated_tokens: 40,
            content_kind: :contract_lock
          },
          %{
            ref: "authority://policy",
            priority: :critical,
            estimated_tokens: 40,
            content_kind: :policy
          },
          %{
            ref: "supporting://trace",
            priority: :supporting,
            estimated_tokens: 20,
            content_kind: :trace
          }
        ],
        token_budget: 100,
        tokenizer: %{adapter: "gpt-test", version: "tokenizer@1"}
      )

    assert manifest.status == :ready
    assert manifest.provider_call_allowed? == true
    assert manifest.tokenizer == %{adapter: "gpt-test", version: "tokenizer@1"}

    assert manifest.ordered_refs == [
             "authority://contract-lock",
             "authority://policy",
             "supporting://trace"
           ]

    assert manifest.shed_reasons == [
             %{
               ref: "advisory://nice-to-have",
               reason: :budget_exceeded,
               priority: :advisory,
               content_kind: :advisory_note
             }
           ]
  end

  test "uses a deterministic fallback tokenizer when no adapter tokenizer is available" do
    manifest =
      ContextAssemblyManifest.assemble(
        [
          %{
            ref: "authority://plan-revision",
            priority: :critical,
            estimated_tokens: 10,
            content_kind: :plan_revision
          }
        ],
        token_budget: 100,
        estimator_version: "fallback-estimator@1"
      )

    assert manifest.tokenizer == %{adapter: "fallback", version: "fallback-estimator@1"}
  end
end
