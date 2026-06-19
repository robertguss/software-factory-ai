defmodule Conveyor.TestIntegritySentinelTest do
  use ExUnit.Case, async: true

  alias Conveyor.Verification.IntegritySentinel

  @spec_attrs %{
    test_pack_id: "test-pack:unit",
    integrity_spec_digest: "sha256:integrity-spec",
    sample_no: 1,
    slice_id: "slice-1",
    run_spec_id: "run-spec-1"
  }

  test "clean deterministic observations produce a trustworthy TestIntegrityRun" do
    run =
      IntegritySentinel.run(@spec_attrs, clean_observations(),
        evaluated_at: "2026-06-19T00:00:00Z"
      )

    assert run["schema_version"] == "conveyor.test_integrity_run@1"
    assert run["test_pack_id"] == "test-pack:unit"
    assert run["verdict"] == "trustworthy"
    assert run["findings"] == []
    assert run["probe_results"]["hermeticity"]["status"] == "passed"
    assert run["probe_results"]["falsifier_preservation"]["status"] == "passed"
    assert run["integrity_run_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
  end

  test "non-hermetic controls and production-source mutation are untrustworthy" do
    observations =
      clean_observations()
      |> put_in([:hermeticity, :network], :leaked)
      |> put_in([:source_mutation, :mutated_production_paths], ["lib/conveyor/core.ex"])

    run = IntegritySentinel.run(@spec_attrs, observations, evaluated_at: "2026-06-19T00:00:00Z")

    assert run["verdict"] == "untrustworthy"
    assert run["probe_results"]["hermeticity"]["status"] == "failed"
    assert run["probe_results"]["source_mutation"]["status"] == "failed"
    assert Enum.any?(run["findings"], &(&1["rule_key"] == "test_integrity.non_hermetic_network"))

    assert Enum.any?(
             run["findings"],
             &(&1["rule_key"] == "test_integrity.production_source_mutated")
           )
  end

  test "unstable repeatability is suspect rather than trustworthy" do
    observations =
      put_in(clean_observations(), [:repeatability, :result_digests], [
        "sha256:first",
        "sha256:second"
      ])

    run = IntegritySentinel.run(@spec_attrs, observations, evaluated_at: "2026-06-19T00:00:00Z")

    assert run["verdict"] == "suspect"
    assert run["probe_results"]["repeatability"]["status"] == "suspect"
    assert [%{"rule_key" => "test_integrity.repeatability_unstable"}] = run["findings"]
  end

  test "missing required observations are not assessed until evidence exists" do
    run =
      IntegritySentinel.run(@spec_attrs, %{},
        required_probes: [:base_calibration, :hermeticity],
        evaluated_at: "2026-06-19T00:00:00Z"
      )

    assert run["verdict"] == "not_assessed"
    assert run["probe_results"]["base_calibration"]["status"] == "not_assessed"
    assert run["probe_results"]["hermeticity"]["status"] == "not_assessed"
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
            obligation_id: "verification_obligation:sha256:abc",
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
end
