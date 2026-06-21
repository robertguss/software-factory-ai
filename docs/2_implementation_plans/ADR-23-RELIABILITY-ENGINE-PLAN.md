# ADR-23 — Reliability Engine: implementation plan (TrustScore + abstaining gate)

> **Status:** **Part A (pure `TrustScore`) + Part B (abstain wiring) IMPLEMENTED
> + GREEN.** Part B landed after the loop branch merged to main (PR #9). The
> `Finalizer` now routes a passed-but-unconfident gate to `:abstained` /
> `Slice :parked` — **opt-in**: it only fires when the conductor supplies
> `:trust_evidence`, so every existing pass path is unchanged. **Spec:**
> `docs/adrs/adr-23-ternary-gate-verdict-calibrated-abstention.md`. **Bead:**
> `software-factory-ai-dr1m.1`. **Date:** 2026-06-20.

## 1. Goal

Make the gate ternary — `pass / fail / abstain` — by computing a calibrated
`TrustScore` from signals Conveyor **already produces and discards**, and routing
a passed-but-unconfident attempt to the human (`:parked`) instead of
auto-accepting it. This is the keystone of the raw-leverage program: it lets the
operator review only the fraction the machine is honestly unsure about.

## 2. Two parts, deliberately split by collision risk

| Part | What | Touches | Build now? |
| --- | --- | --- | --- |
| **A. `Conveyor.Gate.TrustScore`** | a **pure** fusion + threshold function over recorded evidence | one new file (`lib/conveyor/gate/trust_score.ex`) | **DONE — implemented + green.** |
| **B. Abstain wiring** | the `:abstained` outcome + the `Finalizer` third branch + slice `:parked` routing | `gate/finalizer.ex`, `factory/run_attempt.ex` (+ migration), `SliceLifecycle` | **No — defer.** These are hot files the `codex/handoff-full-implementation` branch is actively reshaping (see §6). |

Part A is the substance and the risk (calibration is the hard part); it has no
overlap with the loop work, so it is buildable today behind the failing tests.
Part B is mechanical but must wait for the loop-closer/finalizer churn to land.

## 3. Part A — `Conveyor.Gate.TrustScore` (pure)

### 3.1 Inputs (all already computed elsewhere)

`evaluate/2` takes a normalized `evidence` map and `opts` (thresholds + policy):

```
evidence = %{
  integrity_verdict: "trustworthy" | "suspect" | "not_assessed" | "untrustworthy",
      # from Conveyor.Verification.IntegritySentinel.run/3 -> result["verdict"]
  calibration_status: :valid | :invalid | :not_assessed,
      # from Conveyor.AcceptanceCalibration (%{status: :valid, expected_failures: [...]})
  baseline_status:    :green | :red | :unknown,
      # from Conveyor.BaselineHealth
  replay_divergence:  :none  | :diverged | :unknown,
      # from Conveyor.Cassettes.ReplayDiagnostics (evaluation_surface_changed?)
  corpus_pass_rate:   float() | nil
      # historical P(pass) for this slice archetype from the Genome (nil until seeded)
}
```

The component values are each mapped to `[0.0, 1.0]`, weighted, and summed into a
`score`. The **partition into a band is what matters**: above the `auto_accept`
threshold → `:auto_accept`; otherwise → `:abstain`. (TrustScore never returns a
`fail` band — a stage failure already produced `passed? == false` upstream;
TrustScore only adjudicates *passed* gates.)

### 3.2 Output

```
%{
  score: float(),                 # 0.0..1.0
  band: :auto_accept | :abstain,
  components: %{integrity: float, calibration: float, baseline: float,
                replay: float, corpus: float},
  thresholds: %{auto_accept: float},
  policy_digest: String.t()       # sha256 of the weights+thresholds (content-addressed)
}
```

### 3.3 Load-bearing invariants (these are the tests)

1. **Trustworthy & fully-green evidence ⇒ `:auto_accept`.** Specifically the
   known-good reference solution's evidence must always auto-accept — this is the
   `loop_integrity` guarantee (ADR-23 §Implementation Notes). If the reference
   abstains, calibration is broken and that is release-blocking.
2. **`suspect` or `untrustworthy` integrity ⇒ `:abstain`** regardless of green
   stages (a vacuous-but-green suite must not auto-merge).
3. **Any `:not_assessed` / thin evidence ⇒ `:abstain`** (conservative bootstrap:
   with no corpus the system abstains liberally and loosens as data accrues).
4. **Purity / determinism:** identical evidence ⇒ identical result (no I/O, no
   clock, no RNG). Required so it can be re-evaluated offline against history.
5. **Monotonicity:** improving any single component never downgrades the band.
6. **Content-addressing:** `policy_digest` is stable for fixed weights+thresholds
   and changes when they change (mirrors ADR-02/04 — a threshold change cannot
   reinterpret prior scores).

### 3.4 Calibration (the hard part, staged)

Weights and thresholds start hand-set and **deliberately conservative** (abstain
often). As the Genome accrues labeled outcomes — including operator overrides of
abstentions (ADR-23 learning loop) — the thresholds are re-fit (Brier-calibrated)
and the method/policy digest recorded with each score. The fusion *shape* (which
signals, how combined) is fixed in Part A; only the numbers move, behind the
digest.

## 4. Part B — abstain wiring (DONE — green)

1. **Migration:** `:abstained` added to `RunAttempt.outcome` `one_of` **and** to
   the Postgres check constraint `run_attempts_outcome_must_be_known`
   (`priv/repo/migrations/20260620200000_add_abstained_run_attempt_outcome.exs` —
   AshPostgres enforces the enum at the DB level, so the migration was required).
2. **Run-attempt state:** an abstained attempt reuses the `:gate` action → status
   `:gated` with `outcome: :abstained` — it did pass the stages.
3. **`Finalizer.finalize!/3`:** now a `cond` — when `passed?` **and** the
   conductor supplied `:trust_evidence` **and** `TrustScore.evaluate(...).band ==
   :abstain`, `abstain_gate!` sets `RunAttempt outcome: :abstained` and
   transitions the **Slice → `:parked`** (the existing `:park` transition allows
   `:in_progress → :parked`). It also **skips `emit_pass_outputs!`** so no
   verified-pass provenance (BackEdge) or TrustBundle is minted for an
   unaccepted run. `:trust_score` is returned in the finalize result.
4. **Opt-in (the key safety property):** with no `:trust_evidence`, `trust_score`
   returns `nil` and the legacy pass path runs unchanged. This is what let Part B
   land without regressing any of the merged loop tests.
5. **Tests:** `gate_finalizer_test.exs` — low trust evidence ⇒ `:abstained` +
   `:parked` + no BackEdge/TrustBundle; high trust evidence ⇒ still `:accepted`.

## 4a. Evidence threading — DONE (abstain is now LIVE)

`Conveyor.Gate.TrustEvidence` (`lib/conveyor/gate/trust_evidence.ex`, pure)
assembles the `TrustScore` evidence from a slice run's accumulated `output` — the
acceptance-calibration (`"test_pack_calibration".status`) and baseline-health
(`"baseline_health_status"`) signals the stations already write. Both production
finalize sites — `Planning.SerialDriver` and `AttemptLoop` — now thread
`slice_result.output` into the finalize context as `:trust_evidence`, and
`AttemptLoop` treats `:abstained` as a terminal outcome.

**Safe staged rollout:** unmeasured signals (IntegritySentinel verdict, replay,
corpus rate) default to **non-blocking**, so a passed gate abstains only on a
*recognized negative* — `calibration_status: :invalid` or `baseline_status: :red`.
The happy path (valid calibration + passed baseline) auto-accepts exactly as
before, so the full merged loop regression (44 tests) stays green; abstain now
genuinely fires on bad calibration/baseline. Tests:
`test/conveyor/gate/trust_evidence_test.exs`.

## 4b. Persisted verdict — DONE

The `GateResult` resource gains a nullable `:trust_score` (jsonb) column
(`priv/repo/migrations/20260620210000_*.exs`); `Finalizer` persists the full
`TrustScore` map (score / band / components / thresholds / policy_digest) on every
passed gate, nil when no evidence. Abstentions and the score behind every
auto-accept are now durable and queryable (the foundation for a parked-slice
inbox). Tests assert the band round-trips (`gate_finalizer_test.exs`).

## 4c. IntegritySentinel verdict — tested SEAM done; observation production deferred

`Conveyor.Gate.IntegrityEvidence.verdict/2` runs the anti-vacuity sentinel over a
map of probe observations and returns the verdict `TrustEvidence` already reads.
**Safety property (tested):** a probe with no observation is `not_assessed`
(never `failed`), and `TrustEvidence` maps `not_assessed` → non-blocking — so the
sentinel can be wired with *partial* observations and never force a spurious
abstain; it abstains only on a genuine probe failure (e.g. production source
mutated, hidden network/secret dependency).

**Producer path — WIRED (verdict honestly `not_assessed`).** The production verify
station (`Conveyor.Stations.Verify`) now emits `output["integrity_verdict"]` via
`IntegrityEvidence`, so the full path verify → output → `TrustEvidence` → gate is
live and asserted (`first_light_production_loop_test`). It currently emits
`not_assessed` (non-blocking) because the verify station has **no truthful probe
observations to supply** — and faking them would overclaim. This is the honest
state, not a stub.

**The genuinely-remaining work — probe-observation instrumentation (its own
subsystem):** each IntegritySentinel probe needs an observation matching its exact
expectation. The toolchain's `hermeticity/1` descriptor deliberately uses a
different, honest vocabulary (it pins network/clock/rng/locale but not
ordering/shared_state, and only blocks the network under docker), so it does not
satisfy the probe's 6-control check without overclaiming; source-mutation/
mount-boundary need the sandbox to report writes; falsifier survival needs the
contract seeds run. Until those producers exist (and assert hermeticity only under
a hermetic/docker backend so local runs stay non-blocking), the wired path
correctly reports `not_assessed`. Replay divergence (`"replay_divergence"`) is
likewise read by `TrustEvidence` and awaits a producer.

## 5. TDD test plan

Part A — **implemented + green** (11 tests):

- `test/conveyor/gate/trust_score_test.exs` — the Part-A invariants in §3.3 all
  pass against `lib/conveyor/gate/trust_score.ex`.

Deferred (write when Part B unblocks, against a `DataCase`):

- `Finalizer` abstain branch: passed stages + abstain band ⇒ `outcome:
  :abstained`, slice `:parked`, no auto-accept.
- passed stages + auto_accept band ⇒ unchanged `:accepted` behavior (regression).
- failed stages ⇒ unchanged fail/rework/policy_block classification (regression).
- the known-good reference run ⇒ `:accepted` (loop_integrity end-to-end).

## 6. Sequencing & dependencies

- **Build Part A now.** Pure, isolated, fully testable; lands the calibration
  design and the invariants.
- **Hold Part B** until `codex/handoff-full-implementation` merges its loop work
  (it edits `station.ex`, `run_slice.ex`, `gate/stages/*`, and reshapes the
  finalizer/rework path the abstain branch hangs off). Building the finalizer edit
  against a moving target is guaranteed rework.
- **Coordination ask** for the other track: keep the `Finalizer` failure
  classification and terminal-state set **extensible** so adding an `:abstain`
  branch + `:abstained` outcome is additive, not a rewrite.

## 7. Risks

- **Calibration with no data.** Mitigated by conservative bootstrap (abstain
  liberally) + the loop_integrity invariant as a hard floor.
- **IntegritySentinel not yet wired in the production gate.** It exists as an
  oracle; Part B step 4 wires it as a non-blocking evidence producer before
  TrustScore consumes it.
- **Over-abstaining annoys the operator.** Acceptable early; the override-learning
  loop tightens thresholds over time. Track abstain-rate as a first-class metric.
