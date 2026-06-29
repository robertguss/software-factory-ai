defmodule Conveyor.Planning.PlanFoundry.ClaudeCodeDrafter do
  @moduledoc """
  Live `Conveyor.Planning.PlanFoundry.Drafter` backed by Claude Code (ADR-27, KTD7).

  Mirrors `Conveyor.Planning.PlanFoundry.CodexDrafter`: plan drafting is a
  *non-workspace* completion (intent prose → a structured `conveyor.plan@1`), so it
  reuses the shared, fully-tested `PlanPrompt.build_prompt/1` + `parse_plan/1` and
  owns only the completion seam.

    1. `PlanPrompt.build_prompt/1` — the versioned prompt (shared).
    2. `PlanPrompt.parse_plan/1` — parse the model's response into a contract map
       (shared).
    3. an injectable **completion** function (`opts[:completion]`) that turns the
       prompt into text. Tests inject a fake; the production default drives `claude`.

  The determinism boundary holds: this drafter only produces a *draft*; the
  deterministic critic/audit and human approval in `PlanFoundry` gate it, and the
  downstream implementer is a third actor.

  ## Live completion (wired)

  `default_completion/2` drives the real `claude` CLI **read-only** via
  `--permission-mode plan --output-format json`, one-shot, in a temp dir (no file
  edits — we only want the model's text). `--output-format json` emits ONE JSON
  object whose `"result"` key holds the model text. The CLI call is an injectable
  seam (`opts[:claude_exec]`) so the parsing logic is tested with canned output and
  CI stays deterministic + $0; the real path is exercised only by a
  `:live_agent`-tagged test.

  The outer-envelope decode is **guarded**: on auth failure / root-refusal / any
  CLI error, `claude` writes non-JSON (or sets `is_error`), so `default_completion`
  returns a structured `{:error, ...}` rather than letting `Jason.decode` raise.
  """

  @behaviour Conveyor.Planning.PlanFoundry.Drafter

  alias Conveyor.Planning.PlanFoundry.PlanPrompt

  @impl true
  def draft_plan(intent, opts \\ []) when is_binary(intent) and is_list(opts) do
    completion = Keyword.get(opts, :completion, &default_completion/2)

    with {:ok, text} when is_binary(text) <- completion.(PlanPrompt.build_prompt(intent), opts),
         {:ok, plan} <- PlanPrompt.parse_plan(text) do
      {:ok, plan}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_completion_result, other}}
    end
  end

  defp default_completion(prompt, opts) do
    exec = Keyword.get(opts, :claude_exec, &claude_exec/2)

    case exec.(prompt, opts) do
      {stdout, exit_code} when is_binary(stdout) ->
        decode_envelope(stdout, exit_code)

      other ->
        {:error, {:claude_exec_failed, other}}
    end
  end

  # Guard the outer envelope (KTD7): `claude --output-format json` writes ONE JSON
  # object whose `.result` holds the model text. Any CLI failure (auth, root-refusal,
  # non-zero exit) means non-JSON stdout or `is_error: true`, so every failure becomes
  # a structured {:error, ...} — Jason.decode must never raise.
  defp decode_envelope(stdout, exit_code) do
    case safe_decode(stdout) do
      {:ok, %{"is_error" => true} = decoded} ->
        {:error, {:claude_exec_failed, decoded}}

      {:ok, %{"result" => result}} when is_binary(result) and exit_code == 0 ->
        case String.trim(result) do
          "" -> {:error, :claude_empty_response}
          _ -> {:ok, result}
        end

      {:ok, decoded} ->
        {:error, {:claude_exec_failed, decoded}}

      :error ->
        {:error, {:claude_exec_failed, stdout}}
    end
  end

  defp safe_decode(stdout) do
    case Jason.decode(stdout) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> :error
    end
  end

  # One-shot Claude completion: read-only via `--permission-mode plan`, single JSON
  # object on stdout. stdin is closed via an sh wrapper so headless `claude` does not
  # block reading stdin. No shell injection: claude + args are positional params
  # ($0/$@), never interpolated.
  defp claude_exec(prompt, opts) do
    cd = Keyword.get(opts, :claude_cd, System.tmp_dir!())

    args =
      ["-p", "--permission-mode", "plan", "--output-format", "json"] ++
        model_args(opts) ++ [prompt]

    System.cmd("/bin/sh", ["-c", ~s(exec "$0" "$@" </dev/null), "claude" | args],
      cd: cd,
      stderr_to_stdout: true
    )
  end

  # Exposed (not private) so the default/override is asserted directly without a
  # live `claude` — `--model opus` unless `opts[:claude_code_model]` overrides.
  @doc false
  def model_args(opts) do
    ["--model", Keyword.get(opts, :claude_code_model, "opus")]
  end
end
