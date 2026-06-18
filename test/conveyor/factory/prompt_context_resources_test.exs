defmodule Conveyor.Factory.PromptContextResourcesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.CodeQualityRun
  alias Conveyor.Factory.ContextPack
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.InstructionSource
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunPrompt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Prompt sample", local_path: "/tmp/prompt-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Prompt plan",
          intent: "Assemble prompt context.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Prompt epic", description: "Prompts."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Prompt slice", position: 1}, domain: Factory)

    brief =
      Ash.create!(
        AgentBrief,
        %{
          slice_id: slice.id,
          version: 1,
          current_behavior: "Tasks can be listed and created.",
          desired_behavior: "Tasks can also be completed.",
          key_interfaces: ["PATCH /tasks/{id}", "Task.completed"],
          out_of_scope: ["Authentication"],
          acceptance_criteria: [acceptance_criterion()],
          required_tests: [%{"ref" => "tests/test_tasks.py::test_complete_task"}],
          verification_commands: [command_spec()],
          non_goals: ["Bulk updates"],
          locked_at: DateTime.utc_now(:microsecond),
          locked_by: "planner",
          contract_sha256: digest("brief")
        },
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: "abc123",
          status: :planned,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-prompt"
        },
        domain: Factory
      )

    %{brief: brief, project: project, run_attempt: run_attempt, slice: slice}
  end

  test "context packs record cited scout output and quality references", %{slice: slice} do
    pack =
      Ash.create!(
        ContextPack,
        %{
          slice_id: slice.id,
          scout_version: "context-scout@1",
          confidence: Decimal.new("0.86"),
          relevant_files: [
            %{"path" => "app/main.py", "reason" => "Defines current task routes"}
          ],
          key_interfaces: ["PATCH /tasks/{id}", "Task.completed"],
          existing_tests: ["tests/test_tasks.py"],
          risks: ["Persistence must preserve completed state."],
          suggested_validation: ["pytest -q"],
          code_quality_refs: ["artifacts/quality/baseline.json"]
        },
        domain: Factory
      )

    assert Decimal.compare(pack.confidence, Decimal.new("0.86")) == :eq
    assert [%{"path" => "app/main.py"}] = pack.relevant_files
    assert pack.code_quality_refs == ["artifacts/quality/baseline.json"]
  end

  test "run prompts link brief, context pack, and trust-labeled instruction sources", %{
    brief: brief,
    slice: slice
  } do
    pack = Ash.create!(ContextPack, context_pack_attrs(slice.id), domain: Factory)
    body = "# Role\n\nImplement exactly one slice."

    prompt =
      Ash.create!(
        RunPrompt,
        %{
          slice_id: slice.id,
          brief_id: brief.id,
          context_pack_id: pack.id,
          template_version: "implementation-prompt@1",
          body: body,
          body_sha256: digest(body),
          policy_refs: ["policies/implement.yml"],
          memory_refs: [],
          output_schema_version: "conveyor.agent_output@1"
        },
        domain: Factory
      )

    assert prompt.brief_id == brief.id
    assert prompt.context_pack_id == pack.id

    attrs = %{
      run_prompt_id: prompt.id,
      source_kind: :repo_file,
      trust_level: :untrusted,
      source_ref: "app/main.py",
      digest: digest("app/main.py"),
      included_in_prompt: true
    }

    source = Ash.create!(InstructionSource, attrs, domain: Factory)
    assert source.source_kind == :repo_file
    assert source.trust_level == :untrusted

    assert_raise Ash.Error.Invalid, fn ->
      Ash.create!(InstructionSource, Map.put(attrs, :trust_level, :privileged), domain: Factory)
    end
  end

  test "code quality runs capture adapter results and high-risk deltas", %{
    project: project,
    run_attempt: run_attempt
  } do
    run =
      Ash.create!(
        CodeQualityRun,
        %{
          project_id: project.id,
          run_attempt_id: run_attempt.id,
          adapter: "CodeQualityAdapter.Noop",
          profile: "standard",
          baseline_ref: "artifacts/quality/baseline.json",
          result_ref: "artifacts/quality/attempt-1.json",
          findings_summary: %{"high" => 0, "medium" => 1},
          new_high_risk_findings: 0,
          status: :succeeded
        },
        domain: Factory
      )

    assert run.project_id == project.id
    assert run.run_attempt_id == run_attempt.id
    assert run.findings_summary["medium"] == 1
    assert run.new_high_risk_findings == 0

    updated = Ash.update!(run, %{status: :blocked, new_high_risk_findings: 1}, domain: Factory)
    assert updated.status == :blocked
    assert updated.new_high_risk_findings == 1
  end

  defp context_pack_attrs(slice_id) do
    %{
      slice_id: slice_id,
      scout_version: "context-scout@1",
      confidence: Decimal.new("0.75"),
      relevant_files: [%{"path" => "app/main.py", "reason" => "Route implementation."}],
      key_interfaces: ["PATCH /tasks/{id}"],
      existing_tests: ["tests/test_tasks.py"],
      risks: ["Route may not preserve list behavior."],
      suggested_validation: ["pytest -q"],
      code_quality_refs: []
    }
  end

  defp acceptance_criterion do
    %{
      "id" => "AC-001",
      "text" => "Complete a task.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-002"],
      "required_test_refs" => ["tests/test_tasks.py::test_complete_task"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp command_spec do
    %{
      "key" => "pytest",
      "argv" => ["pytest", "-q"],
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

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-prompt")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/attempt-1.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: %{
        "schema_version" => "conveyor.station_plan@1",
        "stations" => [
          %{
            "key" => "prompt",
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
