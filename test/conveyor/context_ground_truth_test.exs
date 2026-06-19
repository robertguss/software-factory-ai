defmodule Conveyor.ContextGroundTruthTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContextGroundTruth

  test "labelled context truth reports precision recall and forbidden refs" do
    report =
      ContextGroundTruth.evaluate(%{
        case_id: "CTX-001",
        necessary_source_refs: ["lib/checkout.ex", "lib/payments.ex"],
        useful_source_refs: ["test/checkout_test.exs"],
        forbidden_or_irrelevant_source_refs: ["secrets.env"],
        selected_source_refs: ["lib/checkout.ex", "test/checkout_test.exs", "secrets.env"],
        patch_source_refs: ["lib/checkout.ex"],
        opened_source_refs: ["lib/checkout.ex", "docs/unused.md"],
        post_failure_missing_context: false,
        budget_exhausted: false,
        critical_context_shed: true
      })

    assert report["schema_version"] == "conveyor.context_ground_truth_report@1"
    assert report["case_id"] == "CTX-001"
    assert report["labelled"] == true
    assert report["selected_context_precision"] == 2 / 3
    assert report["necessary_context_recall"] == 0.5
    assert report["forbidden_selected_refs"] == ["secrets.env"]

    assert report["proxy_metrics"] == %{
             "selected_context_used_by_patch" => true,
             "files_opened_but_unused" => ["docs/unused.md"],
             "post_failure_missing_context" => false,
             "budget_exhausted" => false,
             "critical_context_shed" => true
           }
  end

  test "unlabelled work emits only named proxy metrics" do
    report =
      ContextGroundTruth.evaluate(%{
        case_id: "real-work-001",
        selected_source_refs: ["lib/checkout.ex"],
        patch_source_refs: [],
        opened_source_refs: ["lib/checkout.ex"],
        post_failure_missing_context: true,
        budget_exhausted: true,
        critical_context_shed: false
      })

    assert report["labelled"] == false
    assert report["selected_context_precision"] == nil
    assert report["necessary_context_recall"] == nil

    assert Map.keys(report["proxy_metrics"]) == [
             "budget_exhausted",
             "critical_context_shed",
             "files_opened_but_unused",
             "post_failure_missing_context",
             "selected_context_used_by_patch"
           ]
  end
end
