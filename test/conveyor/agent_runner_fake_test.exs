defmodule Conveyor.AgentRunnerFakeTest do
  use Conveyor.DataCase, async: false

  import Conveyor.AgentRunnerConformance
  import Conveyor.FactoryFixtures

  alias Conveyor.AgentRunner.Fake
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.ContextPack
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunPrompt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice

  test "fake runner satisfies the adapter conformance suite without credentials" do
    fixture = conformance_fixture!("fake-conformance")

    result = assert_adapter_conforms!(Fake, fixture)

    assert result.metadata["adapter"] == "fake"

    assert File.read!(Path.join(fixture.workspace.path, "fake_agent_output.txt")) =~
             fixture.run_prompt.body_sha256
  end

  test "fake runner reports malformed output as a structured adapter finding" do
    fixture = conformance_fixture!("fake-malformed")
    assert_malformed_output_is_structured!(Fake, fixture)
  end

  defp conformance_fixture!(label) do
    workspace_path = git_workspace!(label)
    base_commit = git!(workspace_path, ["rev-parse", "HEAD"])
    blob_root = temp_dir!("#{label}-blobs")

    project =
      Ash.create!(
        Project,
        %{name: "Fake runner sample", local_path: workspace_path, default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Fake runner plan",
          intent: "Conform fake AgentRunner.",
          source_document: "docs/fake-runner.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Fake runner epic", description: "Adapter."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Fake runner slice", position: 1},
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
          acceptance_criteria: [acceptance_criterion()],
          verification_commands: [command_spec()],
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

    run_prompt =
      Ash.create!(
        RunPrompt,
        %{
          slice_id: slice.id,
          brief_id: brief.id,
          context_pack_id: context_pack.id,
          template_version: "implementation-prompt@1",
          body: "Write deterministic fake output.",
          body_sha256: digest("fake-prompt"),
          output_schema_version: "conveyor.agent_output@1"
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
          trace_id: "trace-fake"
        },
        domain: Factory
      )

    agent_session =
      Ash.create!(
        AgentSession,
        %{
          run_attempt_id: run_attempt.id,
          run_prompt_id: run_prompt.id,
          agent_profile_id: Ash.UUID.generate(),
          role: :implementer,
          base_commit: base_commit,
          status: :running
        },
        domain: Factory
      )

    %{
      adapter_name: "fake",
      agent_session: agent_session,
      blob_root: blob_root,
      policy: policy(),
      run_attempt: run_attempt,
      run_prompt: run_prompt,
      workspace: %{path: workspace_path, base_commit: base_commit}
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

  defp policy do
    %Policy{
      name: "implement",
      profile: :implement,
      allowlist: ["fake"],
      denylist: [],
      env_policy: %{"allowlist" => []},
      network_policy: %{"default" => "none"},
      budget_policy: %{},
      autonomy_ceiling: 2
    }
  end

  defp run_spec_attrs(slice_id, base_commit) do
    run_spec_sha256 = digest("run-spec-fake")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/fake.json",
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
            "kind" => "implementer",
            "input" => %{"run_spec_sha256" => run_spec_sha256},
            "output" => %{"run_spec_sha256" => run_spec_sha256}
          }
        ]
      },
      station_plan_sha256: digest("station-plan"),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "implement",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp acceptance_criterion do
    %{
      "id" => "AC-FAKE-001",
      "text" => "Fake runner produces deterministic output.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-FAKE-001"],
      "required_test_refs" => ["test/conveyor/agent_runner_fake_test.exs"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp command_spec do
    %{
      "key" => "fake-test",
      "argv" => ["mix", "test", "test/conveyor/agent_runner_fake_test.exs"],
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

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
