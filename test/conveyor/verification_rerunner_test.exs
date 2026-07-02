defmodule Conveyor.VerificationRerunnerTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Evidence.VerificationRerunner
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.VerificationSuite

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Verification rerunner sample",
          local_path: "/tmp/verification",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Verification plan",
          intent: "Rerun suites.",
          source_document: "docs/verification.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Verification epic", description: "Evidence."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Verification slice", position: 1},
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

    %{project: project, run_spec: run_spec, slice: slice}
  end

  test "reruns baseline and acceptance suites into structured test identities", %{
    project: project,
    run_spec: run_spec,
    slice: slice
  } do
    Ash.create!(
      VerificationSuite,
      suite_attrs(project.id, slice.id, :baseline_regression, [
        command_spec("baseline", ["mix", "test"], result_format: "json")
      ]),
      domain: Factory
    )

    Ash.create!(
      VerificationSuite,
      suite_attrs(project.id, slice.id, :acceptance_locked, [
        command_spec("acceptance", ["mix", "test", "acceptance"], result_format: "tap")
      ]),
      domain: Factory
    )

    result =
      VerificationRerunner.run!(run_spec,
        runner: fn
          %{"key" => "baseline"} ->
            %{exit_code: 0, stdout: Jason.encode!(%{tests: [%{id: "base-1", status: "passed"}]})}

          %{"key" => "acceptance"} ->
            %{exit_code: 0, stdout: "ok 1 - accepts patch\n"}
        end
      )

    assert result.status == :passed
    assert [baseline, acceptance] = result.suites

    assert baseline["commands"]
           |> hd()
           |> get_in(["attempts", Access.at(0), "tests", Access.at(0), "id"]) == "base-1"

    assert acceptance["commands"]
           |> hd()
           |> get_in(["attempts", Access.at(0), "tests", Access.at(0), "name"]) == "accepts patch"
  end

  test "returns suites in a deterministic suite_kind order regardless of insertion order", %{
    project: project,
    run_spec: run_spec,
    slice: slice
  } do
    # Insert acceptance FIRST, baseline SECOND — deterministic ordering must still put
    # baseline_regression before acceptance_locked (evidence order can't depend on DB rows).
    Ash.create!(
      VerificationSuite,
      suite_attrs(project.id, slice.id, :acceptance_locked, [
        command_spec("acceptance", ["mix", "test", "acceptance"], result_format: "tap")
      ]),
      domain: Factory
    )

    Ash.create!(
      VerificationSuite,
      suite_attrs(project.id, slice.id, :baseline_regression, [
        command_spec("baseline", ["mix", "test"], result_format: "json")
      ]),
      domain: Factory
    )

    result =
      VerificationRerunner.run!(run_spec,
        runner: fn
          %{"key" => "baseline"} ->
            %{exit_code: 0, stdout: Jason.encode!(%{tests: [%{id: "base-1", status: "passed"}]})}

          %{"key" => "acceptance"} ->
            %{exit_code: 0, stdout: "ok 1 - accepts patch\n"}
        end
      )

    assert Enum.map(result.suites, & &1["suite_kind"]) == [
             "baseline_regression",
             "acceptance_locked"
           ]
  end

  test "classifies repeated mixed outcomes as quarantined flakes", %{
    project: project,
    run_spec: run_spec,
    slice: slice
  } do
    Ash.create!(
      VerificationSuite,
      suite_attrs(project.id, slice.id, :acceptance_locked, [
        command_spec("flake", ["mix", "test"], repeat: 2, flake_policy: "quarantine")
      ]),
      domain: Factory
    )

    attempts = :counters.new(1, [])

    result =
      VerificationRerunner.run!(run_spec,
        runner: fn _command ->
          :counters.add(attempts, 1, 1)

          if :counters.get(attempts, 1) == 1 do
            %{exit_code: 1, stdout: "failed\n"}
          else
            %{exit_code: 0, stdout: "passed\n"}
          end
        end
      )

    assert result.status == :passed
    assert [suite] = result.suites
    assert [command] = suite["commands"]
    assert command["classification"] == "flake"
    assert command["status"] == "passed_with_warning"
  end

  test "retries configured infra failures before parsing result", %{
    project: project,
    run_spec: run_spec,
    slice: slice
  } do
    Ash.create!(
      VerificationSuite,
      suite_attrs(project.id, slice.id, :baseline_regression, [
        command_spec("infra", ["mix", "test"],
          infra_retry_policy: %{"max_retries" => 1, "retry_on" => ["container_start_failed"]}
        )
      ]),
      domain: Factory
    )

    attempts = :counters.new(1, [])

    result =
      VerificationRerunner.run!(run_spec,
        runner: fn _command ->
          :counters.add(attempts, 1, 1)

          if :counters.get(attempts, 1) == 1 do
            %{error: :container_start_failed}
          else
            %{exit_code: 0, stdout: "ok\n"}
          end
        end
      )

    assert result.status == :passed
    assert [suite] = result.suites

    assert get_in(suite, ["commands", Access.at(0), "attempts", Access.at(0), "infra_retries"]) ==
             1
  end

  test "passes clean-container reproducibility when agent and gate results match", %{
    project: project,
    run_spec: run_spec,
    slice: slice
  } do
    Ash.create!(
      VerificationSuite,
      suite_attrs(project.id, slice.id, :acceptance_locked, [
        command_spec("acceptance", ["mix", "test"], result_format: "json")
      ]),
      domain: Factory
    )

    runner = fn %{"key" => "acceptance"} ->
      %{exit_code: 0, stdout: Jason.encode!(%{tests: [%{id: "acceptance-1", status: "passed"}]})}
    end

    result =
      VerificationRerunner.run_reproducible!(run_spec,
        agent_runner: runner,
        gate_runner: runner
      )

    assert result.status == :passed
    assert result.reproducibility["status"] == "passed"
    assert result.reproducibility["findings"] == []
    assert result.reproducibility["agent_sha256"] == result.reproducibility["gate_sha256"]
  end

  test "fails clean-container reproducibility when gate result diverges from agent result", %{
    project: project,
    run_spec: run_spec,
    slice: slice
  } do
    Ash.create!(
      VerificationSuite,
      suite_attrs(project.id, slice.id, :acceptance_locked, [
        command_spec("acceptance", ["mix", "test"], result_format: "json")
      ]),
      domain: Factory
    )

    agent_runner = fn %{"key" => "acceptance"} ->
      %{exit_code: 0, stdout: Jason.encode!(%{tests: [%{id: "acceptance-1", status: "passed"}]})}
    end

    gate_runner = fn %{"key" => "acceptance"} ->
      %{exit_code: 1, stdout: Jason.encode!(%{tests: [%{id: "acceptance-1", status: "failed"}]})}
    end

    result =
      VerificationRerunner.run_reproducible!(run_spec,
        agent_runner: agent_runner,
        gate_runner: gate_runner
      )

    assert result.status == :failed
    assert result.reproducibility["status"] == "failed"
    assert result.reproducibility["agent_status"] == "passed"
    assert result.reproducibility["gate_status"] == "failed"
    assert result.reproducibility["agent_sha256"] != result.reproducibility["gate_sha256"]

    assert [
             %{
               "category" => "clean_container_divergence",
               "severity" => "blocking"
             }
           ] = result.reproducibility["findings"]
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

  defp command_spec(key, argv, opts) do
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
      "repeat" => Keyword.get(opts, :repeat, 1),
      "flake_policy" => Keyword.get(opts, :flake_policy, "fail_closed"),
      "infra_retry_policy" =>
        Keyword.get(opts, :infra_retry_policy, %{"max_retries" => 0, "retry_on" => []}),
      "result_format" => Keyword.get(opts, :result_format, "stdout")
    }
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-verification")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/verification.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
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
            "key" => "evidence",
            "kind" => "evidence",
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

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
