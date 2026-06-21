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

  Built: `interrogation_questions/1` (the pure question reducer) and the
  deterministic `draft/2` spine — draft (via an injectable `Drafter`) -> structural
  audit -> interrogation. The live `CodexDrafter` is the next slice; until it is
  wired, `draft/2` with the default drafter returns `{:error, :not_implemented}`,
  and the orchestration is exercised through an injected drafter.
  """

  alias Conveyor.Planning.StructuralAudit

  @default_drafter Conveyor.Planning.PlanFoundry.CodexDrafter

  @type question :: %{id: String.t(), prompt: String.t()}

  @type draft_result ::
          {:ok, map()}
          | {:needs_clarification, [question()]}
          | {:error, term()}

  @doc """
  Draft a plan from a paragraph of intent.

  Drives the deterministic spine: a `Drafter` (default
  `Conveyor.Planning.PlanFoundry.CodexDrafter`, override with `:drafter`) turns the
  intent into a structured `conveyor.plan@1` map, the pure
  `Conveyor.Planning.StructuralAudit` checks it, and any blocking findings become
  operator questions.

  Returns `{:needs_clarification, questions}` when the audit finds gaps the
  operator must resolve, `{:ok, plan}` when the draft is structurally clean, and
  `{:error, reason}` when the drafter fails or returns a non-plan.
  """
  @spec draft(String.t(), keyword()) :: draft_result()
  def draft(intent, opts \\ []) when is_binary(intent) and is_list(opts) do
    drafter = Keyword.get(opts, :drafter, @default_drafter)

    with {:ok, plan} when is_map(plan) <- drafter.draft_plan(intent, opts) do
      case interrogation_questions(StructuralAudit.audit(plan).findings) do
        [] -> {:ok, plan}
        questions -> {:needs_clarification, questions}
      end
    else
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_drafter_result, other}}
    end
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
