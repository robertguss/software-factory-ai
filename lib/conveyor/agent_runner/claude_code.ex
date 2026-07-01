defmodule Conveyor.AgentRunner.ClaudeCode do
  @moduledoc """
  Real coding-agent adapter driving the **Claude Code CLI** (`claude -p`) in
  non-interactive (print) mode:

      claude -p --output-format stream-json --verbose \
        --permission-mode bypassPermissions --model <model> \
        --fallback-model <cheaper> "<prompt>"

  Auth is the user's Claude **subscription** (the CLI's own saved login) — no API
  key. The agent subprocess never sees `ANTHROPIC_API_KEY` or unrelated host
  secrets: the default exec runs the agent through `Conveyor.AgentRunner.ContainedExec`
  (R11/U8), which starts a fresh, scrubbed container env and only threads the keys
  the declared `%Policy{}` allowlists.

  KTD1 — `--output-format stream-json` (JSONL), not single `json`: a `system`/init
  event, one `assistant` event per turn (text and `tool_use` blocks), then a final
  `result` event carrying the summary text, `total_cost_usd`, `usage`, and
  `is_error`. Parsed line-by-line, skipping undecodable lines, mirroring the Codex
  adapter. `--verbose` is required alongside stream-json in print mode. We do **not**
  set `stderr_to_stdout` on the station exec — merged stderr can splice into the
  `result` line and silently zero usage/cost.

  KTD2 — autonomy via `--permission-mode bypassPermissions` (disables the CLI's
  in-process approval prompts so the agent runs unattended). That flag is **not**
  containment; containment is Conveyor's job (R11/U8). Claude Code refuses
  `bypassPermissions` as root, so the default exec preflights and refuses to run as
  root.

  KTD3 — capabilities are declared honestly (not copied from Codex): cost comes from
  the `result` event (`:provider_reported`), `mcp_support`/`slash_commands_enabled`
  are true, and `pre_exec_command_policy: false` pins `autonomy_ceiling` at L1.

  Determinism / cost control: `run/4` takes an injectable `:claude_code_exec`
  `(prompt, workspace_path, opts) -> {stream_json_stdout, exit_code}`; the default
  drives the real `claude -p`. Tests inject a fake (canned stream-json + a patch) so
  conformance stays deterministic and $0 (mirrors `AgentRunner.Codex`). The
  contained `docker` invocation is a finer seam (`opts[:cmd]`, consumed by
  `ContainedExec`) so arg/boundary building is verifiable without shelling out.
  """

  @behaviour Conveyor.AgentRunner

  alias Conveyor.AgentRunner.{
    AdapterBase,
    Capabilities,
    ContainedExec,
    EventRecorder,
    RawRunResult
  }

  alias Conveyor.Factory.{Policy, RunPrompt}

  @adapter "claude_code"
  @default_model "opus"
  @fallback_model "sonnet"

  # Resolved model default: per-run opts win, then `config :conveyor, :claude_code_model`
  # (e.g. "sonnet" to cut dogfood cost), then the opus code default. KTD6.
  defp default_model, do: Application.get_env(:conveyor, :claude_code_model, @default_model)

  # Watchdog: bound the (blocking) agent shell-out so a hung `claude -p` can't hang an
  # unattended multi-hour run (M2). The shared watchdog reports a timeout as a non-zero
  # (124) run with empty output -> the slice fails its gate and parks/reworks.
  @default_agent_timeout_ms 900_000

  @impl true
  def capabilities do
    %Capabilities{
      streaming_events: true,
      pre_exec_command_policy: false,
      # cancel/1 records intent but cannot guarantee killing an in-flight blocking
      # subprocess on demand (synchronous run, no exposed port handle): best-effort.
      cancellation: :best_effort,
      diff_capture: :git_diff,
      # cost is read from the `result` event's total_cost_usd, not estimated from a
      # token rate. ponytail: open question whether subscription total_cost_usd is
      # API-equivalent pricing (then :estimated) — first pass treats it as reported.
      cost_reporting: :provider_reported,
      mcp_support: true,
      slash_commands_enabled: true,
      structured_output: true,
      session_resume: false,
      known_limitations: []
    }
  end

  @impl true
  def run(%RunPrompt{} = run_prompt, workspace, %Policy{} = policy, opts \\ []) do
    if root_preflight_required?(opts) and root?() do
      {:error,
       {:must_not_run_as_root,
        "Claude Code refuses --permission-mode bypassPermissions as root; run the agent as a non-root user (KTD2/U8)."}}
    else
      # Thread the declared policy down to the contained exec so it enforces the
      # network/env boundary (R11). put_new: a test-injected policy wins.
      do_run(run_prompt, workspace, Keyword.put_new(opts, :policy, policy))
    end
  end

  defp do_run(%RunPrompt{} = run_prompt, workspace, opts) do
    agent_session_id = Keyword.fetch!(opts, :agent_session_id)
    session_id = Keyword.get(opts, :session_id, "claude-code-#{Ash.UUID.generate()}")
    blob_opts = Keyword.take(opts, [:blob_root])
    ws_path = AdapterBase.workspace_path!(workspace)

    exec = Keyword.get(opts, :claude_code_exec, &default_exec/3)
    timeout_ms = Keyword.get(opts, :agent_timeout_ms, @default_agent_timeout_ms)
    started = System.monotonic_time(:millisecond)

    {stdout, exit_code} =
      AdapterBase.run_with_timeout(exec, run_prompt.body, ws_path, opts, timeout_ms)

    latency_ms = max(System.monotonic_time(:millisecond) - started, 0)

    events = parse_stream_json(stdout)
    result_event = extract_result_event(events)
    usage = extract_usage(result_event)
    cost_usd = cost_usd(result_event)
    is_error = result_event != nil and result_event["is_error"] == true
    summary = extract_summary(result_event) || "claude_code run #{run_prompt.body_sha256}"
    tool_calls = extract_tool_uses(events)
    commands = extract_commands(tool_calls)
    command = command_event(commands)

    record_event!(
      agent_session_id,
      session_id,
      "session_started",
      %{"mode" => "claude_code", "exit_code" => exit_code},
      blob_opts
    )

    record_event!(agent_session_id, session_id, "heartbeat", %{"status" => "running"}, blob_opts)

    record_event!(
      agent_session_id,
      session_id,
      "message_completed",
      %{"role" => "assistant", "content" => summary},
      blob_opts
    )

    record_event!(agent_session_id, session_id, "command_requested", command, blob_opts)

    record_event!(
      agent_session_id,
      session_id,
      "command_policy_decision",
      %{"decision" => "allowed", "reason" => "claude bypassPermissions, contained by conveyor"},
      blob_opts
    )

    patch_capture = AdapterBase.capture_patch(workspace, opts, blob_opts)

    raw_transcript_ref =
      AdapterBase.raw_transcript_ref(@adapter, run_prompt, session_id, redact(stdout), blob_opts)

    emit_usage(latency_ms, usage, cost_usd)

    result = %RawRunResult{
      summary: summary,
      messages: [%{"role" => "assistant", "content" => summary}],
      tool_calls: tool_calls,
      attempted_commands: commands,
      diff_ref: patch_capture.patch_ref,
      metadata: %{
        "adapter" => @adapter,
        "session_id" => session_id,
        "patch_set_id" => patch_capture.patch_set_id,
        "raw_transcript_ref" => raw_transcript_ref,
        "model" => Keyword.get(opts, :claude_code_model, default_model()),
        "exit_code" => exit_code,
        "is_error" => is_error,
        "usage" => usage,
        # shared-base persistence key (AdapterBase.update_agent_session!); carries the
        # provider-reported total_cost_usd from the result event.
        "cost_usd_estimated" => cost_usd,
        "latency_ms" => latency_ms
      }
    }

    record_event!(
      agent_session_id,
      session_id,
      "final_response",
      %{"summary" => summary},
      blob_opts
    )

    record_event!(
      agent_session_id,
      session_id,
      "session_completed",
      %{"status" => "succeeded"},
      blob_opts
    )

    AdapterBase.update_agent_session!(agent_session_id, session_id, result, raw_transcript_ref)

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

  # --- claude -p ---------------------------------------------------------------

  # The real station exec routes the agent through Conveyor's containment boundary
  # (R11/U8): the `claude` argv runs inside a hardened container that enforces the
  # declared %Policy{} (network egress, workspace-scoped writes, scrubbed env). The
  # container's --workdir is the workspace mount, so `claude` (no --cd flag) operates
  # on the mounted workspace directly. KTD1: stream-json, no merged stderr.
  defp default_exec(prompt, ws_path, opts) do
    # The fresh, scrubbed container has no saved login; thread the host's subscription
    # credential file so ContainedExec bind-mounts it read-only into the agent HOME.
    opts = Keyword.put_new(opts, :creds_path, claude_credentials_path())
    ContainedExec.run(["claude" | build_args(prompt, opts)], ws_path, opts)
  end

  # Where the `claude` CLI stores its subscription token on the host. Overridable via
  # `config :conveyor, :claude_credentials_path` for non-default homes / CI.
  defp claude_credentials_path do
    Application.get_env(:conveyor, :claude_credentials_path) ||
      Path.expand("~/.claude/.credentials.json")
  end

  defp build_args(prompt, opts) do
    [
      "-p",
      "--output-format",
      "stream-json",
      "--verbose",
      "--permission-mode",
      "bypassPermissions"
    ] ++ model_args(opts) ++ [prompt]
  end

  # `--fallback-model` (KTD6): a throttled subscription run degrades to a cheaper model
  # rather than failing outright.
  defp model_args(opts) do
    [
      "--model",
      Keyword.get(opts, :claude_code_model, default_model()),
      "--fallback-model",
      @fallback_model
    ]
  end

  # Root check only gates the real default exec; an injected exec (tests) bypasses it.
  defp root_preflight_required?(opts), do: not Keyword.has_key?(opts, :claude_code_exec)

  defp root? do
    case System.cmd("id", ["-u"]) do
      {uid, 0} -> String.trim(uid) == "0"
      _ -> false
    end
  end

  # --- stream-json parsing -----------------------------------------------------

  defp parse_stream_json(stdout) do
    stdout
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, map} -> [map]
        _ -> []
      end
    end)
  end

  defp extract_result_event(events) do
    events
    |> Enum.filter(&(&1["type"] == "result"))
    |> List.last()
  end

  defp extract_summary(nil), do: nil
  defp extract_summary(%{"result" => text}) when is_binary(text) and text != "", do: text
  defp extract_summary(_), do: nil

  defp extract_usage(%{"usage" => usage}) when is_map(usage), do: usage
  defp extract_usage(_), do: %{}

  defp cost_usd(%{"total_cost_usd" => cost}) when is_number(cost), do: cost
  defp cost_usd(_), do: 0.0

  defp extract_tool_uses(events) do
    events
    |> Enum.filter(&(&1["type"] == "assistant"))
    |> Enum.flat_map(&content_blocks/1)
    |> Enum.filter(&(&1["type"] == "tool_use"))
    |> Enum.map(fn block -> %{"name" => block["name"], "input" => block["input"] || %{}} end)
  end

  defp content_blocks(%{"message" => %{"content" => content}}) when is_list(content), do: content
  defp content_blocks(_), do: []

  # Bash tool_use carries the executed shell command in input.command.
  defp extract_commands(tool_uses) do
    tool_uses
    |> Enum.filter(&(&1["name"] == "Bash"))
    |> Enum.map(fn %{"input" => input} -> input["command"] end)
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
  end

  defp command_event([cmd | _]), do: %{"argv" => String.split(cmd), "trusted" => false}
  defp command_event([]), do: %{"argv" => ["claude", "-p"], "trusted" => false}

  # Redact known secret shapes before the transcript blob is written, so a leaked key
  # in agent output never lands in evidence.
  defp redact(stdout) do
    stdout
    |> String.replace(~r/sk-[A-Za-z0-9_\-]{6,}/, "sk-[REDACTED]")
    |> String.replace(~r/ANTHROPIC_API_KEY=\S+/, "ANTHROPIC_API_KEY=[REDACTED]")
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

  # --- event recording ---------------------------------------------------------

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
end
