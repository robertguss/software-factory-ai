defmodule Conveyor.Planning.PlanFoundry do
  @moduledoc """
  ADR-27 — in-factory plan authoring ("Plan Foundry").

  Turns a short statement of intent into a critiqued, `handoff_ready`
  `conveyor.plan@1` by driving the existing machinery: `ContractForge` drafts,
  `ContractCritic` challenges (a distinct actor), `Readiness`/the compiler surface
  genuine ambiguities, and the operator is interrogated only on those before
  approving.

  Separation of duties is preserved: the drafter, the critic, and the downstream
  implementer are three distinct actors, and the human still approves. ADR-19
  (compiler-owned falsifier seeds) and decision 6d (Test Architect) are unchanged.

  Plan: docs/2_implementation_plans/ADR-27-PLAN-FOUNDRY-PLAN.md

  ## Status

  Kicked off: `interrogation_questions/1` (the pure heart) is implemented and
  tested. `draft/2` and the per-stage adapters are staged (see the module plan and
  the `@tag :skip` specs in `test/conveyor/planning/plan_foundry_test.exs`).
  """

  @type question :: %{id: String.t(), prompt: String.t()}

  @type draft_result ::
          {:ok, map()}
          | {:needs_clarification, [question()]}
          | {:error, term()}

  @doc """
  Draft a `handoff_ready` plan from a paragraph of intent.

  Returns `{:needs_clarification, questions}` when the critic/readiness pass finds
  genuine ambiguity the operator must resolve first; `{:ok, plan}` when the draft
  reaches the `handoff_ready` bar; `{:error, reason}` otherwise.

  NOT YET IMPLEMENTED — see the module plan.
  """
  @spec draft(String.t(), keyword()) :: draft_result()
  def draft(intent, opts \\ []) when is_binary(intent) and is_list(opts) do
    raise "Conveyor.Planning.PlanFoundry.draft/2 not implemented (ADR-27 / dr1m.5)"
  end

  @doc """
  Reduce a set of readiness/critic findings to the minimal list of questions the
  operator must answer.

  Pure and deterministic. Accepts findings with either atom (`:message`) or string
  (`"message"`) keys — matching `Conveyor.Readiness` findings (`%{code:, message:}`)
  and `Conveyor.ContractCritic` lens findings respectively. Blank/missing messages
  are dropped; identical prompts are de-duplicated; the remaining questions are
  numbered `Q1, Q2, ...` in first-seen order so the set is stable and reviewable.
  """
  @spec interrogation_questions([map()]) :: [question()]
  def interrogation_questions(findings) when is_list(findings) do
    findings
    |> Enum.map(&prompt_of/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.with_index(1)
    |> Enum.map(fn {prompt, index} -> %{id: "Q#{index}", prompt: prompt} end)
  end

  # Extract a clarification prompt from a finding, normalizing key style and
  # whitespace. Anything without a usable message collapses to "" and is dropped.
  defp prompt_of(%{message: message}) when is_binary(message), do: String.trim(message)
  defp prompt_of(%{"message" => message}) when is_binary(message), do: String.trim(message)
  defp prompt_of(%{prompt: prompt}) when is_binary(prompt), do: String.trim(prompt)
  defp prompt_of(%{"prompt" => prompt}) when is_binary(prompt), do: String.trim(prompt)
  defp prompt_of(_finding), do: ""
end
