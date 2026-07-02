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

  require Logger

  alias Conveyor.AgentRunner.FailureClass
  alias Conveyor.AgentRunner.PatchCapture
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession

  # Watchdog timeout exit code: on timeout the run is unblocked and reported as a
  # non-zero (124) run with empty output -> the slice fails its gate and parks/reworks
  # instead of the whole plan hanging forever (M2).
  @agent_timeout_exit_code 124

  # rt6k.6: bounded backoff-retry for TRANSIENT infra failures (5xx/429/refused/timeout).
  # Infra outcomes are retried in-place — absorbed at this seam, so they never return to the
  # AttemptLoop as a consumed attempt. WORK outcomes (the agent ran, even badly) return
  # immediately. Small bounded backoff keeps total added wall-clock well under the run reaper.
  @infra_retry_cap 2
  @base_backoff_ms 500

  # Watchdog around the blocking agent exec. Runs it in a Task; on timeout, brutally
  # shuts the Task down (closing the System.cmd port, which terminates the child) and
  # reports a timeout (empty stdout, exit #{@agent_timeout_exit_code}) so the loop treats
  # the slice as a failed attempt instead of hanging the unattended run. Transient infra
  # failures are retried here (rt6k.6) rather than burning an attempt.
  def run_with_timeout(exec, prompt, ws_path, opts, timeout_ms) do
    run_with_infra_retry(exec, prompt, ws_path, opts, timeout_ms, 0)
  end

  defp run_with_infra_retry(exec, prompt, ws_path, opts, timeout_ms, retry_index) do
    {stdout, exit_code} = run_once_with_timeout(exec, prompt, ws_path, opts, timeout_ms)
    cap = Keyword.get(opts, :infra_retry_cap, @infra_retry_cap)

    case FailureClass.classify(%{exit_code: exit_code, output: stdout}) do
      {:infra, class} when retry_index < cap ->
        delay = backoff_ms(retry_index)

        Logger.warning(
          "agent infra retry: class=#{class} adapter=#{adapter_label(opts)} " <>
            "retry=#{retry_index + 1}/#{cap} backoff_ms=#{delay} exit_code=#{exit_code}"
        )

        sleep(delay, opts)
        run_with_infra_retry(exec, prompt, ws_path, opts, timeout_ms, retry_index + 1)

      {:infra, class} ->
        Logger.warning(
          "agent infra retry cap exhausted: class=#{class} adapter=#{adapter_label(opts)} " <>
            "after #{cap} retries — failing the attempt (infra_error)"
        )

        {stdout, exit_code}

      :work ->
        {stdout, exit_code}
    end
  end

  defp run_once_with_timeout(exec, prompt, ws_path, opts, timeout_ms) do
    task = Task.async(fn -> exec.(prompt, ws_path, opts) end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {stdout, exit_code}} -> {stdout, exit_code}
      _ -> {"", @agent_timeout_exit_code}
    end
  end

  # Exponential backoff with a fixed jitter fraction (no Date/rand dependency in the hot path
  # of tests — the sleep fn is injectable via opts[:sleep_fn] so tests run instantly).
  defp backoff_ms(retry_index), do: @base_backoff_ms * Integer.pow(2, retry_index)

  defp sleep(delay, opts), do: Keyword.get(opts, :sleep_fn, &Process.sleep/1).(delay)

  defp adapter_label(opts), do: Keyword.get(opts, :adapter, "agent")

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
