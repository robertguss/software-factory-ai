# ROADMAP-REVIEW — adversarial self-audit of the v1 roadmap

> Audit trail for `ROADMAP.md`. The v1 roadmap (2026-06-21) was produced from a
> 16-agent **static** code audit, then deliberately red-teamed by 15 independent
> agents: 7 **blind** fact-re-verifiers (neutral prompts, not told v1's
> conclusions) + 8 logic/omission critics. This file records what they found and
> the six corrections that produced **v2**. It also answers the "audit artifacts
> were never committed" critique by committing _this_.

## Method & honesty caveat

Nothing was executed — the audit is static reading only. Runtime claims
("eval.lift crashes", "lift = 0.0", "abstain never fires", "a hung agent hangs
forever") are **inferred**, tagged `[needs-run]` in the roadmap, and are
resolved in **M0** by actually running the paths.

## What survived blind re-verification (high confidence)

The strategic spine held: loop doesn't close autonomously; **real agent never
ran through the production `SerialDriver`** (only `ReferenceSolution` patches;
7/7 slices "accepted" measures the patch applier, not an agent);
`Decomposer.propose` is content-blind (reads only `List.first(requirements)`);
**zero `Oban.insert`/`insert_all`**; all dormant closers have zero production
callers; 14 gate stages defined, 4 wired on the live path. **Serial-first is the
right call.**

## Findings → corrections applied in v2

**Tier A — factual errors (now fixed in the doc):**

1. "≈230 lib modules" → **383** (was off ~60%).
2. `eval.lift` crash cause: **not a "glob collision"** (no glob exists) —
   `load_reports` decodes `usage.json` alongside duel reports; fix = filter by
   `schema_version`.
3. "~7.5× / 12k vs 1.6k LOC" was the extreme of a **2.3×–8.6×** range presented
   as a point; like-for-like ≈ **2.3–4×**. Relabeled.
4. "pass@1 lift = 0.0" mischaracterized: **both arms passed 3/3 (100%)** on a
   trivial task (n=3, CI [0.292,1.0]) → **no signal**, not "Conveyor
   underperformed."

**Tier B — the core reframe:** "over-built judge, freeze it" was wrong and
self-contradictory (M4 is itself net-new verifier work). The verifier is
**under-wired / non-functional**, not over-built; building it first was a
**deliberate, defensible** bet. New framing: _nothing works end-to-end; activate
**and finish** the verifier, build the loop that exercises it; freeze new gate
**concepts** only._

**Tier C — sequencing:** M5 (medium plan) secretly depended on decomposition →
**decomposition resequenced before the medium-plan milestone** (now M5;
long-horizon is M6); the §4 bar's `conveyor.author` requirement is flagged as
needing M5. Within-slice racing (ADR-25) **moved into Track A (M2)** as a
reliability lever; the "parallelism = only throughput" axiom scoped to
cross-slice. Principle 4's stub-validation scoped to "once the graph is computed
(M5)."

**Tier D — exit-bar false rigor:** thresholds relabeled **[provisional]**;
70%/20% disclosed as inherited **"INITIAL HYPOTHESES"** the one real run missed;
"5 runs" specified as **live** (not cassette, which only tests determinism);
**M1's exit corrected** to claim wiring stability, not agent reliability;
parked-rate gains an absolute per-day reviewer cap.

**Tier E — Docker (D1) overstatement corrected:** the zero-false-pass bar runs
on the host already; hermeticity needs **network isolation, not Docker
specifically** (5/6 controls already host-met); `not_assessed` is
**non-blocking** (→ abstain/park, not false-pass); agent isolation ≠ gate
hermeticity. D1 rewritten accordingly.

**Tier F — tracker (`br`):** `onfq` duplicated in-progress `dr1m.2` (ADR-24) →
onfq closed, `dr1m.2` linked under M2; `dr1m.9` retitled from "decide: wire or
defer" to the decided "wire"; `dr1m.3` (ADR-25) linked as M2's optional lever;
epic `sgp` annotated superseded.

**Tier G — PM omissions added:** cost/budget + dogfooding + self-hosting
capstone (§6); kill/ pivot triggers on M1 & M3; T-shirt effort sizes per
milestone; human-review bandwidth cap.

## What is deliberately NOT resolved here

The exit-bar numbers remain provisional pending real data; the "what repos do
unattended runs target?" sub-decision (D1) is open; whether Findings-to-Fix
(verifier-as-product on external repos) is independently shippable before
loop-closure is flagged for genuine re-examination.

_2026-06-21._
