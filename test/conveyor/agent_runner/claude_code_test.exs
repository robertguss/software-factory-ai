defmodule Conveyor.AgentRunner.ClaudeCodeTest do
  use Conveyor.DataCase, async: false

  import Conveyor.AgentRunnerConformance

  alias Conveyor.AgentRunner.{Capabilities, ClaudeCode}
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Eval.BridgeFixtures
  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent

  @moduletag :eval
  @known_good "samples/tasks_service/.conveyor/canary/known_good.patch"
  @fixture "test/support/claude_code/stream_json_station_run.jsonl"

  defp fixture_jsonl, do: File.read!(@fixture)

  # An injected exec that applies the reference patch and returns the captured
  # stream-json transcript — deterministic and $0 (no real `claude` spend).
  defp fake_exec do
    fn _prompt, ws_path, _opts ->
      patch = Path.expand(@known_good, File.cwd!())

      {_, 0} =
        System.cmd("patch", ["-p3", "-f", "-d", ws_path, "-i", patch], stderr_to_stdout: true)

      {fixture_jsonl(), 0}
    end
  end

  defp agent_events(agent_session_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.agent_session_id == agent_session_id and &1.type == "agent.event"))
    |> Enum.sort_by(& &1.payload["sequence_no"])
  end

  test "ClaudeCode satisfies the conformance suite with an injected exec (deterministic, $0)" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "cc-conformance",
        adapter_name: "claude_code",
        patch_ref: @known_good
      )

    result = assert_adapter_conforms!(ClaudeCode, fixture, claude_code_exec: fake_exec())

    assert result.metadata["adapter"] == "claude_code"
    assert result.summary == "Implemented the change; tests pass."

    # the live token spend is PERSISTED onto the agent_session row (21000 + 350 = 21350).
    session =
      Conveyor.Factory.AgentSession
      |> Ash.read!(domain: Conveyor.Factory)
      |> Enum.find(&(&1.id == fixture.agent_session.id))

    assert session.tokens == 21_350
    refute is_nil(session.cost_estimate)
  end

  test "usage/cost come from the result event; commands from assistant tool_use events" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "cc-usage",
        adapter_name: "claude_code",
        patch_ref: @known_good
      )

    {:ok, result} =
      ClaudeCode.run(fixture.run_prompt, fixture.workspace, fixture.policy,
        agent_session_id: fixture.agent_session.id,
        run_attempt_id: fixture.run_attempt.id,
        blob_root: fixture.blob_root,
        claude_code_exec: fake_exec()
      )

    assert result.metadata["usage"]["input_tokens"] == 21_000
    assert result.metadata["usage"]["output_tokens"] == 350
    assert result.metadata["cost_usd_estimated"] == 0.42
    assert result.metadata["is_error"] == false
    assert "mix test test/foo_test.exs" in result.attempted_commands
    assert Enum.any?(result.tool_calls, &(&1["name"] == "Bash"))
  end

  test "default model is opus; claude_code_model overrides it (argv captured via injected cmd)" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "cc-model",
        adapter_name: "claude_code",
        patch_ref: @known_good
      )

    test_pid = self()

    capture_cmd = fn _sh, sh_args, _cmd_opts ->
      send(test_pid, {:argv, sh_args})
      {fixture_jsonl(), 0}
    end

    {:ok, _} =
      ClaudeCode.run(fixture.run_prompt, fixture.workspace, fixture.policy,
        agent_session_id: fixture.agent_session.id,
        blob_root: fixture.blob_root,
        claude_code_cmd: capture_cmd
      )

    assert_receive {:argv, default_argv}
    assert "--model" in default_argv
    assert "opus" in default_argv
    assert "--fallback-model" in default_argv

    {:ok, _} =
      ClaudeCode.run(fixture.run_prompt, fixture.workspace, fixture.policy,
        agent_session_id: fixture.agent_session.id,
        blob_root: fixture.blob_root,
        claude_code_model: "sonnet",
        claude_code_cmd: capture_cmd
      )

    assert_receive {:argv, sonnet_argv}
    assert "sonnet" in sonnet_argv
    refute "opus" in sonnet_argv
  end

  test "empty/garbled stdout falls back to run_prompt.body_sha256 without crashing" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "cc-garbled",
        adapter_name: "claude_code",
        patch_ref: @known_good
      )

    garbled = fn _p, _ws, _o -> {"not json\n{bad json", 0} end

    {:ok, result} =
      ClaudeCode.run(fixture.run_prompt, fixture.workspace, fixture.policy,
        agent_session_id: fixture.agent_session.id,
        blob_root: fixture.blob_root,
        claude_code_exec: garbled
      )

    assert result.summary =~ fixture.run_prompt.body_sha256
  end

  test "watchdog bounds a hung exec (M2): a slow agent returns a timeout, never hangs the run" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "cc-watchdog",
        adapter_name: "claude_code",
        patch_ref: @known_good
      )

    slow_exec = fn _p, _ws, _o ->
      Process.sleep(60_000)
      {"", 0}
    end

    {:ok, result} =
      ClaudeCode.run(fixture.run_prompt, fixture.workspace, fixture.policy,
        agent_session_id: fixture.agent_session.id,
        blob_root: fixture.blob_root,
        claude_code_exec: slow_exec,
        agent_timeout_ms: 100
      )

    assert result.metadata["exit_code"] == 124
    assert result.metadata["latency_ms"] < 5_000
  end

  test "the agent subprocess receives an allowlisted env with ANTHROPIC_API_KEY scrubbed" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "cc-env",
        adapter_name: "claude_code",
        patch_ref: @known_good
      )

    System.put_env("ANTHROPIC_API_KEY", "sk-ant-should-not-leak")
    on_exit(fn -> System.delete_env("ANTHROPIC_API_KEY") end)

    test_pid = self()

    capture_cmd = fn _sh, _sh_args, cmd_opts ->
      send(test_pid, {:env, cmd_opts[:env]})
      {fixture_jsonl(), 0}
    end

    {:ok, _} =
      ClaudeCode.run(fixture.run_prompt, fixture.workspace, fixture.policy,
        agent_session_id: fixture.agent_session.id,
        blob_root: fixture.blob_root,
        claude_code_cmd: capture_cmd
      )

    assert_receive {:env, env}
    # ANTHROPIC_API_KEY is actively unset (nil), never passed through with its value.
    refute Enum.any?(env, fn {k, v} -> k == "ANTHROPIC_API_KEY" and not is_nil(v) end)
    assert {"ANTHROPIC_API_KEY", nil} in env
    # the allowlist still threads PATH so the CLI is resolvable.
    assert Enum.any?(env, fn {k, v} -> k == "PATH" and is_binary(v) end)
  end

  test "known secret patterns are redacted before the transcript blob is written" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "cc-redact",
        adapter_name: "claude_code",
        patch_ref: @known_good
      )

    leaky = fn _p, _ws, _o ->
      {fixture_jsonl() <>
         "\nleaked sk-ant-api03-SECRETVALUE1234567890 and ANTHROPIC_API_KEY=sk-ant-secretvalue\n",
       0}
    end

    {:ok, result} =
      ClaudeCode.run(fixture.run_prompt, fixture.workspace, fixture.policy,
        agent_session_id: fixture.agent_session.id,
        blob_root: fixture.blob_root,
        claude_code_exec: leaky
      )

    transcript =
      BlobStore.read!(result.metadata["raw_transcript_ref"], blob_root: fixture.blob_root)

    refute transcript =~ "SECRETVALUE1234567890"
    refute transcript =~ "secretvalue"
    assert transcript =~ "[REDACTED]"
  end

  test "capabilities/0 returns the honest struct (KTD3): pre_exec false pins autonomy at L1" do
    caps = Capabilities.new!(ClaudeCode.capabilities())

    assert caps.streaming_events
    assert caps.structured_output
    assert caps.diff_capture == :git_diff
    assert caps.cost_reporting == :provider_reported
    assert caps.mcp_support
    assert caps.slash_commands_enabled
    refute caps.pre_exec_command_policy
    refute caps.session_resume
    assert Capabilities.autonomy_ceiling(caps) == "L1"
  end

  test "cancel/1 records cancel_requested/cancel_acknowledged and returns :ok" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "cc-cancel",
        adapter_name: "claude_code",
        patch_ref: @known_good
      )

    assert :ok =
             ClaudeCode.cancel("claude-code-cancel",
               agent_session_id: fixture.agent_session.id,
               blob_root: fixture.blob_root,
               reason: "operator_requested"
             )

    types =
      fixture.agent_session.id
      |> agent_events()
      |> Enum.map(& &1.payload["event_type"])

    assert types == ["cancel_requested", "cancel_acknowledged"]
  end

  @tag :live_agent
  @tag timeout: 600_000
  test "real claude -p completes a station run end-to-end against the workspace" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "cc-live",
        adapter_name: "claude_code",
        patch_ref: @known_good,
        prompt_body: "Reply with a one-line summary of this repository. Do not edit any files."
      )

    {:ok, result} =
      ClaudeCode.run(fixture.run_prompt, fixture.workspace, fixture.policy,
        agent_session_id: fixture.agent_session.id,
        run_attempt_id: fixture.run_attempt.id,
        blob_root: fixture.blob_root
      )

    assert result.metadata["adapter"] == "claude_code"
    assert result.summary != ""
    assert result.diff_ref
  end
end
