defmodule Conveyor.QualificationReportTest do
  use ExUnit.Case, async: true

  alias Conveyor.Qualification.Report

  test "publishes evidence roots, quality intervals, limitations, waivers, and invalidation triggers" do
    report =
      Report.publish(%{
        grant: %{
          "id" => "qualification_grant:sha256:grant",
          "scope_ref" => "qualification-scope:adapter=primary-live",
          "evidence_root_digest" => digest("evidence-root"),
          "success_rate_bands" => [
            %{
              "capability" => "QUALIFICATION-GRANTS",
              "lower_bound" => 0.95,
              "upper_bound" => 1.0,
              "sample_count" => 40,
              "policy_ref" => "policy:p15-b7"
            }
          ],
          "limitations" => ["offline-only"],
          "waiver_refs" => ["waiver:legacy-fixture"],
          "issued_at" => "2026-06-19T00:00:00Z",
          "expires_at" => "2026-07-19T00:00:00Z",
          "invalidation_triggers" => ["policy_digest_changed"],
          "max_autonomy" => "local_dev"
        },
        scope_lattice: %{
          "unassessed_strata" => ["production_deployment"]
        },
        active_waivers: [
          %{
            "id" => "waiver:legacy-fixture",
            "owner" => "release-captain",
            "compensating_controls" => ["manual review"],
            "max_autonomy" => "local_dev",
            "expires_at" => "2026-06-30T00:00:00Z"
          }
        ],
        residual_risks: ["primary adapter not qualified for production"]
      })

    assert report["schema_version"] == "conveyor.qualification_release_report@1"
    assert report["complete?"] == true

    assert [
             %{
               "grant_id" => "qualification_grant:sha256:grant",
               "deterministic_evidence_root" => evidence_root,
               "live_quality_intervals" => [quality_interval],
               "limitations" => ["offline-only"],
               "unassessed_capabilities" => ["production_deployment"],
               "active_waivers" => [waiver],
               "issued_at" => "2026-06-19T00:00:00Z",
               "expires_at" => "2026-07-19T00:00:00Z",
               "invalidation_triggers" => ["policy_digest_changed"],
               "residual_risks" => ["primary adapter not qualified for production"]
             }
           ] = report["grant_reports"]

    assert evidence_root == digest("evidence-root")
    assert quality_interval["sample_count"] == 40
    assert quality_interval["lower_bound"] == 0.95
    assert waiver["compensating_controls"] == ["manual review"]
  end

  defp digest(label) do
    "sha256:" <> (:crypto.hash(:sha256, label) |> Base.encode16(case: :lower))
  end
end
