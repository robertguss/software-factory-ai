# ADR-23 — Reliability Engine: implementation plan (TrustScore + abstaining gate)

> **Status:** **Part A (pure `TrustScore`) IMPLEMENTED + GREEN** (11 tests pass,
> credo/format clean); **Part B (abstain wiring) staged** behind the in-flight
> loop work (see §6 Sequencing). **Spec:** `docs/adrs/adr-23-ternary-gate-verdict-
> calibrated-abstention.md`. **Bead:** `software-factory-ai-dr1m.1`. **Date:**
> 2026-06-20.

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

## 4. Part B — abstain wiring (deferred until §6 clears)

1. **Migration:** add `:abstained` to `RunAttempt.outcome` `one_of` (currently
   `[:none, :needs_rework, :accepted, :rejected, :policy_blocked]`). Append-only.
2. **Run-attempt state machine:** an abstained attempt keeps a terminal *passed*
   status (`:gated`) with `outcome: :abstained` — it did pass the stages.
3. **`Finalizer.finalize!/3`:** today it branches `if result.passed? do
   pass_gate! else fail_gate!`. Add a third path: when `passed?` **and**
   `TrustScore.evaluate(...).band == :abstain`, call `abstain_gate!` →
   `RunAttempt outcome: :abstained`, **Slice → `:parked`** (the state already
   exists; reuse/extend the `:park` `SliceLifecycle` transition). Never auto-merge.
4. **Threading the evidence:** the gate context must carry the IntegritySentinel
   result + calibration + baseline + replay so `Finalizer` can build the evidence
   map. Most are already in the gate context; confirm IntegritySentinel runs in
   the production gate (today it is an oracle, not a wired stage — wire it as a
   non-blocking evidence producer first).
5. **Reporting:** `GateResult`/report schemas carry the third outcome + the
   `TrustScore` breakdown + the policy digest. Reports must never collapse abstain
   into pass or fail.

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
