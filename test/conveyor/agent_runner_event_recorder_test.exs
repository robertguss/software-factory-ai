defmodule Conveyor.AgentRunnerEventRecorderTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.AgentRunner.EventRecorder
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Agent event sample", local_path: "/tmp/agent-event", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Agent event plan",
          intent: "Normalize adapter events.",
          source_document: "docs/agent-event.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Agent event epic", description: "Events."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Agent event slice", position: 1},
        domain: Factory
      )

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

    attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: "abc123",
          status: :running,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-agent-event"
        },
        domain: Factory
      )

    session =
      Ash.create!(
        AgentSession,
        %{
          run_attempt_id: attempt.id,
          run_prompt_id: Ash.UUID.generate(),
          agent_profile_id: Ash.UUID.generate(),
          adapter_session_id: "adapter-session-1",
          role: :implementer,
          base_commit: "abc123",
          status: :running
        },
        domain: Factory
      )

    %{
      attempt: attempt,
      blob_root: temp_dir!("agent-event-blobs"),
      run_spec: run_spec,
      session: session
    }
  end

  test "records normalized agent events with content-addressed raw output", %{
    attempt: attempt,
    blob_root: blob_root,
    run_spec: run_spec,
    session: session
  } do
    event =
      EventRecorder.record!(
        %{
          agent_session_id: session.id,
          adapter: "fake",
          sequence_no: 1,
          event_type: "session_started",
          payload: %{"role" => "implementer"},
          raw: %{"transcript" => "session opened"},
          occurred_at: ~U[2026-01-02 03:04:05Z]
        },
        blob_root: blob_root
      )

    assert event.type == "agent.event"
    assert event.run_attempt_id == attempt.id
    assert event.agent_session_id == session.id
    assert event.payload["event_version"] == "conveyor.agent_event@1"
    assert event.payload["run_spec_sha256"] == run_spec.run_spec_sha256
    assert event.payload["adapter"] == "fake"
    assert event.payload["session_id"] == "adapter-session-1"
    assert event.payload["sequence_no"] == 1
    assert event.payload["event_type"] == "session_started"
    assert event.payload["occurred_at"] == "2026-01-02T03:04:05Z"

    raw = event.payload["raw_ref"] |> BlobStore.read!(blob_root: blob_root) |> Jason.decode!()
    assert raw["transcript"] == "session opened"
  end

  test "sequence numbers are monotonic and idempotent", %{session: session} do
    first =
      EventRecorder.record!(%{
        agent_session_id: session.id,
        adapter: "fake",
        sequence_no: 1,
        event_type: "session_started",
        payload: %{"first" => true}
      })

    duplicate =
      EventRecorder.record!(%{
        agent_session_id: session.id,
        adapter: "fake",
        sequence_no: 1,
        event_type: "heartbeat",
        payload: %{"changed" => true}
      })

    assert duplicate.id == first.id
    assert duplicate.payload["event_type"] == "session_started"

    EventRecorder.record!(%{
      agent_session_id: session.id,
      adapter: "fake",
      sequence_no: 3,
      event_type: "heartbeat",
      payload: %{}
    })

    assert_raise ArgumentError, ~r/must be greater than previous 3/, fn ->
      EventRecorder.record!(%{
        agent_session_id: session.id,
        adapter: "fake",
        sequence_no: 2,
        event_type: "message_delta",
        payload: %{}
      })
    end

    assert length(Ash.read!(LedgerEvent, domain: Factory)) == 2
  end

  test "rejects unknown event types", %{session: session} do
    assert_raise ArgumentError, ~r/unknown agent event_type/, fn ->
      EventRecorder.record!(%{
        agent_session_id: session.id,
        adapter: "fake",
        sequence_no: 1,
        event_type: "slash_command_policy_bypass",
        payload: %{}
      })
    end
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec-agent-event")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/agent-event.json",
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

  defp temp_dir!(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
