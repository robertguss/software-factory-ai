defmodule Conveyor.PlanningSelectiveInvalidationTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.SelectiveInvalidation

  test "shared interface changes invalidate every affected consumer attempt" do
    result =
      SelectiveInvalidation.classify(%{
        changes: [
          %{
            change_kind: "shared_interface",
            interface_key: "payments-api",
            affected_consumers: ["slice:checkout", "slice:refunds"]
          }
        ]
      })

    assert result["outcomes"] == [
             outcome(
               "slice:checkout",
               "invalidate_downstream_attempt",
               "shared_interface_changed"
             ),
             outcome("slice:refunds", "invalidate_downstream_attempt", "shared_interface_changed")
           ]
  end

  test "review-only corrections preserve the existing contract lock" do
    result =
      SelectiveInvalidation.classify(%{
        changes: [
          %{
            change_kind: "review_only_correction",
            subject_ref: "contract_lock:checkout:r4"
          }
        ]
      })

    assert result["outcomes"] == [
             outcome("contract_lock:checkout:r4", "unchanged_reusable", "review_only_correction")
           ]

    assert result["preserved_locks"] == ["contract_lock:checkout:r4"]
  end

  test "waiver changes invalidate the obligation epic and grant scope" do
    result =
      SelectiveInvalidation.classify(%{
        changes: [
          %{
            change_kind: "waiver_change",
            waiver_ref: "waiver:pci-temporary",
            obligation_ref: "verification_obligation:pci",
            epic_ref: "epic:checkout",
            grant_id: "grant:qualified-contract-foundry"
          }
        ]
      })

    assert outcome("verification_obligation:pci", "invalidate_obligation", "waiver_changed") in result[
             "outcomes"
           ]

    assert outcome("epic:checkout", "requalify_scope", "waiver_changed") in result["outcomes"]

    assert outcome("grant:qualified-contract-foundry", "requalify_scope", "waiver_changed") in result[
             "outcomes"
           ]
  end

  defp outcome(subject_ref, action, reason) do
    %{"subject_ref" => subject_ref, "action" => action, "reason" => reason}
  end
end
