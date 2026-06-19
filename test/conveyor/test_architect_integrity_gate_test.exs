defmodule Conveyor.TestArchitectIntegrityGateTest do
  use ExUnit.Case, async: true

  alias Conveyor.TestArchitect.IntegrityGate
  alias Conveyor.Verification

  @obligation_id "verification_obligation:sha256:abc"
  @evaluated_at "2026-06-19T00:01:00Z"

  test "passes only when the Sentinel is trustworthy and each obligation is satisfied" do
    requirement = requirement([:specification_present, :candidate_result, :hermeticity])

    evidence = [
      evidence("spec", :specification),
      evidence("candidate", :candidate_result),
      evidence("hermetic", :hermeticity)
    ]

    result =
      IntegrityGate.evaluate!(
        integrity_spec(),
        clean_observations(),
        [%{requirement: requirement, evidence: evidence}],
        policy_decision_id: "policy-decision:allow",
        evaluated_at: @evaluated_at
      )

    assert result.status == :passed
    assert result.integrity_run["verdict"] == "trustworthy"
    assert [%{"result" => "satisfied"}] = result.obligation_satisfactions
    assert result.hard_findings == []
  end

  test "blocks untrustworthy Sentinel findings before authority can pass" do
    observations =
      clean_observations()
      |> put_in([:source_mutation, :mutated_production_paths], ["lib/conveyor/core.ex"])

    result =
      IntegrityGate.evaluate!(
        integrity_spec(),
        observations,
        [
          %{
            requirement: requirement([:candidate_result]),
            evidence: [evidence("candidate", :candidate_result)]
          }
        ],
        policy_decision_id: "policy-decision:block",
        evaluated_at: @evaluated_at
      )

    assert result.status == :blocked
    assert result.integrity_run["verdict"] == "untrustworthy"

    assert Enum.any?(
             result.hard_findings,
             &(&1["rule_key"] == "test_integrity.production_source_mutated")
           )
  end

  test "advisory-until-calibrated mutation and dynamic coverage signals never hard-block" do
    result =
      IntegrityGate.evaluate!(
        integrity_spec(),
        clean_observations(),
        [
          %{
            requirement: requirement([:candidate_result]),
            evidence: [evidence("candidate", :candidate_result)]
          }
        ],
        policy_decision_id: "policy-decision:allow",
        evaluated_at: @evaluated_at,
        advisory_checks: %{
          universal_mutation_without_reference: "not_calibrated",
          dynamic_coverage: "not_calibrated"
        }
      )

    assert result.status == :passed
    assert result.hard_findings == []

    assert result.advisory_findings == [
             %{
               "rule_key" => "test_integrity.advisory.dynamic_coverage",
               "severity" => "advisory",
               "status" => "not_calibrated"
             },
             %{
               "rule_key" => "test_integrity.advisory.universal_mutation_without_reference",
               "severity" => "advisory",
               "status" => "not_calibrated"
             }
           ]
  end

  defp integrity_spec do
    %{
      test_pack_id: "test-pack:unit",
      integrity_spec_digest: "sha256:integrity-spec",
      sample_no: 1,
      slice_id: "slice-1",
      run_spec_id: "run-spec-1"
    }
  end

  defp clean_observations do
    %{
      base_calibration: %{
        expected_role: "test_architect",
        observed_role: "test_architect",
        base_behavior: "red_on_stub"
      },
      falsifier_survival: %{required: true, survived: true},
      hermeticity: %{
        network: :blocked,
        clock: :controlled,
        rng: :seeded,
        ordering: :stable,
        locale: :pinned,
        shared_state: :isolated
      },
      repeatability: %{
        sample_count: 3,
        result_digests: ["sha256:same", "sha256:same", "sha256:same"],
        failure_signatures: []
      },
      mapping: %{
        obligation_refs: [
          %{
            obligation_id: @obligation_id,
            acceptance_ref: "AC-001",
            interface_oracle_ref: "interface-oracle:abc"
          }
        ]
      },
      mount_boundary: %{write_violations: []},
      required_artifacts: %{required: ["result.json"], present: ["result.json"]},
      source_mutation: %{mutated_production_paths: []},
      hidden_dependency: %{secret_refs: [], network_hosts: []},
      falsifier_preservation: %{dropped_falsifier_refs: [], superseded_falsifier_refs: []}
    }
  end

  defp requirement(dimensions) do
    Verification.new_evidence_requirement!(%{
      verification_obligation_id: @obligation_id,
      required_dimensions: dimensions,
      created_at: "2026-06-19T00:00:00Z"
    })
  end

  defp evidence(label, kind) do
    Verification.new_evidence!(%{
      verification_obligation_id: @obligation_id,
      producer_kind: "test_pack",
      producer_ref: "test-pack:#{label}",
      evidence_kind: kind,
      validity: :valid,
      environment_fingerprint_digest: "sha256:env",
      result_ref: "artifact:#{label}",
      evidence_digest: "sha256:#{label}",
      created_at: "2026-06-19T00:00:00Z"
    })
  end
end
