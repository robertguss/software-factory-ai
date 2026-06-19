defmodule Conveyor.ShadowControlsTest do
  use ExUnit.Case, async: true

  alias Conveyor.ShadowControls

  test "tutor output remains advisory and cannot satisfy work authority" do
    report =
      ShadowControls.tutor_advice(%{
        subject_ref: "slice:checkout",
        finding_refs: ["finding:test-gap"]
      })

    assert report["schema_version"] == "conveyor.tutor_shadow@1"
    assert report["advisory_only"] == true
    assert report["can_close_slice"] == false
    assert report["can_satisfy_obligation"] == false
    assert report["authority_effect"] == "none"
  end

  test "retry escalation consumes a tier only for implementation and validation failures" do
    profiles = ["small", "medium", "large"]

    assert ShadowControls.retry_escalation(%{
             failure_category: "implementation_failure",
             profiles: profiles,
             current_profile: "small"
           }) == %{
             "schema_version" => "conveyor.retry_escalation_shadow@1",
             "decision" => "new_attempt_with_next_profile",
             "next_profile" => "medium",
             "consumes_tier" => true
           }

    for category <- ["contract_fault", "policy_violation", "adapter_failure", "infra_failure"] do
      assert ShadowControls.retry_escalation(%{
               failure_category: category,
               profiles: profiles,
               current_profile: "small"
             }) == %{
               "schema_version" => "conveyor.retry_escalation_shadow@1",
               "decision" => "route_without_escalation",
               "next_profile" => nil,
               "consumes_tier" => false
             }
    end
  end
end
