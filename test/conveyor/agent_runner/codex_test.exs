defmodule Conveyor.AgentRunner.CodexTest do
  use Conveyor.DataCase, async: false

  import Conveyor.AgentRunnerConformance

  alias Conveyor.AgentRunner.Codex
  alias Conveyor.Eval.BridgeFixtures

  @moduletag :eval
  @known_good "samples/tasks_service/.conveyor/canary/known_good.patch"

  # An injected exec that applies the reference patch and returns canned JSONL —
  # deterministic and $0 (no real codex spend), exercising the adapter's parsing,
  # event, and diff-capture logic.
  defp fake_exec do
    fn _prompt, ws_path, _opts ->
      patch = Path.expand(@known_good, File.cwd!())

      {_, 0} =
        System.cmd("patch", ["-p3", "-f", "-d", ws_path, "-i", patch], stderr_to_stdout: true)

      jsonl =
        Enum.join(
          [
            ~s({"type":"thread.started","thread_id":"t1"}),
            ~s({"type":"turn.started"}),
            ~s({"type":"item.completed","item":{"id":"c1","type":"command_execution","command":"pytest -q","status":"completed"}}),
            ~s({"type":"item.completed","item":{"id":"a1","type":"agent_message","text":"Applied the reference solution."}}),
            ~s({"type":"turn.completed","usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":200,"reasoning_output_tokens":50}})
          ],
          "\n"
        )

      {jsonl, 0}
    end
  end

  test "Codex adapter satisfies the conformance suite with an injected exec (deterministic, $0)" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "codex-conformance",
        adapter_name: "codex",
        patch_ref: @known_good
      )

    result = assert_adapter_conforms!(Codex, fixture, codex_exec: fake_exec())

    assert result.metadata["adapter"] == "codex"
    assert result.summary == "Applied the reference solution."
    assert result.metadata["usage"]["input_tokens"] == 1000
    assert result.metadata["usage"]["output_tokens"] == 200
    assert result.metadata["usage"]["reasoning_output_tokens"] == 50
    assert is_integer(result.metadata["latency_ms"])
    assert result.metadata["cost_usd_estimated"] >= 0.0
  end

  test "usage parsing sums turns and tolerates missing fields" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "codex-usage",
        adapter_name: "codex",
        patch_ref: @known_good
      )

    exec = fn _p, ws, _o ->
      patch = Path.expand(@known_good, File.cwd!())
      {_, 0} = System.cmd("patch", ["-p3", "-f", "-d", ws, "-i", patch], stderr_to_stdout: true)

      {~s({"type":"turn.completed","usage":{"input_tokens":5}}\n{"type":"turn.completed","usage":{"input_tokens":7,"output_tokens":3}}),
       0}
    end

    {:ok, result} =
      Codex.run(fixture.run_prompt, fixture.workspace, fixture.policy,
        agent_session_id: fixture.agent_session.id,
        run_attempt_id: fixture.run_attempt.id,
        blob_root: fixture.blob_root,
        codex_exec: exec
      )

    assert result.metadata["usage"]["input_tokens"] == 12
    assert result.metadata["usage"]["output_tokens"] == 3
  end
end
