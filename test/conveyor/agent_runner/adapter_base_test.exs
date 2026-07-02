defmodule Conveyor.AgentRunner.AdapterBaseTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.AgentRunner.{AdapterBase, RawRunResult}
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Eval.BridgeFixtures

  @moduletag :eval
  @known_good "samples/tasks_service/.conveyor/canary/known_good.patch"

  # Apply the reference patch into the workspace so there is a real diff to capture.
  defp apply_known_good!(ws_path) do
    patch = Path.expand(@known_good, File.cwd!())

    {_, 0} =
      System.cmd("patch", ["-p3", "-f", "-d", ws_path, "-i", patch], stderr_to_stdout: true)
  end

  describe "run_with_timeout/5 (watchdog)" do
    test "returns the exec result when it finishes within the budget" do
      exec = fn _prompt, _ws, _opts -> {"done", 0} end
      assert AdapterBase.run_with_timeout(exec, "p", "/tmp", [], 1_000) == {"done", 0, nil}
    end

    test "bounds a hung exec: a slow fun returns a timeout (exit 124), never hangs" do
      slow_exec = fn _p, _ws, _o ->
        Process.sleep(60_000)
        {"", 0}
      end

      # A timeout is transient infra: retried at the seam (rt6k.6) then, when exhausted, returned
      # as a typed infra_error (rt6k.7). sleep_fn is stubbed so the backoff does not add wall-clock.
      started = System.monotonic_time(:millisecond)

      assert {"", 124, %{"class" => "timeout", "retries" => 2}} =
               AdapterBase.run_with_timeout(
                 slow_exec,
                 "p",
                 "/tmp",
                 [sleep_fn: fn _ -> :ok end],
                 100
               )

      assert System.monotonic_time(:millisecond) - started < 5_000
    end
  end

  describe "git_diff!/2" do
    test "produces a non-empty diff of workspace edits against a base commit" do
      fixture = BridgeFixtures.sample_fixture!(label: "adapter-base-diff", adapter_name: "codex")
      ws_path = fixture.workspace.path
      apply_known_good!(ws_path)

      diff = AdapterBase.git_diff!(ws_path, fixture.base_commit)

      assert is_binary(diff)
      assert diff =~ "diff --git"
    end
  end

  describe "capture_patch/3" do
    test "with a run_attempt_id captures a patch set (patch_ref + patch_set_id)" do
      fixture =
        BridgeFixtures.sample_fixture!(label: "adapter-base-capture", adapter_name: "codex")

      apply_known_good!(fixture.workspace.path)

      result =
        AdapterBase.capture_patch(
          fixture.workspace,
          [
            run_attempt_id: fixture.run_attempt.id,
            agent_session_id: fixture.agent_session.id,
            base_commit: fixture.base_commit
          ],
          blob_root: fixture.blob_root
        )

      assert is_binary(result.patch_ref)
      refute is_nil(result.patch_set_id)
    end

    test "without a run_attempt_id writes the raw diff to a blob (patch_set_id nil)" do
      fixture = BridgeFixtures.sample_fixture!(label: "adapter-base-blob", adapter_name: "codex")
      apply_known_good!(fixture.workspace.path)

      result =
        AdapterBase.capture_patch(fixture.workspace, [base_commit: fixture.base_commit],
          blob_root: fixture.blob_root
        )

      assert is_nil(result.patch_set_id)
      assert BlobStore.read!(result.patch_ref, blob_root: fixture.blob_root) =~ "diff --git"
    end
  end

  describe "raw_transcript_ref/5" do
    test "writes a JSON transcript blob carrying the adapter name passed in" do
      fixture = BridgeFixtures.sample_fixture!(label: "adapter-base-transcript")

      ref =
        AdapterBase.raw_transcript_ref(
          "claude_code",
          fixture.run_prompt,
          "session-xyz",
          "raw transcript bytes",
          blob_root: fixture.blob_root
        )

      decoded = Jason.decode!(BlobStore.read!(ref, blob_root: fixture.blob_root))
      assert decoded["adapter"] == "claude_code"
      assert decoded["session_id"] == "session-xyz"
      assert decoded["transcript"] == "raw transcript bytes"
      assert decoded["run_prompt_sha256"] == fixture.run_prompt.body_sha256
    end
  end

  describe "update_agent_session!/4" do
    test "persists succeeded status, summed token spend, and cost onto the session row" do
      fixture = BridgeFixtures.sample_fixture!(label: "adapter-base-session")

      result = %RawRunResult{
        summary: "done",
        metadata: %{
          "session_id" => "adapter-session-1",
          "usage" => %{
            "input_tokens" => 1000,
            "output_tokens" => 200,
            "reasoning_output_tokens" => 50
          },
          "cost_usd_estimated" => 0.0042
        }
      }

      AdapterBase.update_agent_session!(
        fixture.agent_session.id,
        "session-fallback",
        result,
        "transcript-ref"
      )

      session =
        Conveyor.Factory.AgentSession
        |> Ash.read!(domain: Conveyor.Factory)
        |> Enum.find(&(&1.id == fixture.agent_session.id))

      assert session.status == :succeeded
      assert session.adapter_session_id == "adapter-session-1"
      assert session.raw_result_ref == "transcript-ref"
      assert session.tokens == 1250
      refute is_nil(session.cost_estimate)
    end
  end
end
