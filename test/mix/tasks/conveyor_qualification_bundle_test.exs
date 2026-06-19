defmodule Mix.Tasks.ConveyorQualificationBundleTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "qualification_bundle builds JSON and qualification_bundle_verify verifies offline" do
    input_path = write_json!(bundle_input())
    put_exit_fun(:conveyor_qualification_bundle_exit_fun)

    bundle_output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.qualification_bundle")
        Mix.Task.run("conveyor.qualification_bundle", ["--input", input_path, "--format", "json"])
      end)

    bundle = Jason.decode!(bundle_output)

    assert bundle["schema_version"] == "conveyor.qualification_bundle@1"
    assert_received {:exit_code, 0}

    bundle_path = write_json!(bundle)
    put_exit_fun(:conveyor_qualification_bundle_verify_exit_fun)

    verify_output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.qualification_bundle_verify")

        Mix.Task.run("conveyor.qualification_bundle_verify", [
          "--offline",
          bundle_path,
          "--format",
          "json"
        ])
      end)

    verification = Jason.decode!(verify_output)

    assert verification["schema_version"] == "conveyor.qualification_bundle_verification@1"
    assert verification["status"] == "verified"
    assert verification["checked_without_live_db?"] == true
    assert_received {:exit_code, 0}
  after
    Process.delete(:conveyor_qualification_bundle_exit_fun)
    Process.delete(:conveyor_qualification_bundle_verify_exit_fun)
  end

  defp put_exit_fun(key) do
    test_pid = self()
    Process.put(key, fn code -> send(test_pid, {:exit_code, code}) end)
  end

  defp write_json!(payload) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-qualification-bundle-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(payload))
    path
  end

  defp bundle_input do
    %{
      registry_digest: digest("registry"),
      root_manifest_digest: digest("root-manifest"),
      run_digest: digest("qualification-run"),
      grant: %{
        "id" => "qualification_grant:sha256:grant",
        "scope_digest" => digest("scope"),
        "evidence_root_digest" => digest("evidence-root"),
        "waiver_refs" => []
      },
      scope_lattice: %{
        "scope_digest" => digest("scope"),
        "worst_required_stratum_result" => "pass"
      },
      hard_invariant_verdicts: [%{"key" => "registry", "status" => "passed"}],
      canary_refs: ["battery-run:p15-b5"],
      replay_anchors: ["replay-anchor:strict"],
      waiver_availability: [],
      signature_status: "unsigned_local"
    }
  end

  defp digest(label) do
    "sha256:" <> (:crypto.hash(:sha256, label) |> Base.encode16(case: :lower))
  end
end
