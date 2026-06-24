defmodule Conveyor.Planning.Author do
  @moduledoc """
  ADR-27 (M5) — the core of `mix conveyor.author`: turn a paragraph of intent into a
  drafted `conveyor.plan@1` via `Conveyor.Planning.PlanFoundry.draft/2`.

  This is the factory's missing front door — `PlanFoundry`'s first non-test caller.
  It drives the deterministic spine (an injectable `Drafter` -> `StructuralAudit` ->
  interrogation), so it is exercised with a canned drafter and needs no live agent.

  ## What it does NOT do (yet)

  `PlanFoundry.draft/2` returns a *structurally audited* draft, not a fully
  schema-valid, runnable `conveyor.plan@1` (slice decomposition + schema completion is
  the next M5 slice — the content-aware `Decomposer`). So this authors and (optionally)
  writes the draft; it deliberately does NOT hand off to `PlanRunner`. When the audit
  finds gaps, it surfaces the operator questions instead of a plan.
  """

  alias Conveyor.Planning.PlanFoundry

  @type ok :: %{plan: map(), path: String.t() | nil}
  @type result ::
          {:ok, ok()} | {:needs_clarification, [PlanFoundry.question()]} | {:error, term()}

  @doc """
  Author a plan draft from `intent`.

  Options:
    * `:out` — when set, the drafted plan is written there as pretty JSON and the path
      is returned in the result; otherwise no file is written (`path: nil`).
    * `:draft_opts` — keyword list passed straight to `PlanFoundry.draft/2` (e.g.
      `[drafter: MyDrafter]` / `[completion: fn ...]`), so callers and tests can inject
      the drafter and keep the path deterministic.

  Returns `{:ok, %{plan, path}}` for a structurally clean draft,
  `{:needs_clarification, questions}` when the audit needs operator input, and
  `{:error, reason}` for an empty intent or a drafter failure.
  """
  @spec author(String.t(), keyword()) :: result()
  def author(intent, opts \\ []) when is_binary(intent) and is_list(opts) do
    case String.trim(intent) do
      "" -> {:error, :empty_intent}
      trimmed -> draft(trimmed, opts)
    end
  end

  defp draft(intent, opts) do
    case PlanFoundry.draft(intent, Keyword.get(opts, :draft_opts, [])) do
      {:ok, plan} -> {:ok, %{plan: plan, path: maybe_write!(plan, Keyword.get(opts, :out))}}
      {:needs_clarification, questions} -> {:needs_clarification, questions}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_write!(_plan, nil), do: nil

  defp maybe_write!(plan, path) when is_binary(path) do
    File.write!(path, Jason.encode!(plan, pretty: true))
    path
  end
end
