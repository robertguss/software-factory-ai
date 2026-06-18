defmodule Conveyor.GateStagesBuildTestTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.VerificationSuite
  alias Conveyor.Gate
  alias Conveyor.Gate.Stages.BuildInstall
  alias Conveyor.Gate.Stages.TestExecution

  test "build install passes on successful build/import evidence" do
    result =
      BuildInstall.run(%{
        build_install_result: %{
          status: :passed,
          artifact_refs: ["logs/build.json"],
          commands: [
            %{key: "deps", argv: ["mix", "deps.get"], exit_code: 0},
            %{key: "compile", argv: ["mix", "compile"], exit_code: 0}
          ]
        }
      })

    assert result.status == :passed
    assert result.evidence_refs == ["logs/build.json"]
  end

  test "build install fails on non-zero build/import command evidence" do
    result =
      BuildInstall.run(%{
        build_install_result: %{
          status: :failed,
          commands: [
            %{key: "compile", argv: ["mix", "compile"], exit_code: 1}
          ]
        }
      })

    assert result.status == :failed
    categories = Enum.map(result.findings, & &1["category"])
    assert "build_install_failed" in categories
    assert "build_install_command_failed" in categories
  end

  test "test execution passes with green baseline locked acceptance and valid base-red calibration" do
    result =
      TestExecution.run(%{
        verification_result: verification_result(),
        test_pack_calibration: valid_calibration()
      })

    assert result.status == :passed
    assert result.findings == []
  end

  test "test execution fails when baseline regression is red" do
    result =
      TestExecution.run(%{
        verification_result:
          verification_result([
            suite("baseline", "baseline_regression", "failed"),
            suite("acceptance", "acceptance_locked", "passed")
          ]),
        test_pack_calibration: valid_calibration()
      })

    assert result.status == :failed
    assert Enum.any?(result.findings, &(&1["category"] == "baseline_regression_failed"))
  end

  test "test execution fails without valid locked acceptance calibration" do
    result =
      TestExecution.run(%{
        verification_result: verification_result(),
        test_pack_calibration: %{status: :invalid, expected_failures: []}
      })

    assert result.status == :failed
    categories = Enum.map(result.findings, & &1["category"])
    assert "invalid_acceptance_calibration" in categories
  end

  test "test execution fails closed on unapproved flaky quarantine" do
    flaky_result =
      verification_result([
        suite("baseline", "baseline_regression", "passed"),
        suite("acceptance", "acceptance_locked", "passed", [
          %{"key" => "acceptance", "status" => "passed_with_warning", "classification" => "flake"}
        ])
      ])

    failed =
      TestExecution.run(%{
        verification_result: flaky_result,
        test_pack_calibration: valid_calibration()
      })

    assert failed.status == :failed
    assert Enum.any?(failed.findings, &(&1["category"] == "unapproved_flake_quarantine"))

    approved =
      TestExecution.run(%{
        verification_result: flaky_result,
        test_pack_calibration: valid_calibration(),
        flake_quarantine_approved: true
      })

    assert approved.status == :passed
  end

  test "test execution can invoke VerificationRerunner from a RunSpec" do
    fixture = create_artifact_run!(blob_root: temp_dir!("gate-test-execution"))
    run_spec = get_by_id!(RunSpec, fixture.run_attempt.run_spec_id)

    Ash.create!(
      VerificationSuite,
      suite_attrs(fixture.project.id, run_spec.slice_id, :baseline_regression, [
        command_spec("baseline", ["mix", "test"])
      ]),
      domain: Factory
    )

    Ash.create!(
      VerificationSuite,
      suite_attrs(fixture.project.id, run_spec.slice_id, :acceptance_locked, [
        command_spec("acceptance", ["mix", "test", "acceptance"])
      ]),
      domain: Factory
    )

    result =
      TestExecution.run(%{
        run_spec: run_spec,
        test_pack_calibration: valid_calibration(),
        verification_runner: fn _command -> %{exit_code: 0, stdout: "ok\n"} end
      })

    assert result.status == :passed

    assert result.evidence_refs |> Enum.count(&String.starts_with?(&1, "verification-suites/")) ==
             2
  end

  test "build and test stages compose through the gate framework" do
    result =
      Gate.run!(
        %{
          gate_code_sha256: "sha256:gate",
          policy_sha256: "sha256:policy",
          contract_lock_sha256: "sha256:contract",
          build_install_result: %{status: :passed, commands: []},
          verification_result: verification_result(),
          test_pack_calibration: valid_calibration()
        },
        [
          %{key: "build_install", module: BuildInstall},
          %{key: "test_execution", module: TestExecution}
        ]
      )

    assert result.passed?
    assert Enum.map(result.stages, & &1.status) == [:passed, :passed]
  end

  defp verification_result(suites \\ nil) do
    %{
      status: :passed,
      suites:
        suites ||
          [
            suite("baseline", "baseline_regression", "passed"),
            suite("acceptance", "acceptance_locked", "passed")
          ]
    }
  end

  defp suite(key, kind, status, commands \\ nil) do
    %{
      "suite_id" => "#{key}-suite-id",
      "key" => key,
      "suite_kind" => kind,
      "status" => status,
      "commands" =>
        commands || [%{"key" => key, "status" => "passed", "classification" => "stable"}]
    }
  end

  defp valid_calibration do
    %{
      status: :valid,
      expected_failures: ["acceptance::test_required"],
      result_ref: "calibrations/acceptance.json"
    }
  end

  defp suite_attrs(project_id, slice_id, suite_kind, command_specs) do
    %{
      project_id: project_id,
      slice_id: slice_id,
      key: Atom.to_string(suite_kind),
      suite_kind: suite_kind,
      command_specs: command_specs,
      expected_on_base: :pass,
      expected_on_patch: :pass,
      required: true,
      result_format: :stdout
    }
  end

  defp command_spec(key, argv) do
    %{
      "key" => key,
      "argv" => argv,
      "cwd" => ".",
      "profile" => "verify",
      "required" => true,
      "timeout_ms" => 120_000,
      "network" => "none",
      "env_allowlist" => [],
      "output_limit_bytes" => 2_000_000,
      "repeat" => 1,
      "flake_policy" => "fail_closed",
      "infra_retry_policy" => %{"max_retries" => 0, "retry_on" => []},
      "result_format" => "stdout"
    }
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
