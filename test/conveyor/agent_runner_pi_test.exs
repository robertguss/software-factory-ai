defmodule Conveyor.AgentRunnerPiTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.AgentRunner.Capabilities
  alias Conveyor.AgentRunner.Pi
  alias Conveyor.AgentRunner.RawRunResult
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.ContextPack
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunPrompt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice

  test "declares preferred host-controlled and observe-only Pi profiles" do
    host = Pi.capabilities(:pi_host_controlled_tools)
    observe_only = Pi.capabilities(:pi_in_container_observe_only)

    assert %Capabilities{} = host
    assert host.streaming_events
    assert host.pre_exec_command_policy
    assert host.diff_capture == :git_diff
    assert host.structured_output
    assert Capabilities.autonomy_ceiling(host) == "L2"

    assert observe_only.streaming_events
    refute observe_only.pre_exec_command_policy
    assert observe_only.diff_capture == :git_diff
    assert "L1" == Capabilities.autonomy_ceiling(observe_only)
    assert :no_pre_exec_interception in observe_only.known_limitations
  end

  test "runs Pi RPC client, streams events, and captures a fresh-base diff" do
    workspace_path = git_workspace!("agent-runner-pi")
    base_commit = git!(workspace_path, ["rev-parse", "HEAD"])
    blob_root = temp_dir!("pi-blobs")
    fixture = create_prompt_fixture!(workspace_path, base_commit)
    parent = self()

    rpc_client = fn request, emit ->
      send(parent, {:request, request})

      emit.(%{
        "type" => "session_started",
        "payload" => %{"mode" => "rpc"}
      })

      emit.(%{
        "type" => "message_delta",
        "payload" => %{"text" => "editing sample.txt"}
      })

      File.write!(Path.join(request.workspace_path, "sample.txt"), "changed by pi\n")

      emit.(%{
        "type" => "command_requested",
        "payload" => %{"argv" => ["mix", "test"]}
      })

      {:ok,
       %{
         "session_id" => "pi-session-123",
         "summary" => "Updated sample.txt",
         "messages" => [%{"role" => "assistant", "content" => "done"}],
         "tool_calls" => [%{"name" => "edit", "path" => "sample.txt"}],
         "attempted_commands" => ["mix test"],
         "status" => "succeeded"
       }}
    end

    assert {:ok, %RawRunResult{} = result} =
             Pi.run(
               fixture.run_prompt,
               %{path: workspace_path, base_commit: base_commit},
               policy(),
               agent_session_id: fixture.agent_session.id,
               blob_root: blob_root,
               profile: :pi_host_controlled_tools,
               session_id: "pi-request-1",
               rpc_client: rpc_client
             )

    assert_received {:request, request}
    assert request.adapter == "pi"
    assert request.profile == "pi_host_controlled_tools"
    assert request.prompt == fixture.run_prompt.body
    assert request.workspace_path == workspace_path

    assert result.summary == "Updated sample.txt"
    assert result.attempted_commands == ["mix test"]
    assert result.metadata["adapter"] == "pi"
    assert result.metadata["session_id"] == "pi-session-123"

    diff = BlobStore.read!(result.diff_ref, blob_root: blob_root)
    assert diff =~ "-original"
    assert diff =~ "+changed by pi"

    raw_transcript = BlobStore.read!(result.metadata["raw_transcript_ref"], blob_root: blob_root)
    assert Jason.decode!(raw_transcript)["summary"] == "Updated sample.txt"

    events =
      LedgerEvent
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.agent_session_id == fixture.agent_session.id))
      |> Enum.sort_by(& &1.payload["sequence_no"])

    assert Enum.map(events, & &1.payload["event_type"]) == [
             "session_started",
             "message_delta",
             "command_requested",
             "final_response",
             "session_completed"
           ]

    assert Enum.map(events, & &1.payload["sequence_no"]) == [1, 2, 3, 4, 5]
    assert Enum.all?(events, & &1.payload["raw_ref"])
    assert Enum.all?(events, &(&1.payload["adapter"] == "pi"))

    session =
      AgentSession
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.id == fixture.agent_session.id))

    assert session.adapter_session_id == "pi-session-123"
    assert session.status == :succeeded
    assert session.raw_result_ref == result.metadata["raw_transcript_ref"]
  end

  defp create_prompt_fixture!(workspace_path, base_commit) do
    project =
      Ash.create!(
        Project,
        %{name: "Pi sample", local_path: workspace_path, default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Pi plan",
          intent: "Drive Pi over RPC.",
          source_document: "docs/pi.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Pi epic", description: "Agent adapter."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Pi slice", position: 1}, domain: Factory)

    brief =
      Ash.create!(
        AgentBrief,
        %{
          slice_id: slice.id,
          version: 1,
          current_behavior: "sample.txt says original.",
          desired_behavior: "sample.txt is updated.",
          key_interfaces: ["sample.txt"],
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
          confidence: Decimal.new("0.88"),
          relevant_files: [%{"path" => "sample.txt", "reason" => "Target file."}],
          key_interfaces: ["sample.txt"],
          existing_tests: [],
          risks: [],
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
          body: "Update sample.txt.",
          body_sha256: digest("prompt-body"),
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
          trace_id: "trace-pi"
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

    %{agent_session: agent_session, run_prompt: run_prompt}
  end

  defp git_workspace!(label) do
    path = temp_dir!(label)
    git!(path, ["init", "-b", "main"])
    git!(path, ["config", "user.email", "conveyor@example.test"])
    git!(path, ["config", "user.name", "Conveyor Test"])
    File.write!(Path.join(path, "sample.txt"), "original\n")
    git!(path, ["add", "sample.txt"])
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
      allowlist: ["mix", "git"],
      denylist: ["git reset --hard"],
      env_policy: %{"allowlist" => []},
      network_policy: %{"default" => "none"},
      budget_policy: %{},
      autonomy_ceiling: 2
    }
  end

  defp run_spec_attrs(slice_id, base_commit) do
    run_spec_sha256 = digest("run-spec-pi")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/pi.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: base_commit,
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
      "id" => "AC-PI-001",
      "text" => "Pi edits the workspace and emits events.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-PI-001"],
      "required_test_refs" => ["test/conveyor/agent_runner_pi_test.exs"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp command_spec do
    %{
      "key" => "pi-test",
      "argv" => ["mix", "test"],
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
