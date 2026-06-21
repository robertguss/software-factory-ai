defmodule Conveyor.Planning.PlanFoundry.CodexDrafter do
  @moduledoc """
  Live `Conveyor.Planning.PlanFoundry.Drafter` backed by an agent (ADR-27).

  Plan drafting is a *non-workspace* completion (intent prose → a structured
  `conveyor.plan@1`), so it does not use the workspace-oriented `AgentRunner`. The
  drafter is composed of three parts, the first two pure and fully tested:

    1. `build_prompt/1` — a versioned prompt instructing the agent to emit a
       `conveyor.plan@1` JSON object (with the project's key conventions and the
       separation-of-duties framing).
    2. `parse_plan/1` — parse the agent's response (raw or fenced JSON) into a
       contract map.
    3. an injectable **completion** function (`opts[:completion]`) that turns the
       prompt into text. Tests inject a fake; the production default calls the live
       agent.

  The determinism boundary holds: this drafter only produces a *draft*; the
  deterministic critic/audit and human approval in `PlanFoundry` gate it, and the
  downstream implementer is a third actor.

  > **Live wiring is the one remaining step:** `default_completion/2` returns
  > `{:error, :codex_completion_unconfigured}` until the real `codex` one-shot
  > completion is wired (CLI specifics + real spend). All drafter *logic* is
  > exercised today via an injected completion.
  """

  @behaviour Conveyor.Planning.PlanFoundry.Drafter

  @prompt_version "plan-drafter@1"

  @impl true
  def draft_plan(intent, opts \\ []) when is_binary(intent) and is_list(opts) do
    completion = Keyword.get(opts, :completion, &default_completion/2)

    with {:ok, text} when is_binary(text) <- completion.(build_prompt(intent), opts),
         {:ok, plan} <- parse_plan(text) do
      {:ok, plan}
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_completion_result, other}}
    end
  end

  @doc "The versioned plan-drafting prompt for an intent. Pure."
  @spec build_prompt(String.t()) :: String.t()
  def build_prompt(intent) do
    """
    [#{@prompt_version}] You are a planning assistant for the Conveyor software
    factory. Turn the INTENT below into a single `conveyor.plan@1` JSON object.

    Output ONLY the JSON (optionally in a ```json fence). The object must have:
      - "schema_version": "conveyor.plan@1"
      - "goal": one sentence.
      - "requirements": [{"key":"REQ-001","text":...}, ...]
      - "acceptance_criteria": [{"key":"AC-001","text":...,
          "requirement_refs":["REQ-001"],"required_test_refs":[...]}, ...]
      - "slices": [{"key":"SLICE-001","title":...}, ...]
      - "non_goals": [...], "decisions": [{"key":"DEC-001","decision":...}]

    Keys match ^[A-Z]+-[0-9]{3}$. Every requirement needs at least one acceptance
    criterion; every acceptance criterion needs a measurable oracle
    (required_test_refs). Do NOT invent scope beyond the intent — prefer fewer,
    crisp requirements. You author the plan only; a separate critic and a human
    review it, and a different implementer builds it.

    INTENT:
    #{intent}
    """
  end

  @doc "Parse an agent response (raw or ```json-fenced) into a contract map. Pure."
  @spec parse_plan(String.t()) :: {:ok, map()} | {:error, term()}
  def parse_plan(text) when is_binary(text) do
    case Jason.decode(extract_json(text)) do
      {:ok, %{} = plan} -> {:ok, plan}
      {:ok, _other} -> {:error, :plan_not_a_map}
      {:error, _reason} -> {:error, :invalid_plan_json}
    end
  end

  defp extract_json(text) do
    case Regex.run(~r/```(?:json)?\s*(.*?)\s*```/s, text) do
      [_full, inner] -> inner
      nil -> String.trim(text)
    end
  end

  defp default_completion(_prompt, _opts), do: {:error, :codex_completion_unconfigured}
end
