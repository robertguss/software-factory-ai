defmodule Conveyor.StationsBaselineHealthTest do
  # TEST-ONLY behavioral unit test for the BaselineHealth station (plan unit U10).
  #
  # Output contract (happy path): run/2 returns
  #   {:ok, %{"baseline_health_status" => _, "baseline_suites" => _}}
  # With no baseline_regression VerificationSuites for the slice, BaselineHealth.run!/1
  # vacuously passes ("passed", []) — a fully hermetic happy path that exercises the real
  # status/suite projection without any toolchain.
  # Failure mode: ArgumentError when context.run_attempt.run_spec_id has no RunSpec.
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Stations.BaselineHealth

  @base_commit String.duplicate("a", 40)

  test "run/2 returns the baseline status and suites for a run spec" do
    run_spec = run_spec!("baseline-health-happy")

    assert {:ok, output} = BaselineHealth.run(%{}, %{run_attempt: %{run_spec_id: run_spec.id}})

    # No baseline suites are seeded, so the suite set is empty and the status is "passed".
    assert output["baseline_health_status"] == "passed"
    assert output["baseline_suites"] == []
  end

  test "run/2 raises ArgumentError when the run spec does not exist" do
    assert_raise ArgumentError, fn ->
      BaselineHealth.run(%{}, %{run_attempt: %{run_spec_id: Ecto.UUID.generate()}})
    end
  end

  defp run_spec!(label) do
    project =
      Ash.create!(
        Project,
        %{name: "BaselineHealth #{label}", local_path: temp_dir!(label), default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "BaselineHealth plan",
          intent: "Exercise the baseline_health station.",
          source_document: "docs/baseline-health.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "BaselineHealth epic", description: "Baseline."},
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{epic_id: epic.id, title: "BaselineHealth slice", position: 1},
        domain: Factory
      )

    Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-baseline-health")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/baseline-health.json",
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
            "key" => "baseline_health",
            "module" => "Conveyor.Stations.BaselineHealth",
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
