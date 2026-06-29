defmodule Conveyor.Planning.PlanFoundry.PlanPrompt do
  @moduledoc """
  Pure plan-drafting prompt build/parse shared by every `Drafter` backend (ADR-27).

  Drafting a `conveyor.plan@1` is the same task regardless of which agent backend
  produces the completion, so the two pure halves live here:

    1. `build_prompt/1` — a versioned prompt instructing the agent to emit a
       `conveyor.plan@1` JSON object (with the project's key conventions and the
       separation-of-duties framing).
    2. `parse_plan/1` — parse the agent's response (raw or fenced JSON) into a
       contract map.

  The determinism boundary holds: a drafter only produces a *draft*; the
  deterministic critic/audit and human approval in `PlanFoundry` gate it, and the
  downstream implementer is a third actor.
  """

  @prompt_version "plan-drafter@1"

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
end
