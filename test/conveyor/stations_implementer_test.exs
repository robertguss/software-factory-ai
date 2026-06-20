defmodule Conveyor.StationsImplementerTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.ContextPack
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunPrompt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Stations.Implementer

  test "creates a prompt and agent session from context pack input when none exists" do
    fixture = fixture!("implementer-bootstrap")

    assert [] = Ash.read!(AgentSession, domain: Factory)
    assert [] = Ash.read!(RunPrompt, domain: Factory)

    assert {:ok, output} =
             Implementer.run(
               %{
                 "workspace_path" => fixture.workspace_path,
                 "base_commit" => fixture.base_commit,
                 "blob_root" => fixture.blob_root,
                 "context_pack_id" => fixture.context_pack.id,
                 "adapter" => "Conveyor.AgentRunner.Fake"
               },
               %{run_attempt: fixture.run_attempt}
             )

    assert output["patch_set_id"]
    assert output["diff_ref"]

    assert [session] = Ash.read!(AgentSession, domain: Factory)
    prompt = Ash.get!(RunPrompt, session.run_prompt_id, domain: Factory)

    assert session.run_attempt_id == fixture.run_attempt.id
    assert session.role == :implementer
    assert session.base_commit == fixture.base_commit
    assert prompt.context_pack_id == fixture.context_pack.id
    assert prompt.brief_id == fixture.brief.id
    assert prompt.body =~ "Fake runner writes deterministic output."
  end

  defp fixture!(label) do
    workspace_path = git_workspace!(label)
    base_commit = git!(workspace_path, ["rev-parse", "HEAD"])
    blob_root = temp_dir!("#{label}-blobs")

    project =
      Ash.create!(
        Project,
        %{name: "Implementer sample", local_path: workspace_path, default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Implementer plan",
          intent: "Exercise production implementer bootstrap.",
          source_document: "docs/implementer.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan"),
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Implementer epic", description: "Bootstrap prompt."},
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{epic_id: epic.id, title: "Implementer slice", position: 1, autonomy_level: "L1"},
        domain: Factory
      )

    brief =
      Ash.create!(
        AgentBrief,
        %{
          slice_id: slice.id,
          version: 1,
          current_behavior: "No fake runner output exists.",
          desired_behavior: "Fake runner writes deterministic output.",
          key_interfaces: ["Conveyor.AgentRunner.Fake.run/4"],
          out_of_scope: ["Do not edit policy."],
          risk: "low",
          acceptance_criteria: [acceptance_criterion()],
          required_tests: [required_test()],
          verification_commands: [command_spec()],
          non_goals: ["Do not call external services."],
          locked_at: DateTime.utc_now(:microsecond),
          locked_by: "planner",
          contract_sha256: digest("brief")
        },
        domain: Factory
      )

    context_pack =
      Ash.create!(
        ContextPack,
        %{
          slice_id: slice.id,
          scout_version: "context-scout@1",
          confidence: Decimal.new("0.90"),
          relevant_files: [%{"path" => "fake_agent_output.txt", "reason" => "Fake output."}],
          key_interfaces: ["Conveyor.AgentRunner.Fake.run/4"],
          suggested_validation: ["mix test"],
          code_quality_refs: []
        },
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id, base_commit), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: base_commit,
          status: :running,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-implementer"
        },
        domain: Factory
      )

    %{
      base_commit: base_commit,
      blob_root: blob_root,
      brief: brief,
      context_pack: context_pack,
      run_attempt: run_attempt,
      workspace_path: workspace_path
    }
  end

  defp run_spec_attrs(slice_id, base_commit) do
    run_spec_sha256 = digest("run-spec-implementer")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/implementer.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: base_commit,
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
            "key" => "implement",
            "module" => "Conveyor.Stations.Implementer",
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

  defp git_workspace!(label) do
    path = temp_dir!(label)
    git!(path, ["init", "-b", "main"])
    git!(path, ["config", "user.email", "conveyor@example.test"])
    git!(path, ["config", "user.name", "Conveyor Test"])
    File.write!(Path.join(path, "README.md"), "base\n")
    git!(path, ["add", "."])
    git!(path, ["commit", "-m", "base"])
    path
  end

  defp git!(path, args) do
    {output, 0} = System.cmd("git", ["-C", path | args], stderr_to_stdout: true)
    String.trim(output)
  end

  defp acceptance_criterion do
    %{
      "id" => "AC-001",
      "text" => "Fake runner writes deterministic output.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-001"],
      "required_test_refs" => ["tests/test_fake.py::test_output"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp required_test do
    %{
      "ref" => "tests/test_fake.py::test_output",
      "source_ref" => "tests/test_fake.py",
      "acceptance_criteria_refs" => ["AC-001"],
      "locked" => true
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
      "result_format" => "junit"
    }
  end

  defp temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
