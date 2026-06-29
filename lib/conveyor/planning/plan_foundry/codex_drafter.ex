defmodule Conveyor.Planning.PlanFoundry.CodexDrafter do
  @moduledoc """
  Live `Conveyor.Planning.PlanFoundry.Drafter` backed by an agent (ADR-27).

  Plan drafting is a *non-workspace* completion (intent prose → a structured
  `conveyor.plan@1`), so it does not use the workspace-oriented `AgentRunner`. The
  drafter is composed of three parts, the first two pure and fully tested:

    1. `PlanPrompt.build_prompt/1` — a versioned prompt instructing the agent to
       emit a `conveyor.plan@1` JSON object (with the project's key conventions
       and the separation-of-duties framing).
    2. `PlanPrompt.parse_plan/1` — parse the agent's response (raw or fenced JSON)
       into a contract map.
    3. an injectable **completion** function (`opts[:completion]`) that turns the
       prompt into text. Tests inject a fake; the production default calls the live
       agent.

  Parts 1–2 are shared by every `Drafter` backend, so they live in
  `Conveyor.Planning.PlanFoundry.PlanPrompt`; this drafter only owns the
  completion seam.

  The determinism boundary holds: this drafter only produces a *draft*; the
  deterministic critic/audit and human approval in `PlanFoundry` gate it, and the
  downstream implementer is a third actor.

  ## Live completion (wired)

  `default_completion/2` drives the real `codex exec` CLI in a **read-only**
  sandbox (no file edits — we only want the model's text), one-shot, JSONL output,
  extracting the final `agent_message`. Like `Conveyor.AgentRunner.Codex`, the CLI
  call is an injectable seam (`opts[:codex_exec]`) so the parsing logic is tested
  with canned JSONL and CI stays deterministic + $0; the real path is exercised
  only by a `:live_agent`-tagged test.
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
    exec = Keyword.get(opts, :codex_exec, &codex_exec/2)

    case exec.(prompt, opts) do
      {stdout, _exit_code} when is_binary(stdout) ->
        case final_message(stdout) do
          "" -> {:error, :codex_empty_response}
          text -> {:ok, text}
        end

      other ->
        {:error, {:codex_exec_failed, other}}
    end
  end

  # One-shot Codex completion: read-only sandbox (no edits — we only want text),
  # JSONL output. stdin is closed via an sh wrapper because `codex exec` otherwise
  # blocks reading stdin (same gotcha as Conveyor.AgentRunner.Codex). No shell
  # injection: codex + args are positional params ($0/$@), never interpolated.
  defp codex_exec(prompt, opts) do
    cd = Keyword.get(opts, :codex_cd, System.tmp_dir!())

    args =
      [
        "exec",
        "--cd",
        cd,
        "--sandbox",
        "read-only",
        "--json",
        "--ephemeral",
        "--skip-git-repo-check"
      ] ++
        model_args(opts) ++ [prompt]

    System.cmd("/bin/sh", ["-c", ~s(exec "$0" "$@" </dev/null), "codex" | args],
      stderr_to_stdout: true
    )
  end

  defp model_args(opts) do
    case Keyword.get(opts, :codex_model) do
      nil -> []
      model -> ["-m", model]
    end
  end

  # Extract the last assistant `agent_message` text from Codex's JSONL stream.
  defp final_message(stdout) do
    stdout
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Jason.decode(line) do
        {:ok, map} -> [map]
        _other -> []
      end
    end)
    |> Enum.filter(&(&1["type"] in ["item.started", "item.completed"]))
    |> Enum.map(& &1["item"])
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&(&1["type"] == "agent_message"))
    |> List.last()
    |> case do
      nil -> ""
      item -> item["text"] || ""
    end
  end
end
