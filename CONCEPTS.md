# Concepts

> Shared domain vocabulary for this project — entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

This first seed covers the verification gate and the unit of work it judges — the area a recent learning investigated. It is intentionally partial; other areas accrete over time.

## The factory loop

### Run
A single unattended execution of a selected set of slices in dependency order, identified by one run id for its whole lifetime. A run carries on past a parked slice rather than halting, and its outcome history is committed durably so an interrupted run can be resumed. Every rework attempt within a run shares that one run id.

### Slice
A contract-bearing unit of work — the atomic thing the factory builds and the gate judges — named by a stable contract key that is identical across runs. Once a slice passes the gate its result is durable and is never re-executed, even when a later run resumes; the gate-passed slice is the run's boundary of settled work.

### Resume
Re-entering an interrupted run by folding its committed outcome history back into working state and continuing from the first unsettled slice. Already-passed slices are replayed from the record, not re-executed — only the in-flight slice runs again, from a clean base.

### Rework
Re-executing a slice within the same run after it fails the gate, giving the agent another attempt before the slice is parked. All rework attempts belong to the same run and share its run id, so they are not independent executions.

## The verification gate

### Trust gate
The staged verification gate that decides whether a slice's work may merge without a human. It runs progressively stronger checks, combines them into a calibrated score, and — rather than a plain pass/fail — can withhold judgment when confidence is low.
*Avoid:* "verification gate" (used in strategy docs for the same thing).

### Abstain
The gate's verdict that is neither accept nor reject: when a signal is missing or untrustworthy, the gate withholds judgment and routes the slice to a human review queue instead of merging or hard-failing it. Abstention is what lets work merge unattended only when the gate is confident, and park otherwise.

### Replay fidelity
Whether a run's execution reproduces a known baseline. It is a verification dimension the gate can consider but which stays dormant until a real reproducibility check exists; until then it is reported honestly as "no baseline," never as a success. Replay divergence is the gate-facing form of this verdict.

### Replay divergence
The gate-facing verdict for replay fidelity, in one of three states: reproduced (`none`), diverged, or no-baseline (`baseline-absent`). A diverged verdict makes the gate abstain; the no-baseline state is non-blocking and contributes nothing to the score. A meaningful non-baseline verdict requires re-executing against the same recorded inputs — comparing the outcomes of two different runs does not produce one.
