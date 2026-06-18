defmodule Conveyor.AgentRunnerConformance do
  @moduledoc false

  import ExUnit.Assertions

  alias Conveyor.AgentRunner.Capabilities
  alias Conveyor.AgentRunner.RawRunResult
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.PatchSet

  def assert_adapter_conforms!(adapter, fixture, opts \\ []) do
    capabilities = Capabilities.new!(adapter.capabilities())

    assert capabilities.streaming_events
    assert capabilities.structured_output
    assert capabilities.diff_capture == :git_diff

    assert {:ok, %RawRunResult{} = result} =
             adapter.run(
               fixture.run_prompt,
               fixture.workspace,
               fixture.policy,
               Keyword.merge(
                 [
                   agent_session_id: fixture.agent_session.id,
                   run_attempt_id: fixture.run_attempt.id,
                   blob_root: fixture.blob_root,
                   session_id: "#{fixture.adapter_name}-conformance"
                 ],
                 opts
               )
             )

    assert result.summary != ""
    assert result.diff_ref
    assert BlobStore.read!(result.diff_ref, blob_root: fixture.blob_root) =~ "diff --git"

    assert result.metadata["adapter"] == fixture.adapter_name
    assert result.metadata["patch_set_id"]

    patch_set =
      PatchSet
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.id == result.metadata["patch_set_id"]))

    assert patch_set
    assert patch_set.patch_ref == result.diff_ref
    assert patch_set.applies_cleanly

    events = agent_events(fixture.agent_session.id)
    sequence_numbers = Enum.map(events, & &1.payload["sequence_no"])
    assert sequence_numbers == Enum.to_list(1..length(events))

    event_types = Enum.map(events, & &1.payload["event_type"])

    for event_type <- [
          "session_started",
          "heartbeat",
          "message_completed",
          "command_requested",
          "command_policy_decision",
          "final_response",
          "session_completed"
        ] do
      assert event_type in event_types
    end

    assert Enum.all?(events, & &1.payload["raw_ref"])

    assert :ok =
             adapter.cancel("#{fixture.adapter_name}-conformance",
               agent_session_id: fixture.agent_session.id,
               blob_root: fixture.blob_root,
               reason: "conformance"
             )

    cancel_events =
      fixture.agent_session.id
      |> agent_events()
      |> Enum.take(-2)
      |> Enum.map(& &1.payload["event_type"])

    assert cancel_events == ["cancel_requested", "cancel_acknowledged"]

    result
  end

  def assert_malformed_output_is_structured!(adapter, fixture, opts \\ []) do
    assert {:error, finding} =
             adapter.run(
               fixture.run_prompt,
               fixture.workspace,
               fixture.policy,
               Keyword.merge(
                 [
                   agent_session_id: fixture.agent_session.id,
                   blob_root: fixture.blob_root,
                   session_id: "#{fixture.adapter_name}-malformed",
                   malformed_output?: true
                 ],
                 opts
               )
             )

    assert finding["category"] == "malformed_output"
    assert finding["severity"] == "blocking"

    assert fixture.agent_session.id
           |> agent_events()
           |> Enum.any?(&(&1.payload["event_type"] == "adapter_error"))
  end

  defp agent_events(agent_session_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.agent_session_id == agent_session_id and &1.type == "agent.event"))
    |> Enum.sort_by(& &1.payload["sequence_no"])
  end
end
