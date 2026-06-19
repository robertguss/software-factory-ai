defmodule Conveyor.AgentRunnerDispatchTest do
  use ExUnit.Case, async: true

  alias Conveyor.AgentRunner
  alias Conveyor.AgentRunner.RawRunResult

  defmodule RecordingAdapter do
    @behaviour Conveyor.AgentRunner

    @impl true
    def capabilities do
      %{
        streaming_events: true,
        pre_exec_command_policy: true,
        cancellation: :best_effort,
        diff_capture: :git_diff,
        cost_reporting: :estimated,
        mcp_support: false,
        slash_commands_enabled: false,
        structured_output: true,
        session_resume: false,
        known_limitations: []
      }
    end

    @impl true
    def run(run_prompt, workspace, policy, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:run, run_prompt, workspace, policy, opts})

      {:ok,
       %RawRunResult{
         summary: "adapter completed",
         diff_ref: "blob://diff",
         metadata: %{"adapter" => "recording", "session_id" => "session-1"}
       }}
    end

    @impl true
    def cancel(session_id) do
      send(Process.get(:test_pid), {:cancel, session_id, []})
      :ok
    end

    def cancel(session_id, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:cancel, session_id, opts})
      :ok
    end
  end

  test "runs a selected adapter through the normalized AgentRunner boundary" do
    prompt = %{body: "do the work"}
    workspace = %{path: "/workspace"}
    policy = %{name: "implement"}

    assert {:ok, result} =
             AgentRunner.run(RecordingAdapter, prompt, workspace, policy, test_pid: self())

    assert result.summary == "adapter completed"
    assert result.diff_ref == "blob://diff"
    assert result.metadata["adapter"] == "recording"

    assert_received {:run, ^prompt, ^workspace, ^policy, opts}
    assert opts[:test_pid] == self()
  end

  test "cancels a selected adapter through the normalized AgentRunner boundary" do
    assert :ok = AgentRunner.cancel(RecordingAdapter, "session-1", test_pid: self())
    assert_received {:cancel, "session-1", opts}
    assert opts[:test_pid] == self()
  end
end
