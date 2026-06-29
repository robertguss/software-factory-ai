defmodule Conveyor.AgentRunner.AdapterBase do
  @moduledoc """
  Shared agent-orchestration scaffolding for coding-agent adapters.

  Lifts the adapter-agnostic orchestration that was private to
  `Conveyor.AgentRunner.Codex` — the timeout watchdog, git-diff/patch capture,
  agent-session persistence, and transcript-ref blob writing — into one place so
  every adapter (Codex, Claude Code) reuses it instead of duplicating it. The
  CLI-specific parsing (JSONL/stream-json, usage/cost extraction, arg building)
  stays in each adapter.

  These functions already use the genuinely shared `PatchCapture`/`BlobStore`/
  `AgentSession` paths; they were moved here verbatim, with no behavior change.
  """

  alias Conveyor.AgentRunner.PatchCapture
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession

  # Watchdog timeout exit code: on timeout the run is unblocked and reported as a
  # non-zero (124) run with empty output -> the slice fails its gate and parks/reworks
  # instead of the whole plan hanging forever (M2).
  @agent_timeout_exit_code 124

  # Watchdog around the blocking agent exec. Runs it in a Task; on timeout, brutally
  # shuts the Task down (closing the System.cmd port, which terminates the child) and
  # reports a timeout (empty stdout, exit #{@agent_timeout_exit_code}) so the loop treats
  # the slice as a failed attempt instead of hanging the unattended run.
  def run_with_timeout(exec, prompt, ws_path, opts, timeout_ms) do
    task = Task.async(fn -> exec.(prompt, ws_path, opts) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {stdout, exit_code}} -> {stdout, exit_code}
      _ -> {"", @agent_timeout_exit_code}
    end
  end

  def capture_patch(workspace, opts, blob_opts) do
    case Keyword.get(opts, :run_attempt_id) do
      nil ->
        diff = git_diff!(workspace_path!(workspace), base_commit!(workspace, opts))
        blob = BlobStore.write!(diff, blob_opts)
        %{patch_ref: blob.ref, patch_set_id: nil}

      run_attempt_id ->
        patch_set =
          PatchCapture.capture!(
            workspace,
            blob_opts
            |> Keyword.put(:base_commit, base_commit!(workspace, opts))
            |> Keyword.put(:run_attempt_id, run_attempt_id)
            |> Keyword.put(:agent_session_id, Keyword.get(opts, :agent_session_id))
            |> Keyword.put(:locked_paths, Keyword.get(opts, :locked_paths, []))
          )

        %{patch_ref: patch_set.patch_ref, patch_set_id: patch_set.id}
    end
  end

  def raw_transcript_ref(adapter, run_prompt, session_id, stdout, blob_opts) do
    %{
      "adapter" => adapter,
      "session_id" => session_id,
      "run_prompt_sha256" => run_prompt.body_sha256,
      "transcript" => stdout
    }
    |> Jason.encode!(pretty: true)
    |> BlobStore.write!(blob_opts)
    |> Map.fetch!(:ref)
  end

  def update_agent_session!(agent_session_id, session_id, result, raw_transcript_ref) do
    AgentSession
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == agent_session_id))
    |> case do
      nil ->
        :ok

      session ->
        usage = result.metadata["usage"] || %{}

        Ash.update!(
          session,
          %{
            adapter_session_id: result.metadata["session_id"] || session_id,
            status: :succeeded,
            completed_at: DateTime.utc_now(:microsecond),
            raw_result_ref: raw_transcript_ref,
            # Persist the live token spend (captured but previously dropped) so the
            # agent_session row — not just an ephemeral telemetry metric — carries it.
            tokens:
              num(usage["input_tokens"]) + num(usage["output_tokens"]) +
                num(usage["reasoning_output_tokens"]),
            cost_estimate: result.metadata["cost_usd_estimated"]
          },
          domain: Factory
        )
    end
  end

  def workspace_path!(workspace) do
    workspace
    |> field(:path, :workspace_path)
    |> require_non_empty_string!(:workspace_path)
    |> Path.expand()
  end

  def git_diff!(workspace_path, base_commit) do
    System.cmd("git", ["-C", workspace_path, "add", "--intent-to-add", "--", "."],
      stderr_to_stdout: true
    )

    case System.cmd("git", ["-C", workspace_path, "diff", "--binary", base_commit, "--"],
           stderr_to_stdout: true
         ) do
      {diff, 0} -> diff
      {output, status} -> raise "git diff failed with #{status}: #{output}"
    end
  end

  defp base_commit!(workspace, opts) do
    opts
    |> Keyword.get(:base_commit)
    |> Kernel.||(field(workspace, :base_commit))
    |> require_non_empty_string!(:base_commit)
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(struct, primary, fallback), do: field(struct, primary) || field(struct, fallback)

  defp require_non_empty_string!(value, _field) when is_binary(value) and value != "", do: value

  defp require_non_empty_string!(_value, field),
    do: raise(ArgumentError, "#{field} must be a non-empty string")

  defp num(nil), do: 0
  defp num(n) when is_number(n), do: n
  defp num(_), do: 0
end
