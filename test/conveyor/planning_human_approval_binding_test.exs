defmodule Conveyor.PlanningHumanApprovalBindingTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.HumanApprovalBinding

  @approval_set_schema "docs/schemas/conveyor.approval_set@1.json"

  test "binds human approval to exact shared selected epic and review roots" do
    result =
      HumanApprovalBinding.bind(%{
        approval_id: "human_approval:checkout-1",
        actor: "owner",
        shared_authority_root: digest_ref("shared"),
        epic_authority_roots: %{
          "checkout" => digest_ref("checkout"),
          "admin" => digest_ref("admin")
        },
        selected_epics: ["checkout"],
        review_root: digest_ref("review"),
        approval_policy: %{
          policy_key: "local-threshold-one",
          threshold: 1,
          policy_digest: digest_ref("policy")
        },
        accepted_warnings: ["impact_confidence_low"],
        accepted_assumptions: ["operator reviewed checkout only"],
        accepted_waivers: ["waiver:manual-review"],
        autonomy_ceiling: "local_dev",
        signature_status: "unsigned"
      })

    assert result["status"] == "approved"
    approval = result["human_approval"]

    assert approval["approval_id"] == "human_approval:checkout-1"
    assert approval["shared_authority_root_digest"] == digest_ref("shared")

    assert approval["selected_epic_authority_roots"] == [
             %{"epic_key" => "checkout", "digest" => digest_ref("checkout")}
           ]

    assert approval["review_root_digest"] == digest_ref("review")
    assert approval["accepted_warnings"] == ["impact_confidence_low"]
    assert approval["accepted_assumptions"] == ["operator reviewed checkout only"]
    assert approval["accepted_waivers"] == ["waiver:manual-review"]
    assert approval["autonomy_ceiling"] == "local_dev"
    assert approval["signature_status"] == "unsigned"

    approval_set = result["approval_set"]
    assert approval_set["threshold_satisfied"] == true

    assert Enum.map(approval_set["subject_authority_roots"], & &1["root_kind"]) == [
             "shared_authority",
             "epic_authority"
           ]

    assert_schema_valid!(approval_set, @approval_set_schema)
  end

  test "blocks when an exact review root is missing" do
    result =
      HumanApprovalBinding.bind(%{
        approval_id: "human_approval:checkout-1",
        shared_authority_root: digest_ref("shared"),
        epic_authority_roots: %{"checkout" => digest_ref("checkout")},
        selected_epics: ["checkout"],
        approval_policy: %{threshold: 1, policy_digest: digest_ref("policy")}
      })

    assert result["status"] == "blocked"
    assert "review_root_missing" in result["blocking_reasons"]
    assert result["human_approval"] == nil
  end

  defp assert_schema_valid!(resource, schema_path) do
    schema =
      schema_path
      |> File.read!()
      |> Jason.decode!()
      |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(resource, schema)
  end

  defp digest_ref(seed) do
    %{
      "schema_version" => "conveyor.digest_ref@1",
      "algorithm" => "sha256",
      "value" => :crypto.hash(:sha256, seed) |> Base.encode16(case: :lower)
    }
  end
end
