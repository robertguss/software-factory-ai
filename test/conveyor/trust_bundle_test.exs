defmodule Conveyor.TrustBundleTest do
  use ExUnit.Case, async: true

  alias Conveyor.TrustBundle

  test "builds a DSSE-shaped trust_bundle@1 around the reproducible gate verdict" do
    bundle =
      TrustBundle.build(%{
        run_attempt_id: "attempt-1",
        run_spec_sha256: digest("run-spec"),
        gate_result_id: "gate-1",
        gate_result_sha256: digest("gate-result"),
        verdict: :passed,
        provenance_edge_sha256s: [digest("edge-1")],
        created_at: "2026-06-20T00:00:00Z"
      })

    assert bundle["schema_version"] == "conveyor.trust_bundle@1"
    assert bundle["dsse"]["payloadType"] == "application/vnd.conveyor.trust_bundle.payload+json"
    assert [%{"keyid" => "unsigned-local"}] = bundle["dsse"]["signatures"]

    payload =
      bundle["dsse"]["payload"]
      |> Base.decode64!()
      |> Jason.decode!()

    assert payload["verdict"] == "passed"
    assert payload["gate_result_id"] == "gate-1"
    assert payload["provenance_edge_sha256s"] == [digest("edge-1")]
    assert bundle["payload_sha256"] == digest(payload)
  end

  defp digest(value) do
    "sha256:" <>
      (value
       |> Conveyor.CanonicalJson.encode()
       |> then(&:crypto.hash(:sha256, &1))
       |> Base.encode16(case: :lower))
  end
end
