defmodule Conveyor.Gate.IntegrityEvidenceTest do
  @moduledoc "ADR-23 — IntegritySentinel verdict producer + the safe-rollout property."
  use ExUnit.Case, async: true

  alias Conveyor.Gate.IntegrityEvidence
  alias Conveyor.Gate.TrustEvidence

  test "no observations -> not_assessed (the safety property)" do
    assert IntegrityEvidence.verdict(%{}) == "not_assessed"
  end

  test "an unassessed integrity verdict fails closed at TrustEvidence (M4 un-laundered)" do
    verdict = IntegrityEvidence.verdict(%{})
    assert verdict == "not_assessed"

    evidence = TrustEvidence.assemble(%{integrity: verdict})
    # M4: not_assessed is no longer laundered to "trustworthy" — it passes through, and the
    # trust score then abstains (parks the slice for human + AI investigation).
    assert evidence.integrity_verdict == "not_assessed"
  end

  test "a real probe failure -> untrustworthy (would abstain)" do
    observations = %{"source_mutation" => %{mutated_production_paths: ["lib/secret_backdoor.ex"]}}

    verdict = IntegrityEvidence.verdict(observations, required_probes: ["source_mutation"])
    assert verdict == "untrustworthy"

    evidence = TrustEvidence.assemble(%{integrity: verdict})
    assert evidence.integrity_verdict == "untrustworthy"
  end

  test "all assessed probes passing -> trustworthy" do
    observations = %{
      "base_calibration" => %{
        expected_role: "implementer",
        observed_role: "implementer",
        base_behavior: "red_on_stub"
      }
    }

    assert IntegrityEvidence.verdict(observations, required_probes: ["base_calibration"]) ==
             "trustworthy"
  end

  test "a full hermetic observation -> trustworthy" do
    obs = %{
      "hermeticity" => %{
        network: :blocked,
        clock: :controlled,
        rng: :seeded,
        ordering: :stable,
        locale: :pinned,
        shared_state: :isolated
      }
    }

    assert IntegrityEvidence.verdict(obs, required_probes: ["hermeticity"]) == "trustworthy"
  end

  test "a non-hermetic observation (network unrestricted) -> untrustworthy -> abstain" do
    obs = %{
      "hermeticity" => %{
        network: :unrestricted,
        clock: :controlled,
        rng: :seeded,
        ordering: :stable,
        locale: :pinned,
        shared_state: :isolated
      }
    }

    verdict = IntegrityEvidence.verdict(obs, required_probes: ["hermeticity"])
    assert verdict == "untrustworthy"
    assert TrustEvidence.assemble(%{integrity: verdict}).integrity_verdict == "untrustworthy"
  end

  test "is deterministic (verdict does not depend on the timestamp)" do
    obs = %{"source_mutation" => %{mutated_production_paths: ["a.ex"]}}
    a = IntegrityEvidence.verdict(obs, required_probes: ["source_mutation"], evaluated_at: "x")
    b = IntegrityEvidence.verdict(obs, required_probes: ["source_mutation"], evaluated_at: "y")
    assert a == b
  end
end
