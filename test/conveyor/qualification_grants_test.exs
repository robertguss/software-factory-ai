defmodule Conveyor.QualificationGrantsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Qualification.Grants

  @issued_at "2026-06-19T00:00:00Z"

  test "issues the narrowest supported grant with admission permit and checkpoint" do
    assert {:ok,
            %{
              grant: grant,
              scope_lattice: scope_lattice,
              admission_permit: permit,
              permit_checkpoint: checkpoint
            }} =
             Grants.issue(%{
               project_id: "software-factory-ai",
               requested_scope: %{"adapter" => "primary-live", "archetype" => "planning"},
               supported_scope: %{
                 "adapter" => "primary-live",
                 "archetype" => "planning",
                 "environment" => "ci-linux"
               },
               gate_result: %{status: :passed, evidence_root_digest: digest("evidence-root")},
               scope_lattice: %{
                 "direct_evidence_strata" => [
                   %{
                     "stratum" => "hard_blockers",
                     "result" => "pass",
                     "evidence_refs" => ["gate-run-1"]
                   }
                 ],
                 "inherited_evidence_strata" => [],
                 "supporting_evidence_strata" => [
                   %{
                     "stratum" => "live_quality",
                     "result" => "pass",
                     "evidence_refs" => ["sample-run-1"]
                   }
                 ],
                 "inheritance_default" => "none",
                 "unassessed_strata" => ["production"],
                 "worst_required_stratum_result" => "pass"
               },
               max_autonomy: "local_dev",
               success_rate_bands: [
                 %{
                   "capability" => "QUALIFICATION-GRANTS",
                   "lower_bound" => 0.95,
                   "upper_bound" => 1.0,
                   "sample_count" => 40,
                   "policy_ref" => "policy:p15-b7"
                 }
               ],
               issued_at: @issued_at,
               expires_at: "2026-07-19T00:00:00Z"
             })

    assert grant["schema_version"] == "conveyor.qualification_grant@1"
    assert grant["status"] == "active"

    assert grant["scope"] == %{
             "adapter" => "primary-live",
             "archetype" => "planning",
             "environment" => "ci-linux"
           }

    assert grant["invalidation_triggers"] == ["policy_digest_changed", "scope_digest_changed"]
    assert scope_lattice["inheritance_default"] == "none"
    assert scope_lattice["worst_required_stratum_result"] == "pass"

    assert permit["schema_version"] == "conveyor.admission_permit@1"
    assert permit["qualification_grant_id"] == grant["id"]
    assert permit["expires_at"] > permit["issued_at"]

    assert checkpoint["schema_version"] == "conveyor.permit_checkpoint@1"
    assert checkpoint["admission_permit_id"] == permit["id"]
    assert checkpoint["result"] == "valid"

    assert_schema_valid!(grant, "conveyor.qualification_grant@1")
    assert_schema_valid!(scope_lattice, "conveyor.qualification_scope_lattice@1")
    assert_schema_valid!(permit, "conveyor.admission_permit@1")
    assert_schema_valid!(checkpoint, "conveyor.permit_checkpoint@1")
  end

  test "denies when supported evidence scope does not cover requested scope" do
    assert {:deny, %{reasons: [:scope_not_covered]}} =
             Grants.issue(%{
               project_id: "software-factory-ai",
               requested_scope: %{"adapter" => "primary-live", "environment" => "prod"},
               supported_scope: %{"adapter" => "primary-live", "environment" => "ci-linux"},
               gate_result: %{status: :passed},
               scope_lattice: %{"worst_required_stratum_result" => "pass"}
             })
  end

  defp digest(label) do
    "sha256:" <> (:crypto.hash(:sha256, label) |> Base.encode16(case: :lower))
  end

  defp assert_schema_valid!(resource, schema_name) do
    schema =
      "docs/schemas/#{schema_name}.json"
      |> File.read!()
      |> Jason.decode!()
      |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(resource, schema)
  end
end
