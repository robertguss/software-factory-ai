# Conveyor — Phase 0 + Phase 1 Implementation Plan

> **Purpose of this document.** A comprehensive, standalone implementation plan
> for the first two phases of Conveyor — the foundations (Phase 0) and the
> single-Slice "tracer bullet" (Phase 1). It is written to be diffed against
> competing plans from other models and synthesized into a hybrid "best of all
> worlds" plan.
>
> **Status:** design / pre-implementation. Companion to `docs/BRAINSTORM.md`
> (the living strategy doc with the full architecture and decision log).

---

## 0. One-paragraph context (for readers who haven't seen the brainstorm)

**Conveyor** is an AI-first software factory on the Elixir/BEAM. A human does
the research and planning and hands Conveyor **one finished plan**; Conveyor
decomposes it into a dependency-ordered, contract-bearing work-graph and runs a
fleet of AI coding agents in **isolated containers** to implement it — recording
every run as immutable evidence, gating output through a tiered verification
pyramid, merging through a queue, and learning from the results. It is the
autonomous, BEAM-native successor to _Conveyor AI_ (a Go CLI that proved the
single-run loop). The guiding bets: **isolation over coordination**, **the
verification gate is the human's stand-in**, and a **deterministic conductor
orchestrating stochastic agents**. This document covers only the first two
phases; the full phased roadmap (Phases 2–8: decomposition, parallel fleet,
verification pyramid, self-healing, economic governor, learning loop, throughput
upgrades) lives in the brainstorm doc.

---

## 1. Goals & non-goals for Phase 0 + 1

### Goals

1. Stand up the **deterministic Elixir core**: an Ash/Postgres domain, an
   event-sourced ledger, and the Slice lifecycle as a formal state machine.
2. Run **exactly one Slice end-to-end** against a sterile sample Python app,
   through every station of the loop:
   `readiness → context scout → run prompt → Pi implementer (in Docker) → evidence → deterministic run-check → reviewer-on-dossier → gate → manual merge.`
3. **Prove the loop feels right** on a real change, and — critically — **prove
   the gate can be made honest** via a gate-canary harness that measures false
   negatives _now_, not in a later phase.
4. Establish the **`AgentRunner` adapter** so Pi can later be swapped for Cursor
   CLI, Codex, Claude Code, etc.

### Non-goals (explicitly deferred)

- **No parallelism / Dispatcher / WorkerPool fleet** — Phase 3. Phase 1 runs one
  Slice.
- **No automated decomposition or multi-model planning** — Phase 2. In Phase 1
  the human hand-authors the single Plan/Epic/Slice/Brief (including the failing
  tests).
- **No merge queue** — Phase 3. Merge is a manual human action in Phase 1.
- **No autonomous self-healing, economic governor, or learning loop** — Phases
  5–7. (Retry is manual; cost is observed, not governed.)
- **No interface-stub parallelism** — Phase 8. Strict deps only (and there's
  only one Slice anyway).

### Definition of done for Phase 1

A human seeds one Plan with one Slice + Agent Brief + failing pytest cases,
presses a single "run" action, and Conveyor autonomously drives the Slice
through every station, produces a Run Dossier + machine manifest + ledger
timeline visible in a LiveView, the gate (independently re-run by the conductor)
passes, the gate-canary proves the gate rejects an injected bug, and the human
merges manually. The entire run is replayable from the event log.

---

## 2. Tech stack & assumptions

| Concern                        | Choice                                                                                           |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| Language / runtime             | Elixir ~1.17+, Erlang/OTP 26+                                                                    |
| Web / dashboard                | Phoenix 1.8.x + LiveView (minimal run viewer)                                                    |
| Domain & persistence           | Ash 3.x + AshPostgres, `ash_state_machine`, Postgres 16                                          |
| Background / durable jobs      | Oban                                                                                             |
| Agent isolation                | Docker (one container per agent run)                                                             |
| First implementer agent        | **Pi** (`pi.dev`) driven over **RPC (JSON/stdin-stdout)** via a BEAM Port; OpenAI/Codex provider |
| Deterministic code-health gate | **CodeScent** invoked via its CLI by the conductor (Python supported)                            |
| Sample testbed                 | a small **FastAPI** "tasks" service with a pytest suite, in its own disposable git repo          |

**Assumptions:** Docker is installed and the BEAM node can reach the Docker
daemon; Pi is installed (in the container image) and an OpenAI/Codex provider
credential is available; CodeScent is installed and runnable on the changed
repo; the sample repo starts from a known, committed base commit.

---

## 3. Architecture

### 3.1 The determinism boundary (the load-bearing principle)

Inherited from Conveyor AI's ADR 0004, restated for the BEAM:

> **The deterministic BEAM conductor owns** paths, state transitions, dependency
> integrity, validation, prompt assembly, recorded evidence, and the gate
> verdict's _mechanical_ parts. **Agents own** drafting, implementation, and
> _judgment_ (review). When an agent supplies judgment (a reviewer verdict),
> that verdict is **recorded and itself validated** by the conductor. The
> conductor may orchestrate agents but is never the source of truth for
> generated content — and agents are never the source of truth for whether
> something passed.

Concretely in Phase 1: **the agent may run tests while implementing, but the
conductor independently re-runs the gate** (pytest + CodeScent) in a clean
container against the produced diff. Trust comes from the conductor's
independent re-run, never the agent's self-report.

### 3.2 Ash domain (Phase 0 lays all of it; Phase 1 exercises a subset)

Resources (AshPostgres-backed). Embedded types in _italics_.

- **`Plan`** — `id, title, intent, source_document, status`
- **`Epic`** — `id, plan_id, title, description, risk, approval_status, status`
- **`Slice`** — `id, epic_id, title, position, risk, state` _(state machine,
  §3.3)_
- **`AgentBrief`** (the contract) —
  `id, slice_id, version, current_behavior, desired_behavior, key_interfaces, out_of_scope, risk,`
  _acceptance_criteria[] {text, kind∈behavioral/test, required_test_ref?}_
- **`ContextPack`** — `id, slice_id, scout_version, confidence,`
  _relevant_files[] {path, reason}, key_interfaces[], risks[],
  suggested_validation[]_
- **`RunPrompt`** —
  `id, slice_id, brief_id, context_pack_id, template_version, body, memory_refs[], policy_refs[]`
- **`AgentRun`** —
  `id, slice_id, run_prompt_id, agent, model, base_commit, head_commit, workspace_state, started_at, completed_at, status∈running/succeeded/failed, outcome∈none/needs-rework/accepted`
- **`Evidence`** (1:1 with AgentRun) — _changed_files[], commands[] {cmd,
  status∈ passed/failed/skipped, output_ref}, acceptance_results[] {text,
  status∈passed/failed/ skipped/missing, reason?, evidence_refs[]}, risks[],
  summary_
- **`Review`** —
  `id, agent_run_id, reviewer, model, reviewed_at, decision∈accepted/ needs-rework/rejected, recommendation∈merge/rework/ask-human/archive, summary,`
  _findings[] {severity∈blocking/warning/note, message}, checks[]_
- **`GateResult`** — `id, agent_run_id, level∈slice, passed::bool,` _stages[]
  {name∈ build/tests/codescent/run-check/reviewer, status, detail}_
- **`LedgerEvent`** (append-only, the event source) —
  `id, slice_id, agent_run_id?, type, payload::map, occurred_at`
- **`Memory`** / **`Policy`** — created as resources in Phase 0 but **stubs**,
  unused in Phase 1 (wired up in Phase 7 / Phase 4 respectively).

> **Open decision (flagged, not blocking):** whether these are _only_ in
> Postgres or are also materialized as repo-native `.conveyor/*.md|json`
> artifacts (Conveyor AI's local-first ethos). Phase 0/1 recommendation:
> **Postgres is the source of truth**, and the Run Dossier + manifest are _also_
> written to disk per run for inspectability — a read-only projection, not a
> second source of truth.

### 3.3 The Slice state machine (`ash_state_machine`)

```
drafted ─▶ approved ─▶ ready ─▶ scouting ─▶ scouted ─▶ prompt_built
   ▲                                                        │
   │                                                        ▼
 (Phase 2                                              implementing
  auto-                                                     │
  decomp)                                                   ▼
                                                   evidence_recorded
                                                            │
                                                            ▼
        done ◀── integrated ◀── gated ◀────────────────────┘
       (human                  (passed)
        merge)
   off-ramps from any agent station: needs_rework · parked · failed
```

In Phase 1 the human authors a Slice that begins at **`approved`** (no
auto-decomposition yet). Every transition emits a `LedgerEvent`. Guards are
deterministic; `ash_state_machine` makes illegal transitions impossible.

```elixir
defmodule Conveyor.Work.Slice do
  use Ash.Resource,
    domain: Conveyor.Work,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshStateMachine]

  state_machine do
    initial_states [:drafted, :approved]
    default_initial_state :drafted

    transitions do
      transition :approve,        from: :drafted,            to: :approved
      transition :mark_ready,     from: :approved,           to: :ready
      transition :start_scout,    from: :ready,              to: :scouting
      transition :scouted,        from: :scouting,           to: :scouted
      transition :build_prompt,   from: :scouted,            to: :prompt_built
      transition :implement,      from: :prompt_built,       to: :implementing
      transition :record,         from: :implementing,       to: :evidence_recorded
      transition :gate,           from: :evidence_recorded,  to: :gated
      transition :integrate,      from: :gated,              to: :integrated
      transition :complete,       from: :integrated,         to: :done
      # off-ramps
      transition :rework, from: [:gated, :evidence_recorded, :implementing], to: :needs_rework
      transition :park,   from: :*, to: :parked
      transition :fail,   from: :*, to: :failed
    end
  end
end
```

### 3.4 OTP supervision tree (Phase 0/1 shape)

```
Conveyor.Application
├── Conveyor.Repo                         (AshPostgres)
├── Oban                                  (durable jobs)
├── ConveyorWeb.Endpoint                  (Phoenix + LiveView run viewer)
└── Conveyor.Conductor (Supervisor)
    ├── Conveyor.Ledger        (GenServer) — append-only event writer + PubSub fan-out
    └── (per run) Oban worker: Conveyor.Jobs.RunSlice
            └── drives the slice through stations, calling deterministic modules
                and the AgentRunner; each long agent step is its own Oban job so a
                crash/reboot resumes from the last durable station.
```

Phase 1 has **no Dispatcher / WorkerPool / MergeQueue yet** — those arrive in
Phase 3. A single Slice is run by invoking the `RunSlice` Oban job (from a mix
task or a LiveView button). The durable-job design means the self-healing/resume
property exists from day one even though we don't yet automate retries.

### 3.5 The `AgentRunner` adapter + Pi over RPC

```elixir
defmodule Conveyor.AgentRunner do
  @moduledoc "Behaviour every coding-agent backend implements."
  @callback run(run_prompt :: Conveyor.Work.RunPrompt.t(), opts :: keyword()) ::
              {:ok, Conveyor.Work.RawRunResult.t()} | {:error, term()}
end
```

`RawRunResult` = the agent's _reported_ output (messages, tool calls, commands
it ran, final diff). It is **not** trusted evidence — the conductor turns it
into `Evidence` only after independently re-running the gate.

**`Conveyor.AgentRunner.Pi`** implementation:

1. Materialize the sample repo at `base_commit` into a working dir.
2. `docker run` an image containing Pi + the Python toolchain, mounting the
   working dir, launching Pi in **RPC mode** (`pi` JSON protocol over
   stdin/stdout).
3. Open a BEAM `Port` to the container; a small GenServer frames JSON messages
   and implements the request/response RPC handshake.
4. Send the `RunPrompt.body`; stream Pi's events (tool use, edits, command runs)
   into the `Ledger` as they arrive (live LiveView updates).
5. On completion, collect the final diff + the agent's self-reported command
   results into a `RawRunResult` and return.

Pi is chosen because its **RPC/JSON mode gives a clean structured seam** (no TUI
scraping), its **multi-provider** support fronts the OpenAI/Codex subscription
and future model-fit routing, and its **deliberate minimalism** (no sub-agents,
no plan mode, no built-in orchestration) keeps orchestration where it belongs —
in the conductor. Its recommended "run in a container" security model matches
our isolation decision.

### 3.6 Deterministic modules (the conductor's owned logic)

- **`Readiness`** — validates an Agent Brief is complete (current/desired
  behavior present, acceptance criteria concrete & testable, key interfaces
  named, out-of-scope stated, risk set). Returns
  `ready | needs-clarification | needs-context | too-large | blocked`.
- **`ContextScout`** — read-only repo scan (ripgrep + a read-only Pi pass)
  producing a **cited** `ContextPack`. In Phase 1 it may be mostly deterministic
  (rg-driven).
- **`PromptBuilder`** — assembles a **versioned** `RunPrompt` from Brief +
  Context Pack + an explicit output contract. Pure function; unit-tested.
- **`EvidenceRecorder`** — runs the gate commands itself, maps acceptance
  criteria → test results, writes `Evidence`, the `dossier.md`, and the
  `manifest.json`; emits ledger events. Idempotent (regenerating from the same
  run updates, never duplicates).
- **`RunCheck`** — deterministic validation that the recorded run is well-formed
  (required fields, enum values, artifact links resolve, dossier/manifest agree
  with evidence). The gate's structural pre-check.
- **`Gate`** — composes stages: `build` (container builds) → `tests` (conductor
  re-runs pytest) → `codescent` (CLI scan, no new findings vs baseline) →
  `run-check` → `reviewer` (verdict == accepted). All-green ⇒ `gated:passed`.

### 3.7 The Reviewer (judgment, recorded)

A **second** Pi invocation (different role, ideally different model) that reads
the **recorded dossier** (not the live session) and returns a structured
`Review` (decision/recommendation/findings). Reviewing recorded evidence makes
the judgment **reproducible**. Ash policies enforce that the reviewer actor ≠
the implementer actor — separation of duties from day one.

### 3.8 Minimal LiveView run viewer

A single LiveView page showing the Slice's current state, the station timeline
(from the ledger), the live agent event stream, the Run Dossier, the Evidence
(acceptance criteria → proof), the Review, the Gate stages, and a **"Merge"
button** for the manual Phase-1 merge. Phoenix PubSub pushes ledger events live.

---

## 4. The literal tracer bullet (walkthrough)

### 4.1 The sample testbed

A disposable git repo: a tiny **FastAPI "tasks" service** — `GET /tasks`,
`POST /tasks`, an in-memory or SQLite store, and a pytest suite. Committed at a
known base commit.

### 4.2 The first Slice (human-authored Agent Brief)

```markdown
## Agent Brief — Add "complete a task" endpoint

Category: enhancement Risk: low Current behavior: Tasks can be created and
listed. There is no way to mark a task complete. Desired behavior: A client can
mark a task complete; completed state is persisted and returned by the list
endpoint. Marking a non-existent task returns 404.

Key interfaces:

- HTTP: `PATCH /tasks/{id}` with body `{"completed": true}` → 200 with the
  updated task.
- The task representation gains a boolean `completed` field (default false).
- `PATCH` on an unknown id → 404 with a clear error body.

Acceptance criteria:

- [ ] `PATCH /tasks/{id}` with `{"completed": true}` returns 200 and the task
      with `completed: true`.
- [ ] The completed state is reflected in `GET /tasks`.
- [ ] `PATCH` on a non-existent id returns 404.
- [ ] Existing create/list behavior is unchanged.

Out of scope:

- Authentication, pagination, un-completing a task, bulk updates.
```

**The human (acting as Test Architect in Phase 1) also commits failing pytest
cases** for each acceptance criterion. The implementer agent must make them pass
and **cannot weaken them** — the conductor re-runs the _original_ tests in the
gate. This is trustworthy agent-TDD: red authored by a different actor, green
delivered by the implementer.

### 4.3 Station-by-station

1. **Seed** — a mix task / LiveView form creates the
   `Plan → Epic → Slice → AgentBrief` (state `approved`) and registers the
   sample repo + base commit.
2. **Readiness** — `Readiness.check/1` confirms the Brief is complete → `ready`.
3. **Scout** — `ContextScout` scans the repo, produces a cited `ContextPack`
   (the router module, the task model, the existing tests) → `scouted`.
4. **Prompt** — `PromptBuilder` emits a versioned `RunPrompt` (Brief + Pack +
   output contract: "report changed files, commands, acceptance status,
   evidence, risks") → `prompt_built`.
5. **Implement** — `AgentRunner.Pi` spins the Docker container, drives Pi over
   RPC against the repo; Pi edits code until the committed tests pass; events
   stream to the ledger → `implementing` → returns `RawRunResult`.
6. **Record** — `EvidenceRecorder` **independently re-runs** pytest + CodeScent
   in a clean container against the diff, maps results to acceptance criteria,
   writes `Evidence` + `dossier.md` + `manifest.json`, emits events; `RunCheck`
   validates → `evidence_recorded`.
7. **Review** — a second Pi role reviews the recorded dossier → structured
   `Review`.
8. **Gate** — `Gate` composes build + tests + codescent + run-check +
   reviewer-accepted. All green → `gated`.
9. **Merge** — human inspects the dossier in LiveView and clicks Merge →
   `integrated` → `done`.

Every step is a `LedgerEvent`; the whole run replays from the log.

---

## 5. Testing strategy (for Conveyor itself)

- **TDD the deterministic core.** `Readiness`, `PromptBuilder`, `RunCheck`,
  `EvidenceRecorder`, `Gate` are pure-ish and unit-tested with ExUnit. These are
  the trust-bearing modules; they get the most coverage.
- **Fake `AgentRunner` for the suite.** Following Conveyor AI's "deterministic
  fake reviewer" pattern, tests use a `Conveyor.AgentRunner.Fake` that returns
  canned `RawRunResult`s. **No live model calls in the default test suite.**
- **Live Pi behind a tagged integration test** (`@tag :live_agent`) run on
  demand.
- **State-machine tests** assert illegal transitions are rejected and each legal
  transition emits the right ledger event.
- **The gate-canary harness is itself a test** (see §6).

---

## 6. Front-loaded gate validation (the recommendation, made concrete)

> **The riskiest assumption in all of Conveyor is that the verification gate can
> be made strong enough to trust unattended.** Everything elegant rests on it.
> If the gate can't be trusted, "autonomous" just means "fast at being wrong."
> So we validate the gate's honesty in Phase 1 — not in a later phase.

**Gate-canary harness (Phase 1 deliverable):**

- Maintain a tiny labeled set of "mutants": versions of the sample solution with
  a known defect injected (e.g., off-by-one, swapped status code, dropped
  persistence, a weakened assertion).
- For each mutant, run it through the **gate only** and assert the gate
  **fails** it.
- Track the **false-negative rate** (mutants the gate wrongly passes). This is
  the first, smallest instance of the Phase-5 "shadow mode."
- A gate that passes a mutant is a **release-blocking bug in Conveyor**,
  surfaced loudly in the LiveView and the test suite.

This gives an early, objective signal on the one thing the whole architecture
depends on, and it seeds the Failure-Taxonomy / eval machinery that Phases 5–7
build on.

---

## 7. Risks & open questions

| Risk / question                                        | Stance                                                                                                            |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| **Gate trustworthiness** (the big one)                 | Front-loaded via §6 gate-canary; measure FN rate from Phase 1.                                                    |
| Pi RPC maturity / protocol churn                       | Contained by the `AgentRunner` adapter + integration tests; Cursor/Codex are fallbacks behind the same behaviour. |
| Docker run latency per Slice                           | Acceptable in Phase 1 (one Slice); revisit pooling/warm containers in Phase 3.                                    |
| Flaky tests corrupting AC→evidence mapping             | Conductor re-runs in a clean container; fl­akes surface as gate noise to fix early.                               |
| Ash learning curve / schema churn                      | Keep resources deep & isolated (Conveyor AI's advice); evolve internal schemas behind stable module APIs.         |
| Artifact storage: Postgres vs repo-native `.conveyor/` | Phase 0/1: Postgres = truth, disk = read-only projection; revisit before Phase 3.                                 |
| Context Scout: deterministic vs agentic                | Phase 1: mostly deterministic (rg); measure context-pack-miss rate before investing in an agentic scout.          |

---

## 8. Milestone / task breakdown with acceptance criteria

### Phase 0 — Foundations

- **P0.1 Project scaffold.** Phoenix+Ash+Oban+Postgres app boots; CI runs
  `mix test`, `mix format --check`, Credo/Dialyzer. _AC:_ `mix test` green on an
  empty suite; app boots; CI passes.
- **P0.2 Ash domain & resources.** All §3.2 resources defined with AshPostgres
  migrations. _AC:_ resources create/read/update via Ash; migrations apply
  cleanly.
- **P0.3 Slice state machine.** `ash_state_machine` per §3.3. _AC:_ legal
  transitions succeed, illegal ones error; each transition writes a
  `LedgerEvent`.
- **P0.4 Event-sourced ledger.** `Ledger` GenServer + append-only resource +
  PubSub. _AC:_ a slice's full history is reconstructable from events;
  subscribers receive live events.
- **P0.5 LiveView skeleton.** Run-viewer page rendering a slice's state + ledger
  timeline. _AC:_ navigating to a seeded slice shows its state and event
  timeline live.

### Phase 1 — Single-Slice tracer bullet

- **P1.1 Sample app + first Brief + failing tests.** FastAPI "tasks" repo at a
  base commit; the §4.2 Brief; committed failing pytest cases. _AC:_ `pytest`
  fails on the new cases, passes on existing ones.
- **P1.2 Readiness gate.** _AC:_ complete Brief → `ready`; a deliberately vague
  Brief → `needs-clarification`/`too-large`.
- **P1.3 Context Scout → Context Pack.** _AC:_ produces a cited pack naming the
  router, model, and existing tests with reasons.
- **P1.4 Run Prompt builder.** _AC:_ deterministic, versioned prompt containing
  Brief + Pack + output contract; snapshot-tested.
- **P1.5 Pi AgentRunner over RPC in Docker.** _AC:_ given a RunPrompt, Pi edits
  the repo in a container and returns a `RawRunResult` with a diff; events
  stream to the ledger.
- **P1.6 Evidence recorder + run-check.** _AC:_ conductor independently re-runs
  pytest + CodeScent, writes `Evidence`+`dossier.md`+`manifest.json`, maps ACs
  to results; run-check rejects malformed records; regeneration is idempotent.
- **P1.7 Reviewer-on-dossier.** _AC:_ a second Pi role returns a schema-valid
  `Review`; malformed review output is rejected; reviewer actor ≠ implementer
  actor (policy-enforced).
- **P1.8 Deterministic Gate + CodeScent stage.** _AC:_ gate is green only when
  build+tests+ codescent+run-check+reviewer all pass; any failing stage blocks.
- **P1.9 Gate-canary harness.** _AC:_ a labeled mutant set runs through the
  gate; every mutant is rejected; false-negative rate is reported; a passed
  mutant fails the suite.
- **P1.10 LiveView run viewer (complete).** _AC:_ shows timeline, live agent
  stream, dossier, evidence, review, gate stages, and a working Merge button.
- **P1.11 End-to-end tracer run.** _AC:_ one human action drives the Slice from
  `approved` to `gated` autonomously; human merges → `done`; the run replays
  from the event log.

---

## 9. What success in Phase 1 teaches us (and unblocks)

- Does the loop **feel right** on a real change? (Qualitative, but decisive.)
- **Can the gate be trusted?** (Quantitative: canary false-negative rate.)
- Is the **Pi/RPC seam** clean enough to scale to a fleet?
- Are the **Ash schemas** the right shape, or do they churn under first contact?

Only once the gate proves honest and the loop proves real do we earn Phase 3's
parallelism — the disciplined path from tracer bullet to autonomous factory.
