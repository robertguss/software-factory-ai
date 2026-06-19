defmodule Conveyor.PlanningWorkbenchActionsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.WorkbenchActions

  @schema_path "docs/schemas/conveyor.change_set@1.json"

  test "compiles structured workbench action to a canonical ChangeSet" do
    result =
      WorkbenchActions.compile(%{
        action_type: "select_candidate",
        subject: resource_ref("plan_revision", "plan-revision-1"),
        base_revision_digest: digest_ref("base-revision"),
        base_authority_root_digest: digest_ref("base-authority"),
        impact_preview_ref: resource_ref("impact_preview", "impact-preview-1"),
        value: "candidate-2",
        reason: "operator_selected_lower_risk_candidate",
        materiality_labels: ["material"]
      })

    assert result["status"] == "draft"
    assert result["authority_effect"] == "none"
    assert result["mutation_mode"] == "append_only_change_set"

    change_set = result["change_set"]
    assert change_set["schema_version"] == "conveyor.change_set@1"
    assert change_set["status"] == "draft"

    assert change_set["operations"] == [
             %{
               "op" => "replace",
               "path" => "/candidate_selection_id",
               "value" => "candidate-2",
               "reason" => "operator_selected_lower_risk_candidate"
             }
           ]

    assert Enum.map(change_set["preconditions"], & &1["kind"]) == [
             "base_revision_digest",
             "base_authority_root_digest"
           ]

    assert change_set["materiality_labels"] == ["material"]
    assert_schema_valid!(change_set)
  end

  test "catalog includes every structured operator action" do
    catalog = WorkbenchActions.catalog()

    for action <- [
          "approve_epic",
          "reject_epic",
          "select_candidate",
          "accept_claim",
          "reject_claim",
          "accept_assumption",
          "reject_assumption",
          "accept_waiver",
          "reject_waiver",
          "split",
          "merge",
          "reclassify_edge",
          "change_constraint",
          "change_interface",
          "change_compatibility",
          "mark_human_verification",
          "strengthen_contract",
          "show_cheapest_wrong_impl",
          "rerun_affected",
          "preview_invalidation",
          "open_amendment",
          "save_draft",
          "stop",
          "resume"
        ] do
      assert action in catalog
    end
  end

  test "missing base preconditions blocks ChangeSet compilation" do
    result =
      WorkbenchActions.compile(%{
        action_type: "approve_epic",
        subject: resource_ref("epic", "checkout"),
        impact_preview_ref: resource_ref("impact_preview", "impact-preview-1"),
        reason: "approve exact roots"
      })

    assert result["status"] == "blocked"
    assert result["change_set"] == nil
    assert "base_revision_digest_missing" in result["blocking_reasons"]
  end

  defp assert_schema_valid!(resource) do
    schema =
      @schema_path
      |> File.read!()
      |> Jason.decode!()
      |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(resource, schema)
  end

  defp resource_ref(kind, id) do
    %{"schema_version" => "conveyor.resource_ref@1", "kind" => kind, "id_or_key" => id}
  end

  defp digest_ref(seed) do
    %{
      "schema_version" => "conveyor.digest_ref@1",
      "algorithm" => "sha256",
      "value" => :crypto.hash(:sha256, seed) |> Base.encode16(case: :lower)
    }
  end
end
