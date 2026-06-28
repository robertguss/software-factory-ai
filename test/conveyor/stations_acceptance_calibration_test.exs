defmodule Conveyor.StationsAcceptanceCalibrationTest do
  # TEST-ONLY behavioral unit test for the AcceptanceCalibration station (plan unit U10).
  #
  # Output contract (happy path): run/2 returns
  #   {:ok, %{"test_pack_calibration" => %{"id" => _, "status" => _, "expected_failures" => _}}}
  #
  # Hermetic happy path: with NO workspace_path/base_commit in the input, the station skips the
  # detached git worktree and calls AcceptanceCalibration.run!/2 with no runner. A TestPack with
  # an empty runner_command_specs list runs zero commands, so the real calibration record is
  # produced without invoking pytest/toolchains. (A full :eval integration test adds a real
  # worktree at base_commit and runs the locked acceptance commands, asserting status "valid"
  # only when those tests genuinely fail at base.)
  #
  # Failure mode: ArgumentError when context.run_attempt.run_spec_id has no RunSpec.
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TestPack
  alias Conveyor.Stations.AcceptanceCalibration

  @base_commit String.duplicate("b", 40)

  test "run/2 produces a test pack calibration record for the run spec" do
    %{run_spec: run_spec} = fixture!("acceptance-calibration-happy")

    input = %{"blob_root" => temp_dir!("acceptance-calibration-blobs")}

    assert {:ok, output} =
             AcceptanceCalibration.run(input, %{run_attempt: %{run_spec_id: run_spec.id}})

    calibration = output["test_pack_calibration"]
    assert is_binary(calibration["id"])
    # calibration_attrs only ever sets :valid or :invalid; with zero commands the base run is
    # vacuously green, which yields an "invalid" calibration.
    assert calibration["status"] in ["valid", "invalid"]
    assert is_list(calibration["expected_failures"])
  end

  test "run/2 raises ArgumentError when the run spec does not exist" do
    assert_raise ArgumentError, fn ->
      AcceptanceCalibration.run(%{}, %{run_attempt: %{run_spec_id: Ecto.UUID.generate()}})
    end
  end

  defp fixture!(label) do
    project =
      Ash.create!(
        Project,
        %{
          name: "AcceptanceCalibration #{label}",
          local_path: temp_dir!(label),
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "AcceptanceCalibration plan",
          intent: "Exercise the acceptance_calibration station.",
          source_document: "docs/acceptance-calibration.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "AcceptanceCalibration epic", description: "Calibration."},
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{epic_id: epic.id, title: "AcceptanceCalibration slice", position: 1},
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

    # Empty runner_command_specs => AcceptanceCalibration.run!/2 runs zero commands (no toolchain).
    test_pack =
      Ash.create!(
        TestPack,
        %{
          slice_id: slice.id,
          version: 1,
          source_ref: "tests/",
          test_pack_ref: "artifacts/test-packs/acceptance-calibration.tar",
          test_pack_sha256: digest("test-pack"),
          required_test_refs: [],
          acceptance_criteria_refs: [],
          mount_path: "tests",
          runner_command_specs: [],
          test_result_adapter: "pytest-json",
          locked_at: DateTime.utc_now(),
          locked_by: "planner"
        },
        domain: Factory
      )

    %{slice: slice, run_spec: run_spec, test_pack: test_pack}
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-acceptance-calibration")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/acceptance-calibration.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: @base_commit,
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "fake"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: %{
        "schema_version" => "conveyor.station_plan@1",
        "stations" => [
          %{
            "key" => "acceptance_calibration",
            "module" => "Conveyor.Stations.AcceptanceCalibration",
            "input" => %{"run_spec_sha256" => run_spec_sha256},
            "output" => %{"run_spec_sha256" => run_spec_sha256}
          }
        ]
      },
      station_plan_sha256: digest("station-plan"),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp temp_dir!(label) do
    path =
      Path.join(System.tmp_dir!(), "conveyor-#{label}-#{System.unique_integer([:positive])}")

    File.mkdir_p!(path)
    path
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
