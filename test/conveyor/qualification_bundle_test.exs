defmodule Conveyor.QualificationBundleTest do
  use ExUnit.Case, async: true

  alias Conveyor.Qualification.Bundle

  test "builds an offline-verifiable bundle with authority and evidence digests" do
    bundle =
      Bundle.build(%{
        registry_digest: digest("registry"),
        root_manifest_digest: digest("root-manifest"),
        run_digest: digest("qualification-run"),
        grant: %{
          "id" => "qualification_grant:sha256:grant",
          "scope_digest" => digest("scope"),
          "evidence_root_digest" => digest("evidence-root"),
          "waiver_refs" => ["waiver:legacy-fixture"]
        },
        scope_lattice: %{
          "scope_digest" => digest("scope"),
          "worst_required_stratum_result" => "pass"
        },
        hard_invariant_verdicts: [
          %{"key" => "registry", "status" => "passed"},
          %{"key" => "canaries", "status" => "passed"}
        ],
        canary_refs: ["battery-run:p15-b5"],
        replay_anchors: ["replay-anchor:strict"],
        waiver_availability: [%{"waiver_ref" => "waiver:legacy-fixture", "available" => true}],
        signature_status: "unsigned_local"
      })

    assert bundle["schema_version"] == "conveyor.qualification_bundle@1"
    assert bundle["offline_verifiable?"] == true

    assert {:ok, verified} = Bundle.verify_offline(bundle)
    assert verified["grant_id"] == "qualification_grant:sha256:grant"
    assert verified["checked_without_live_db?"] == true
  end

  test "offline verification rejects grant scope digest drift" do
    bundle =
      Bundle.build(%{
        registry_digest: digest("registry"),
        root_manifest_digest: digest("root-manifest"),
        run_digest: digest("qualification-run"),
        grant: %{
          "id" => "qualification_grant:sha256:grant",
          "scope_digest" => digest("scope-a"),
          "evidence_root_digest" => digest("evidence-root")
        },
        scope_lattice: %{
          "scope_digest" => digest("scope-b"),
          "worst_required_stratum_result" => "pass"
        },
        hard_invariant_verdicts: [%{"key" => "registry", "status" => "passed"}],
        canary_refs: ["battery-run:p15-b5"],
        replay_anchors: ["replay-anchor:strict"],
        waiver_availability: [],
        signature_status: "unsigned_local"
      })

    assert {:error, %{reason: :scope_digest_mismatch}} = Bundle.verify_offline(bundle)
  end

  defp digest(label) do
    "sha256:" <> (:crypto.hash(:sha256, label) |> Base.encode16(case: :lower))
  end
end
