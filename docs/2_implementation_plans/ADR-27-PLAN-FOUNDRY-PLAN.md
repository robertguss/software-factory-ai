# ADR-27 — Plan Foundry: implementation plan (in-factory plan authoring)

> **Status:** `interrogation_questions/1` + the deterministic `draft/2` spine
> (drafter → `StructuralAudit` → interrogation) implemented + green via an
> injectable `Drafter` seam; the live `CodexDrafter` is the next slice (decided:
> agent-drafted). **Spec:** `docs/adrs/adr-27-in-factory-plan-authoring.md`.
> **Bead:** `software-factory-ai-dr1m.5`. **Date:** 2026-06-20.

## 1. Goal

Invert the planning contract. Today the operator hand-authors a finished
`conveyor.plan@1`. The Plan Foundry takes a **paragraph of intent**, drafts the
plan with the existing contract-forge machinery, runs the 10-lens critic
adversarially against its own draft, and **interrogates the operator only on the
genuine ambiguities** the compiler cannot resolve — then hands a `handoff_ready`
plan to the existing approval checkpoint. This is the single biggest solo-leverage
change: it moves the operator out of authoring and into stating intent +
approving.

Why ADR-27 is the right one to build first of the five: it is **upstream** of the
runtime loop and **collision-free** — it touches `ContractForge`,
`ContractCritic`, `Readiness`, and the planning compiler, none of which the
`codex/handoff-full-implementation` branch is churning. The loop-coupled ADRs
(23/24/25/26) must wait for that branch to merge; this one need not.

## 2. The pipeline (and the real modules each stage drives)

```
intent (String)
  │
  ▼  draft
ContractForge.ContractAuthor.materialize/1   →  per-slice AgentBrief contracts
  │                                              (status, contract, falsifier_seeds, findings)
  ▼  decompose / lower
Planning.DecompositionSelection.select/1     →  chosen candidate
Planning.WorkGraphLowering.lower/2           →  conveyor.work_graph@2 (epics/slices/deps)
  │
  ▼  critique (adversarial, different actor)
ContractCritic.Lenses.review/1               →  %{overall_status: :passed | :challenged,
  │                                               lens_results, disagreements}
  ▼  readiness
Readiness.check/2                            →  %Result{status: :ready | :needs_clarification
  │                                               | :too_large | :blocked, findings}
  ▼  interrogate (THE FIRST BUILT SLICE)
PlanFoundry.interrogation_questions/1        →  minimal, deduped operator questions
  │
  ▼  audit
Planning.StructuralAudit.audit/1             →  handoff_ready verdict (the SAME bar
                                                 as human-authored plans)
  ▼
{:ok, plan} | {:needs_clarification, [question]} | {:error, term}
```

**Separation of duties (the safety argument, non-negotiable):** the *drafter*
(contract forge), the *critic* (contract critic — a distinct actor), and the
*implementer* (downstream, a third actor) are separate; no actor authors and then
implements against its own contract, and **the human still approves**. Decision
6d (Test Architect) and ADR-19 (compiler-owned falsifier seeds) are unchanged —
`ContractAuthor.materialize/1` already emits `falsifier_seeds` independently of
any implementer.

## 3. Public API

```elixir
@spec draft(String.t(), keyword()) ::
        {:ok, map()}                          # a handoff_ready plan contract
        | {:needs_clarification, [question()]} # operator must answer first
        | {:error, term()}

@type question :: %{id: String.t(), prompt: String.t()}
@spec interrogation_questions([map()]) :: [question()]   # pure; BUILT
```

## 4. What's built now (the kick-off)

`PlanFoundry.interrogation_questions/1` — the pure heart of "interrogate only on
genuine ambiguity." It takes the union of `Readiness` `:needs_clarification`
findings and `ContractCritic` challenged-lens findings and produces a **minimal,
deduplicated, stably-ordered** question list for the operator. Pure and
deterministic, so the question set is reproducible and reviewable. Tested green in
`test/conveyor/planning/plan_foundry_test.exs`.

This is the right first slice because it is (a) pure and collision-free, (b) the
distinctive value of ADR-27 (keeping the operator's question budget small), and
(c) the contract every later stage feeds into.

## 5. What's built vs. staged

**Built (deterministic, green):** `draft/2` drives drafter → `StructuralAudit`
→ interrogation. The drafter is an **injectable `Drafter` behaviour**
(`lib/conveyor/planning/plan_foundry/drafter.ex`) — the one non-deterministic
actor, isolated so the orchestration is pure and testable without a live agent.
`draft/2` returns `{:ok, plan}` when the draft is structurally clean,
`{:needs_clarification, questions}` when the audit finds gaps, and
`{:error, reason}` on drafter failure. Tests inject a fake drafter.

**CodexDrafter — built (logic complete; one live step remaining).**
`.../codex_drafter.ex` now implements the decided agent-drafted path as three
parts: `build_prompt/1` (versioned `plan-drafter@1` prompt embedding the intent +
`conveyor.plan@1` shape + separation-of-duties framing — pure, tested),
`parse_plan/1` (raw or ```json-fenced response → contract map — pure, tested), and
an **injectable completion** (`opts[:completion]`). `draft_plan/2` composes them;
the whole intent→prompt→completion→parse→audit→interrogation chain is proven
end-to-end via an injected fake completion (`plan_foundry_test.exs`).

**Live completion — WIRED.** `default_completion/2` now drives the real
`codex exec` CLI (read-only sandbox, one-shot, JSONL → final `agent_message`)
behind an injectable `opts[:codex_exec]` seam. The parsing is tested with canned
JSONL; the real call is exercised by a `:live_agent`-tagged smoke test (excluded
by default). The full chain — intent → prompt → codex → parse → audit →
interrogation — is green via the seam, so CI stays deterministic + $0.

**Later slices** (deepen the deterministic gate): add the 10-lens
`ContractCritic` and the full DB-backed `plan_audit` / `handoff_ready` bar to the
gate alongside `StructuralAudit`, and event-source the draft + findings so the
intent→plan expansion becomes learnable corpus.

## 6. TDD

- `test/conveyor/planning/plan_foundry_test.exs`
  - `interrogation_questions/1` — **green now** (empty, dedup, stable ids,
    ignores blanks, atom+string keys, purity).
  - `draft/2` — `@tag :skip` RED spec for the orchestration (remove the tag to
    drive each stage).

## 7. Risks

- **Critic calibration on machine-drafted plans.** The critic was built to review
  human plans; its trustworthiness on generated drafts is now first-class and must
  be measured. Mitigation: keep the human approval checkpoint; treat a critic
  `:challenged` as a hard stop into interrogation.
- **A bad auto-plan wastes a run.** Mitigation: the `handoff_ready` bar gates
  execution exactly as today; a plan that can't reach it is returned with its
  blocking findings, never executed.
- **Scope creep.** The Foundry is a real subsystem; keep slices small and pure
  where possible (interrogation first, then one pipeline stage at a time).
