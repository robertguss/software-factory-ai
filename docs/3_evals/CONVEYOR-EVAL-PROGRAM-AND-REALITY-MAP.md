# Conveyor — Eval Program & Factory Reality Map

> **Status:** proposal draft (round 1). Not committed; awaiting selection of
> which ideas to build.
>
> **Purpose:** (A) a _state-of-the-factory_ reality map — what actually runs
> end-to-end today vs. what is stubbed/designed-only — derived from a 7-way
> parallel source dive; and (B) the **10 best** measurable-eval ideas (distilled
> from ~100), aimed at one north star — **prove the outcome** (can a human plan
> become correct, verified, working software, and is it better/faster/cheaper
> than vanilla Claude or a human?) — under one constraint: **cheap signal
> first** (low cost, deterministic where possible, CI-friendly, a runnable
> ladder).
>
> **How to read this:** Part I is the ground truth you asked for (you hadn't run
> it). Part II is the eval philosophy and the single metric that matters most.
> Part III is the 10 ideas as structured cards. Part IV is the build ladder &
> recommended first moves. Part V is the headline scorecard. The appendix shows
> the breadth behind the 10.

---

## Part I — State of the Factory (reality map)

**Stack:** Elixir 1.20 / OTP 29, Phoenix, Ash (~50 domain resources), Oban,
Postgres. **Only external service required to boot is Postgres.** No LLM key is
needed anywhere today (there is no live LLM client). `deps/` and `_build/` are
empty in a fresh clone, so the first run needs `mix deps.get` once (network for
hex), then everything is offline.

### What RUNS today — the verification spine (real, deterministic, $0 LLM)

| Capability                                                        | Module(s)                                                                         | Notes                                                                                                                                                                                                                                                                                                                                                |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Conductor loop (per-call, synchronous, DI)                        | `lib/conveyor/run_slice.ex:38` `RunSlice.run!/2`                                  | Reduces over `station_plan["stations"]`, threads output→input. No live driver GenServer; you call it directly.                                                                                                                                                                                                                                       |
| Station wrapper (idempotency, leases, effects, artifacts, ledger) | `lib/conveyor/station.ex`                                                         | Owns the durable side-effects around each station.                                                                                                                                                                                                                                                                                                   |
| **14-stage gate (the "working software" verdict)**                | `lib/conveyor/gate.ex:68`; `gate/stages/*`                                        | `passed? = Enum.all?(stages, &passes?)`. Pure, finding-driven, stable string `rule_key`s. Stages: build_install, run_check, test_execution, acceptance_mapping, code_quality_delta, diff_scope, secret_safety, policy_compliance, contract_lock, canary_freshness, provenance_attestation, observed_risk, workspace_integrity, reviewer_aggregation. |
| Gate finalize + failure classification                            | `lib/conveyor/gate/finalizer.ex:18`                                               | Persists `GateResult`; maps findings → critical / policy_violation / rework.                                                                                                                                                                                                                                                                         |
| **Qualification Battery runner + scorer**                         | `lib/conveyor/jobs/run_battery.ex:11` `RunBattery.run!/3`                         | Pure. Takes a corpus + sampling policy + an **injected `agent_runner` fn**; fans out N samples; classifies failures (`:safety_invariant`, `:quality`). This is a ready-made eval shell.                                                                                                                                                              |
| Exact statistics                                                  | `lib/conveyor/statistics.ex`                                                      | Real Clopper-Pearson (Beta-Binomial) confidence intervals at frozen confidence.                                                                                                                                                                                                                                                                      |
| Live stratified sampling, grant scope                             | `battery/live_sampling.ex`, `qualification/gate.ex`, `qualification/grants.ex:18` | Issues scoped, expiring `QualificationGrant`s; pure functions, end-to-end runnable.                                                                                                                                                                                                                                                                  |
| **Anti-vacuity probes (verifier-of-verifiers)**                   | `lib/conveyor/verification/integrity_sentinel.ex`                                 | 10 probes incl. `base_calibration` (demands a red/failing signal), `falsifier_survival`, `hermeticity`, `source_mutation`, `falsifier_preservation`.                                                                                                                                                                                                 |
| Independent Critic                                                | `lib/conveyor/.../contract_critic/*`                                              | 10 lenses, `CheapestWrong.challenge!`, independence enforcement. Structurally non-authorizing.                                                                                                                                                                                                                                                       |
| Plan Compiler front-half                                          | `lib/conveyor/planning/work_graph_lowering.ex:13`                                 | Emits validated `conveyor.work_graph@2` IR from plan source.                                                                                                                                                                                                                                                                                         |
| Free provenance/correctness oracle                                | `mix conveyor.verify` → `Replay`                                                  | Independent re-projection + `bundle_root_sha256`. Deterministic tamper check on any produced bundle.                                                                                                                                                                                                                                                 |
| Hermetic end-to-end tracer                                        | `lib/conveyor/demo.ex` (`mix conveyor.demo` / `mix conveyor.ci`)                  | Seeds tasks, runs RunSlice, projects a bundle — **but over a fake station** (see below).                                                                                                                                                                                                                                                             |
| Deterministic adapters                                            | `agent_runner/fake.ex` (default), `mock_degraded.ex` (11 failure scenarios)       | Zero spend, no network, no `pi` binary needed.                                                                                                                                                                                                                                                                                                       |

### What is STUBBED / DESIGNED-ONLY — the generative path (the gap)

| Gap                                                               | Evidence                                                                                                                                                                                                  | Consequence                                                                                                                        |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **No bridge: `work_graph` IR → runnable `station_plan`**          | only `station_plan` in `lib/` is the hardcoded seed fixture, `sample_tasks_seed.ex:281`                                                                                                                   | Compiler output and executor input **never meet**.                                                                                 |
| **No station invokes the agent**                                  | every station maps to `FakeRunnerStation`; nothing in `lib/` calls `AgentRunner.run`                                                                                                                      | The agent never runs in production paths.                                                                                          |
| **Agent is "real but dead code," and it's not Claude**            | `agent_runner/pi.ex:138` has Port/RPC/git-diff machinery, default cmd `["pi","rpc","--jsonl"]` (`:197`); only reached from tests via injected `:rpc_client`. No Anthropic/OpenAI client exists in `lib/`. | No live model is wired. A real adapter must be built.                                                                              |
| **Cassette record/replay is coded but UNWIRED**                   | `cassettes.ex`, `cassettes/replay_engine.ex` (4 modes) have **no caller in the run loop**                                                                                                                 | "Replay a real run for $0" is design-only until wired.                                                                             |
| **Budget + Emergency-Stop are pure state machines, not enforced** | `budget_reservations.ex`, `emergency_stop.ex` gate only when a caller invokes them; not intercepting `Pi.run`                                                                                             | They cannot actually _stop_ live spend yet.                                                                                        |
| **ADR-06 unified PolicyDecision/DecisionContract evaluator**      | no `PolicyDecision`/`DecisionContract` module in `lib/`; decisions are per-gate ad hoc                                                                                                                    | Decision-contract defaults live in `docs/policies/decision-contracts.json` (17 keys, fail-closed) but aren't a single runtime API. |
| **Battery corpus is starved of data**                             | `docs/phase-1.5/p15-b1/battery-corpus.json` defines 15 cases incl. **9 adversarial traps**, but only as `artifact://` / `secure-eval://` URIs — **no fixtures on disk**                                   | The scorer is real; it has almost nothing to score.                                                                                |
| **No token/cost or latency capture**                              | not present in `AuthorityEvent` / `EffectReceipt` / `LedgerEvent`                                                                                                                                         | Cost/lift can't be measured until instrumented.                                                                                    |
| **Property-based testing nearly absent**                          | 757 tests, **2 property tests**; StreamData is a dep but unused                                                                                                                                           | The pure compiler/statistics core is under-falsified.                                                                              |

### Gold already on disk (your starter eval corpus)

- **`samples/tasks_service`** — Python 3.13 / FastAPI CRUD with
  `conveyor.plan.yml` (4 reqs, 5 ACs, 1 slice), 8 pytest acceptance tests, and a
  locked test-pack `.conveyor/test-packs/tasks-complete/v1/`.
- **9 labeled canary mutants** — `samples/tasks_service/.conveyor/canary/`:
  `known_good.patch` + 8 defects, each tagged with archetype + expected-catch
  (api_behavior, state_persistence, default_contract, test_integrity,
  policy_violation, risk_classification, prompt_injection×2). **A ready-made
  false-negative / false-positive eval.**
- **`toolchains/sample-python-runner`** — pinned Docker image, `pytest -q`,
  requirements.lock, SBOM. Python-only.
- **`test/fixtures/plan_audit/`** — 8 plan fixtures (good / vague /
  contradictory / missing-ac / …); `test/fixtures/eval_suites/phase1.json` — 5
  named suites.

### The one-sentence reality

> **Conveyor can rigorously _judge_ software it cannot yet _build_.** The trust
> machinery is real and runnable for $0; the plan→agent→artifact path is severed
> at two named seams. Therefore the cheapest, highest-value evals prove the
> judge today, and the act of building the outcome-eval is what bridges the
> seam.

---

## Part II — Eval philosophy

1. **The north star is the outcome, but the gateway metric is the verifier's
   honesty.** You cannot "prove the outcome" with a judge you don't trust. A
   factory that emits a single **false-PASS** (green-lights broken software) is
   worse than useless — it launders bad work as verified. So the program's
   primary vital sign is the **false-PASS rate**, driven toward zero, _before
   and during_ any capability claim.

2. **Climb a ladder; pay for signal once.** Rung 0 proves the parts that already
   run for $0. Rung 1 bridges the seam using _reference solutions and mutants as
   stand-in agents_ — still ~$0. Rung 2 spends metered LLM dollars on real
   outcome + lift, but **records every paid run into a cassette** so the signal
   becomes a free, permanent regression asset. Rung 3 calibrates, aggregates,
   and dogfoods.

3. **Every eval should be adversarial and falsification-first.** Examples that
   pass prove little; the value is in actively searching for the input that
   breaks the claim. Three of the ten are literally adversaries.

4. **The eval harness is also the documentation.** A deterministic, narrated
   replay of "plan → caught-mutant → verdict" is simultaneously a test, a demo,
   and the truest documentation of what the system does.

---

## Part III — The 10 best ideas

Each card: **what it proves · how it runs · spend · effort · rung · payoff · why
it's clever.** Effort: S ≈ a day, M ≈ a few days, L ≈ 1–2 weeks. Rung 0 = runs
today.

### 1. The Mutant Gauntlet — _the gate as a measured classifier_

- **Proves:** the verifier actually discriminates good from bad work — and
  _where it's blind_.
- **How:** feed the 9 labeled canary patches (`.conveyor/canary/*`) — plus
  auto-generated graded variants — through the 14-stage gate and emit a
  **confusion matrix**: true-PASS, true-FAIL, **false-PASS** (the dangerous
  cell), false-FAIL. Break catch-rate down by archetype. Add
  **stage-attribution** (which stage caught each mutant) and **stage-ablation**
  (disable each stage, re-measure marginal contribution → find load-bearing vs.
  dead-weight stages).
- **Spend:** $0. **Effort:** S–M. **Rung:** 0 (today).
- **Payoff:** headline **false-PASS rate** and per-archetype/per-stage detection
  map. The single cheapest, most honest "does the verifier work" signal —
  available this week.
- **Why it's clever:** reframes the gate as an ML classifier and measures it
  like one. The false-PASS cell becomes the factory's primary vital sign;
  ablation tells you which of 14 stages you could delete without losing
  detection.

### 2. The Reference-Solution Golden Thread — _bridge the missing seam with $0 agents_

- **Proves:** the **entire** plan → compile → execute → gate → verdict path
  works end-to-end — the thing that has _no path today_.
- **How:** build the minimal `work_graph → station_plan` lowering + one
  agent-invoking station (the two missing seams). Then drive it not with an LLM
  but with **fixtures-as-agents**: replay `known_good.patch` as a "good agent"
  (gate must PASS) and each mutant as a "bad agent" (gate must FAIL/BLOCK). The
  eval _is_ the executable spec and regression test for the seam.
- **Spend:** $0. **Effort:** M–L (it builds real product). **Rung:** 1.
- **Payoff:** the first true end-to-end signal, deterministic and free, and the
  highest-leverage build in the program — it closes the gap the reality map
  exposes.
- **Why it's clever:** turns the reference solution and the mutant corpus into
  deterministic "agent recordings," so you test the whole pipeline _before a
  single LLM token is spent_. The eval pays for the product.

### 3. The Honesty Eval — _calibrate the whole factory_

- **Proves:** when the factory says PASS, the software is actually correct — and
  when it's blind, it _abstains_ instead of guessing.
- **How:** maintain a ground-truth-labeled corpus (known-good vs.
  broken-in-known-ways, seeded from mutants + real runs). Measure
  **calibration**: false-PASS rate (dangerous), false-FAIL rate (annoying), and
  **`indeterminate`/`require_human` coverage** (does it fail closed when
  evidence is missing, per the 17 fail-closed decision-contracts?). Render a
  reliability diagram for the factory.
- **Spend:** $0–low (reuses #1/#2 corpora). **Effort:** M. **Rung:** spans 0→3.
- **Payoff:** a calibration curve and a hard **false-confidence** count — the
  deepest safety number the system has.
- **Why it's clever:** treats the entire factory as a probabilistic classifier
  _of its own correctness_ and holds it to a calibration standard. "Honest
  verdict" becomes a measurable, trendable quantity.

### 4. The Cassette Flywheel — _record once, replay forever_

- **Proves:** real runs are reproducible — and converts every paid run into a
  permanent free regression test.
- **How:** wire the already-built-but-orphaned cassette infra (`cassettes.ex`,
  `replay_engine.ex`) into the run loop so every real agent session is sealed +
  redacted into a cassette; the eval suite replays the **growing** corpus
  deterministically in CI. Assert byte-identical artifacts + identical verdict
  on replay (causal-replay fidelity, ADR-12).
- **Spend:** $0 to replay (one-time spend to record). **Effort:** M. **Rung:**
  1→2.
- **Payoff:** one \$5 real run becomes infinite \$0 regression runs; the eval
  corpus **builds itself** from real usage. This is the literal bridge from
  "cheap signal" to "real outcome."
- **Why it's clever:** monetizes nondeterminism — you pay for signal exactly
  once, then it compounds. The factory's own production becomes its golden
  dataset.

### 5. The Lift Duel — _factory vs. vanilla Claude, same gate as referee_

- **Proves:** the headline lift — does the evidence-first loop produce more
  correct, more policy-compliant, less-cheating software than raw Claude, and at
  what cost multiple?
- **How:** same task → (a) full Conveyor loop, (b) vanilla Claude Code one-shot,
  (c) optionally you, human. Grade **all three** outputs with the _identical_
  Conveyor gate (#1's machinery). Report deltas in gate-pass, false-PASS,
  test-integrity, policy violations, and \$/latency per verified outcome.
- **Spend:** metered (amortized by #4). **Effort:** M (needs the real adapter
  from rung 1.5). **Rung:** 2.
- **Payoff:** the money chart — capability lift and its cost multiple, on one
  axis, ground-truth-anchored.
- **Why it's clever:** uses the factory's own gate as a neutral referee to grade
  its competitors on the exact same exam. The comparison is apples-to-apples by
  construction.

### 6. The Adversarial Agent — _pay an LLM to break your verifier_

- **Proves:** the verifier isn't vacuous — by measuring how hard it is to
  _cheat_.
- **How:** stand up an LLM whose explicit goal is code that **passes the gate
  while being broken** (test-weakening, hidden oracle, complying with
  prompt-injection, sneaking a policy edit). Robustness = the adversary's
  **escape rate**; every escape is auto-minimized and added to the Mutant
  Gauntlet (feeds #1/#3). A standing falsification bounty.
- **Spend:** metered, bounded by an attempt budget. **Effort:** M. **Rung:**
  2→3.
- **Payoff:** a live Goodhart/cheat-resistance score and a self-growing
  adversarial corpus.
- **Why it's clever:** a fixed test set can't tell you what you didn't think to
  test. An adaptive adversary can — and it makes the regression corpus stronger
  every time it wins.

### 7. The Compiler Property Engine — _falsify the pure heart_

- **Proves:** the Plan Compiler never silently drops or weakens human intent,
  and is deterministic.
- **How:** with StreamData (already a dep, currently used by _2 of 757_ tests),
  generate thousands of plans (well-formed + adversarial) and assert invariants:
  **every AC → ≥1 claim → ≥1 verification obligation** (no silent weakening),
  byte-stable content-addressed output (memoization soundness, ADR-14), no
  orphan/"confetti" graph nodes, and injection-in-plan-text never escalates
  authority.
- **Spend:** $0. **Effort:** S–M. **Rung:** 0 (today).
- **Payoff:** a strong, near-free guarantee at the system's purest,
  highest-leverage layer.
- **Why it's clever:** proving the compiler _can't_ lose intent across a
  generated space is far stronger than any example suite — and it targets the
  one subsystem where property testing is both cheapest and most valuable.

### 8. The Sentinel Evasion Tournament — _test the immune system's immune system_

- **Proves:** the anti-vacuity probes actually bite — the deepest failure mode
  the plan itself fears ("vacuous tests").
- **How:** for each of the 10 `IntegritySentinel` probes, construct an input
  that _should_ trip it (a suite with no red signal, a dropped falsifier seed, a
  non-hermetic test, a mutated production path) and assert it fires with the
  correct `rule_key`. Then run an **evasion search** for vacuous-but-passing
  suites. Metric: the false-NEGATIVE rate of the verifier-of-verifiers.
- **Spend:** $0. **Effort:** S–M. **Rung:** 0 (today).
- **Payoff:** a quantified "how hard is it to sneak a fake test past Conveyor"
  number — the thing that most undermines the word "verified."
- **Why it's clever:** everyone tests the product; almost no one tests the
  test-checker. This measures the integrity of integrity itself.

### 9. The Factory Vital-Signs Scorecard — _one living, CI-gating number set_

- **Proves:** trust is trending the right way — and catches trust regressions
  like test failures.
- **How:** a single versioned scorecard that every eval feeds — false-PASS rate,
  mutant catch-rate by archetype, sentinel-evasion rate, compiler-invariant
  violations, pass@1/pass@k, lift-vs-vanilla, \$/verified-AC, replay-fidelity,
  time-to-diagnosis. Rendered as one glanceable "is the factory healthy?"
  report, versioned per commit, and wired as a **required CI gate**.
- **Spend:** $0 (aggregator). **Effort:** S to start, grows. **Rung:** spans
  all; start day one.
- **Payoff:** answers "is it working?" at a glance and over time — and doubles
  as living documentation of what works.
- **Why it's clever:** collapses a sprawling, intimidating system's
  trustworthiness into a small set of trend-able, regression-gated numbers. It
  is the dashboard you wished existed when you "forgot what we built."

### 10. The Self-Hosting Capstone — _the factory fixes its own backlog_

- **Proves:** the outcome, on the hardest and most real task there is —
  Conveyor's own source.
- **How:** once #2/#4/#5 make real runs possible, point Conveyor at a real item
  from its **own beads backlog** (e.g., "wire cassette replay into the run
  loop," or a real bug) and have it produce the fix through the full loop.
  Success = the gate _and_ a human accept it. Every dogfooded fix also adds a
  real cassette to the flywheel (#4).
- **Spend:** metered. **Effort:** L. **Rung:** 3 (capstone).
- **Payoff:** the most credible end-to-end proof possible, and a compounding
  self-improvement loop.
- **Why it's clever:** the ultimate dogfood — the factory advancing the factory
  — and each capstone run simultaneously ships product and grows the regression
  corpus.

---

## Part IV — The build ladder & recommended first moves

```
Rung 0  (today, $0, exploits what exists)
  ├─ #1  Mutant Gauntlet            → false-PASS rate, per-stage map
  ├─ #7  Compiler Property Engine   → intent-preservation + determinism
  └─ #8  Sentinel Evasion Tournament→ anti-vacuity bite
        ↓
Rung 1  (bridge the seam, ~$0)
  ├─ #2  Reference-Solution Golden Thread → first true end-to-end signal
  └─ #4  Cassette Flywheel               → immortalize every future run
        ↓  (build the real Claude adapter here — the one missing enabler)
Rung 2  (real outcome + lift, metered, amortized by #4)
  ├─ #5  Lift Duel        → capability lift + cost multiple
  └─ #6  Adversarial Agent→ cheat-resistance, self-growing corpus
        ↓
Rung 3  (calibrate, aggregate, capstone)
  ├─ #3  Honesty Eval         → factory calibration / false-confidence
  ├─ #9  Vital-Signs Scorecard→ CI-gated trust dashboard (start at rung 0)
  └─ #10 Self-Hosting Capstone→ the factory fixes itself
```

**Recommended first three (one week, $0):** **#1 + #7 + #8** — they prove the
three pillars of the verifier (discrimination, intent-preservation,
anti-vacuity) on assets that already exist, with no LLM spend, and they populate
the **#9 scorecard** from day one. Stand up the scorecard skeleton alongside
them so every later number has a home.

**Then the pivotal build:** **#2** (Reference-Solution Golden Thread). It is the
single highest-leverage item because it _bridges the severed seam the reality
map exposes_ — and it does so deterministically, for $0, before you ever wire a
paid model. Immediately follow with **#4** so the first real (paid) runs are
never thrown away.

---

## Part V — Headline scorecard fields (what #9 tracks)

| Metric                           | Definition                                 | Target direction | First available |
| -------------------------------- | ------------------------------------------ | ---------------- | --------------- |
| **False-PASS rate**              | broken inputs the gate green-lights        | → 0              | Rung 0 (#1)     |
| Mutant catch-rate (by archetype) | true-FAIL / total bad, per defect class    | → 1              | Rung 0 (#1)     |
| Sentinel-evasion rate            | vacuous suites that pass the probes        | → 0              | Rung 0 (#8)     |
| Compiler-invariant violations    | AC→claim→obligation breaks, nondeterminism | → 0              | Rung 0 (#7)     |
| Replay fidelity                  | replayed runs that match byte-for-byte     | → 1              | Rung 1 (#4)     |
| pass@1 / pass@k                  | real-agent gate-pass rate                  | ↑                | Rung 2          |
| **Lift vs. vanilla Claude**      | Δ correctness/policy/integrity, same gate  | ↑                | Rung 2 (#5)     |
| \$ / verified-AC                 | cost to a green acceptance criterion       | ↓                | Rung 2          |
| Cheat-resistance                 | 1 − adversary escape rate                  | → 1              | Rung 2 (#6)     |
| Factory calibration              | PASS-confidence vs. actual correctness     | aligned          | Rung 3 (#3)     |
| Time-to-diagnosis                | replay → localized root cause              | ↓                | Rung 3          |

> **Note:** \$/verified-AC, pass@k, and lift all require **token/cost + latency
> instrumentation**, which does _not_ exist today (see reality map). Adding a
> per-run cost record is a small, prerequisite task for Rung 2.

---

## Appendix — the breadth behind the 10

The 10 were distilled from ~100 candidates across these families (kept for a
later round): discriminative gate evals (ROC/threshold curves, cross-mutant,
stage interaction) · anti-vacuity/Critic evals · compiler determinism &
confetti-graph metrics · the end-to-end bridge variants · real-agent outcome
(pass@k, stability, honest-verdict) · statistical qualification (grant-scope
soundness, sampling power, expiry/invalidation) · replay/forensic (time-travel
debugging, nondeterminism injection) · provenance/supply-chain (tamper
detection, SBOM/toolchain pinning) · safety/policy (emergency-stop coverage,
budget enforcement, secret-leak) · observability gaps (cost capture,
trace-completeness, glass-box run report) · economic/ROI (rework-rate,
throughput ceiling, factory-vs-human) · property/invariant (idempotency,
canonicalization, grant-lattice laws) · chaos/fault injection (MockDegraded's 11
scenarios, crash-mid-run, fail-closed) · and wildcards (factory Turing test,
falsification bounty, provenance replay theater).

Several were folded _into_ the 10 rather than dropped: mutation-driven hardening
lives in

# 1/#6; replay fidelity in #4; honest-verdict in #3; the falsification bounty in #6.
