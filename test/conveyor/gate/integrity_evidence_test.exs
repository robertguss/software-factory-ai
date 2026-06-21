defmodule Conveyor.Gate.IntegrityEvidenceTest do
  @moduledoc "ADR-23 — IntegritySentinel verdict producer + the safe-rollout property."
  use ExUnit.Case, async: true

  alias Conveyor.Gate.IntegrityEvidence
  alias Conveyor.Gate.TrustEvidence

  test "no observations -> not_assessed (the safety property)" do
    assert IntegrityEvidence.verdict(%{}) == "not_assessed"
  end

  test "not_assessed is non-blocking once it reaches TrustEvidence" do
    verdict = IntegrityEvidence.verdict(%{})
    evidence = TrustEvidence.assemble(%{integrity: verdict})
    # not_assessed maps to a non-blocking "trustworthy" integrity signal.
    assert evidence.integrity_verdict == "trustworthy"
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

  test "is deterministic (verdict does not depend on the timestamp)" do
    obs = %{"source_mutation" => %{mutated_production_paths: ["a.ex"]}}
    a = IntegrityEvidence.verdict(obs, required_probes: ["source_mutation"], evaluated_at: "x")
    b = IntegrityEvidence.verdict(obs, required_probes: ["source_mutation"], evaluated_at: "y")
    assert a == b
  end
end
