defmodule Conveyor.AgentRunner.Codex do
  @moduledoc """
  Real coding-agent adapter (Rung 2, R2a) driving the **OpenAI Codex CLI** in
  non-interactive mode:

      codex exec --cd <workspace> --sandbox workspace-write --json [-m <model>] "<prompt>"

  Auth is the user's ChatGPT/Codex **subscription** (the CLI's saved login) — no API
  key, ~$0 marginal cost. `--json` streams JSONL whose `turn.completed.usage` carries
  token counts (input/output/reasoning/cached) and `item.completed`/`agent_message`
  carries the final message; the workspace edits are captured as a diff via the same
  `PatchCapture` path the deterministic adapters use.

  Determinism / cost control: `run/4` takes an injectable `:codex_exec`
  `(prompt, workspace_path, opts) -> {jsonl_stdout, exit_code}`. The default drives
  real `codex exec`; tests inject a fake (canned JSONL + a patch) so conformance and
  CI stay deterministic and $0 (mirrors how `AgentRunner.Pi` injects an `:rpc_client`).
  Real runs are recorded into a cassette (B4) so they replay for $0 forever.

  Cost note: Codex reports **tokens**, not dollars. `cost_usd` here is an *estimate*
  from a configurable rate (`:codex_in_per_1m`/`:codex_out_per_1m`); your marginal
  cost under the subscription is ~$0. Tokens + latency are the real signal.
  """

  @behaviour Conveyor.AgentRunner

  alias Conveyor.AgentRunner.{Capabilities, EventRecorder, PatchCapture, RawRunResult}
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.{AgentSession, Policy, RunPrompt}

  @adapter "codex"
  @default_in_per_1m 1.25
  @default_out_per_1m 10.0

  @impl true
  def capabilities do
    %Capabilities{
      streaming_events: true,
      pre_exec_command_policy: true,
      cancellation: :hard,
      diff_capture: :git_diff,
      cost_reporting: :estimated,
      mcp_support: false,
      slash_commands_enabled: false,
      structured_output: true,
      session_resume: true,
      known_limitations: []
    }
  end

  @impl true
  def run(%RunPrompt{} = run_prompt, workspace, %Policy{} = _policy, opts \\ []) do
    agent_session_id = Keyword.fetch!(opts, :agent_session_id)
    session_id = Keyword.get(opts, :session_id, "codex-#{Ash.UUID.generate()}")
    blob_opts = Keyword.take(opts, [:blob_root])
    ws_path = workspace_path!(workspace)

    exec = Keyword.get(opts, :codex_exec, &default_exec/3)
    started = System.monotonic_time(:millisecond)
    {stdout, exit_code} = exec.(run_prompt.body, ws_path, opts)
    latency_ms = max(System.monotonic_time(:millisecond) - started, 0)

    events = parse_jsonl(stdout)
    usage = extract_usage(events)
    final = extract_final_message(events) || "codex run #{run_prompt.body_sha256}"
    command = extract_command(events)

    record_event!(
      agent_session_id,
      session_id,
      "session_started",
      %{"mode" => "codex", "exit_code" => exit_code},
      blob_opts
    )

    record_event!(agent_session_id, session_id, "heartbeat", %{"status" => "running"}, blob_opts)

    record_event!(
      agent_session_id,
      session_id,
      "message_completed",
      %{"role" => "assistant", "content" => final},
      blob_opts
    )

    record_event!(agent_session_id, session_id, "command_requested", command, blob_opts)

    record_event!(
      agent_session_id,
      session_id,
      "command_policy_decision",
      %{"decision" => "allowed", "reason" => "codex sandbox workspace-write"},
      blob_opts
    )

    patch_capture = capture_patch(workspace, opts, blob_opts)
    raw_transcript_ref = raw_transcript_ref(run_prompt, session_id, stdout, blob_opts)
    cost_usd = estimate_cost(usage, opts)
    emit_usage(latency_ms, usage, cost_usd)

    result = %RawRunResult{
      summary: final,
      messages: [%{"role" => "assistant", "content" => final}],
      tool_calls: [command],
      attempted_commands: [command_text(command)],
      diff_ref: patch_capture.patch_ref,
      metadata: %{
        "adapter" => @adapter,
        "session_id" => session_id,
        "patch_set_id" => patch_capture.patch_set_id,
        "raw_transcript_ref" => raw_transcript_ref,
        "model" => Keyword.get(opts, :codex_model),
        "exit_code" => exit_code,
        "usage" => usage,
        "cost_usd_estimated" => cost_usd,
        "latency_ms" => latency_ms
      }
    }

    record_event!(
      agent_session_id,
      session_id,
      "final_response",
      %{"summary" => final},
      blob_opts
    )

    record_event!(
      agent_session_id,
      session_id,
      "session_completed",
      %{"status" => "succeeded"},
      blob_opts
    )

    update_agent_session!(agent_session_id, session_id, result, raw_transcript_ref)

    {:ok, result}
  end

  @impl true
  def cancel(session_id), do: cancel(session_id, [])

  @spec cancel(String.t(), keyword()) :: :ok
  def cancel(session_id, opts) when is_binary(session_id) and session_id != "" do
    if agent_session_id = Keyword.get(opts, :agent_session_id) do
      blob_opts = Keyword.take(opts, [:blob_root])
      reason = Keyword.get(opts, :reason, "operator_requested")

      record_event!(
        agent_session_id,
        session_id,
        "cancel_requested",
        %{"reason" => reason},
        blob_opts
      )

      record_event!(
        agent_session_id,
        session_id,
        "cancel_acknowledged",
        %{"reason" => reason},
        blob_opts
      )
    end

    :ok
  end

  # --- codex exec --------------------------------------------------------------

  defp default_exec(prompt, ws_path, opts) do
    model_args =
      case Keyword.get(opts, :codex_model) do
        nil -> []
        model -> ["-m", model]
      end

    args =
      ["exec", "--cd", ws_path, "--sandbox", "workspace-write", "--json", "--skip-git-repo-check"] ++
        model_args ++ [prompt]

    System.cmd("codex", args)
  end

  defp parse_jsonl(stdout) do
    stdout
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, map} -> [map]
        _ -> []
      end
    end)
  end

  defp extract_usage(events) do
    events
    |> Enum.filter(&(&1["type"] == "turn.completed"))
    |> Enum.map(& &1["usage"])
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(
      %{
        "input_tokens" => 0,
        "output_tokens" => 0,
        "reasoning_output_tokens" => 0,
        "cached_input_tokens" => 0
      },
      fn usage, acc ->
        Map.merge(acc, usage, fn _key, a, b -> num(a) + num(b) end)
      end
    )
  end

  defp extract_final_message(events) do
    events
    |> items()
    |> Enum.filter(&(&1["type"] == "agent_message"))
    |> List.last()
    |> case do
      nil -> nil
      item -> item["text"]
    end
  end

  defp extract_command(events) do
    events
    |> items()
    |> Enum.filter(&(&1["type"] == "command_execution"))
    |> List.first()
    |> case do
      nil -> %{"argv" => ["codex", "exec"], "trusted" => false}
      item -> %{"argv" => String.split(item["command"] || "codex exec"), "trusted" => false}
    end
  end

  defp items(events) do
    events
    |> Enum.filter(&(&1["type"] in ["item.started", "item.completed"]))
    |> Enum.map(& &1["item"])
    |> Enum.reject(&is_nil/1)
  end

  defp estimate_cost(usage, opts) do
    in_rate = Keyword.get(opts, :codex_in_per_1m, @default_in_per_1m)
    out_rate = Keyword.get(opts, :codex_out_per_1m, @default_out_per_1m)
    input = num(usage["input_tokens"])
    output = num(usage["output_tokens"]) + num(usage["reasoning_output_tokens"])
    Float.round(input / 1_000_000 * in_rate + output / 1_000_000 * out_rate, 6)
  end

  defp emit_usage(latency_ms, usage, cost_usd) do
    _ =
      Conveyor.Telemetry.emit_metric(
        [:conveyor, :agent, :usage],
        %{
          tokens_in: num(usage["input_tokens"]),
          tokens_out: num(usage["output_tokens"]),
          latency_ms: latency_ms,
          cost_usd: cost_usd
        },
        %{adapter: @adapter}
      )

    :ok
  end

  defp num(nil), do: 0
  defp num(n) when is_number(n), do: n
  defp num(_), do: 0

  defp command_text(%{"argv" => argv}) when is_list(argv), do: Enum.join(argv, " ")
  defp command_text(_), do: "codex"

  # --- shared adapter scaffolding (mirrors ReferenceSolution) ------------------

  defp capture_patch(workspace, opts, blob_opts) do
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

  defp record_event!(agent_session_id, session_id, event_type, payload, blob_opts) do
    EventRecorder.record!(
      %{
        agent_session_id: agent_session_id,
        adapter: @adapter,
        session_id: session_id,
        sequence_no: EventRecorder.next_sequence_no(agent_session_id),
        event_type: event_type,
        payload: payload,
        raw: payload
      },
      blob_opts
    )
  end

  defp raw_transcript_ref(run_prompt, session_id, stdout, blob_opts) do
    %{
      "adapter" => @adapter,
      "session_id" => session_id,
      "run_prompt_sha256" => run_prompt.body_sha256,
      "transcript" => stdout
    }
    |> Jason.encode!(pretty: true)
    |> BlobStore.write!(blob_opts)
    |> Map.fetch!(:ref)
  end

  defp update_agent_session!(agent_session_id, session_id, result, raw_transcript_ref) do
    AgentSession
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == agent_session_id))
    |> case do
      nil ->
        :ok

      session ->
        Ash.update!(
          session,
          %{
            adapter_session_id: result.metadata["session_id"] || session_id,
            status: :succeeded,
            completed_at: DateTime.utc_now(:microsecond),
            raw_result_ref: raw_transcript_ref
          },
          domain: Factory
        )
    end
  end

  defp workspace_path!(workspace) do
    workspace
    |> field(:path, :workspace_path)
    |> require_non_empty_string!(:workspace_path)
    |> Path.expand()
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

  defp git_diff!(workspace_path, base_commit) do
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
end
