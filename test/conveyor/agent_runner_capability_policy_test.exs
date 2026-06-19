defmodule Conveyor.AgentRunnerCapabilityPolicyTest do
  use ExUnit.Case, async: true

  alias Conveyor.AgentRunner.CapabilityPolicy

  @derived_at "2026-06-19T00:00:00Z"

  test "derives an EffectiveCapabilitySet by intersecting declaration, probes, observations, health, and policy" do
    effective =
      CapabilityPolicy.derive!("primary-live", claims(),
        health: %{state: :closed},
        policy: %{allowed_capabilities: ["patch_capture", "pre_exec_command_policy"]},
        derived_at: @derived_at
      )

    assert effective["schema_version"] == "conveyor.effective_capability_set@1"
    assert effective["adapter"] == "primary-live"
    assert effective["declared_claim_refs"] == ["claim://declared/patch", "claim://declared/pre"]
    assert effective["probe_claim_refs"] == ["claim://probed/patch", "claim://probed/pre"]
    assert effective["observed_claim_refs"] == ["claim://observed/patch", "claim://observed/pre"]

    assert effective["effective_capabilities"] == %{
             "patch_capture" => "supported",
             "pre_exec_command_policy" => true
           }

    assert "cost_reporting:missing_observed_claim" in effective["excluded_or_degraded_claims"]
    assert effective["capability_set_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
  end

  test "open adapter health excludes all capabilities without mutating historical claims" do
    effective =
      CapabilityPolicy.derive!("primary-live", claims(),
        health: %{state: :open, reason_codes: [:capability_drift]},
        policy: %{allowed_capabilities: ["patch_capture", "pre_exec_command_policy"]},
        derived_at: @derived_at
      )

    assert effective["effective_capabilities"] == %{}
    assert "adapter_health:open" in effective["excluded_or_degraded_claims"]
    assert effective["declared_claim_refs"] == ["claim://declared/patch", "claim://declared/pre"]
  end

  test "autonomy is capped by effective capabilities, policy, and admission permit, not adapter name" do
    claims =
      claims() ++
        [
          claim("structured_output", true, "declared", "claim://declared/structured"),
          claim("structured_output", true, "probed", "claim://probed/structured"),
          claim("structured_output", true, "observed", "claim://observed/structured"),
          claim("diff_capture", "git_diff", "declared", "claim://declared/diff"),
          claim("diff_capture", "git_diff", "probed", "claim://probed/diff"),
          claim("diff_capture", "git_diff", "observed", "claim://observed/diff"),
          claim("streaming_events", true, "declared", "claim://declared/events"),
          claim("streaming_events", true, "probed", "claim://probed/events"),
          claim("streaming_events", true, "observed", "claim://observed/events")
        ]

    first = CapabilityPolicy.derive!("primary-live", claims, derived_at: @derived_at)
    second = CapabilityPolicy.derive!("mock-name", claims, derived_at: @derived_at)

    assert CapabilityPolicy.max_autonomy(first,
             policy: %{max_autonomy: "L2"},
             admission_permit: %{valid?: true, max_autonomy: "L2"}
           ) == "L2"

    assert CapabilityPolicy.max_autonomy(second,
             policy: %{max_autonomy: "L2"},
             admission_permit: %{valid?: true, max_autonomy: "L2"}
           ) == "L2"

    assert CapabilityPolicy.max_autonomy(first,
             policy: %{max_autonomy: "L2"},
             admission_permit: %{valid?: false, max_autonomy: "L2"}
           ) == "L0"
  end

  defp claims do
    [
      claim("patch_capture", "supported", "declared", "claim://declared/patch"),
      claim("patch_capture", "supported", "probed", "claim://probed/patch"),
      claim("patch_capture", "supported", "observed", "claim://observed/patch"),
      claim("pre_exec_command_policy", true, "declared", "claim://declared/pre"),
      claim("pre_exec_command_policy", true, "probed", "claim://probed/pre"),
      claim("pre_exec_command_policy", true, "observed", "claim://observed/pre"),
      claim("cost_reporting", "provider_reported", "declared", "claim://declared/cost"),
      claim("cost_reporting", "provider_reported", "probed", "claim://probed/cost")
    ]
  end

  defp claim(key, value, source, ref) do
    %{
      "schema_version" => "conveyor.capability_claim@1",
      "capability_key" => key,
      "version" => "1",
      "mode_or_value" => value,
      "limits" => %{},
      "source" => source,
      "evidence_ref" => ref,
      "known_degradations" => []
    }
  end
end
