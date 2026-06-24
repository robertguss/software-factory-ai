# P2-B8 Phase 3 Hardening Plan

Recorded outcome: harden_gate_first

No Phase-3 entry contract is issued. The `phase2_gate` is failed and the
PhaseNextDecision opens `gate_first` hardening with no automatic authority.

## Readiness Matrix

| Dimension               | Finding                                                                                                                               | Decision                                                              |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| Evidence/gate integrity | Focused release suites passed, but DB-backed `mix test` is unavailable locally and the gate records `db_backed_mix_test_unavailable`. | Not ready for Phase 3 production authority.                           |
| Grant scope/stability   | Current grant is active for offline/local-dev scope only and does not cover production Phase 3 authority.                             | Keep max autonomy at `local_dev`.                                     |
| Contract stability      | `first_pass_gate_success` and `material_dispute_rate` miss the §17.6 hypotheses.                                                      | Harden contract/gate feedback before concurrency.                     |
| Adapter reliability     | No B8 adapter blocker is observed in the focused release suite.                                                                       | Do not select adapter-first unless new adapter evidence regresses.    |
| Operator clarity        | Release record exposes limitations, decision debt, and residual risks.                                                                | Preserve operator-visible gate state and hardening branch.            |
| Serial execution        | P2-B7 pilot preserves serial execution and selected-set immutability, but one parked/disputed path remains part of the evidence.      | Continue width-one hardening only.                                    |
| Economics/latency       | Phase 3 concurrency/budget sizing lacks production DB-backed timing data.                                                             | Do not infer fleet budgets from local DB-free checks.                 |
| Operational controls    | Dependency graph has no active cycles and compile/diff checks pass; production restore/DB authority is not proven here.               | Keep operational scope local until DB-backed release evidence exists. |

## Branch Selection

Selected branch: `harden_gate_first`.

Non-selected hardening branches remain available as escalation paths:

- `harden_adapter_first`: use if cancellation, policy interception, evidence
  attachment, or adapter health regresses.
- `harden_contract_pipeline_first`: use if contract generation requires
  from-scratch reconstruction or loses required obligations.
- `harden_operator_surface_first`: use if comparison, approval, or recovery
  decisions become ambiguous to operators.
- `harden_evidence_kernel_first`: use if digest, derivation, replay, fencing, or
  hidden-oracle integrity becomes ambiguous.

## Gate-First Work Items

1. Restore a runnable DB-backed `MIX_ENV=test mix test` path for Conveyor.Repo
   and rerun the full release suite.
2. Add release-gate cases that turn `first_pass_gate_success` below 70% into a
   visible hard blocker.
3. Add release-gate cases that turn `material_dispute_rate` at or above 20% into
   a visible hard blocker.
4. Re-run the B8.1 release suite and update `phase2-gate.json` only after the
   DB-backed suite and quality hypotheses are green or a new PhaseNextDecision
   explicitly changes the hypotheses.

## Exit Criteria

- `db_backed_mix_test_unavailable` is removed by a passing DB-backed suite or by
  a visible human risk acceptance that grants no automatic authority.
- `first_pass_gate_success` is at least 70% or superseded by a recorded
  PhaseNextDecision.
- `material_dispute_rate` is below 20% or superseded by a recorded
  PhaseNextDecision.
- The active grant covers the requested Phase 3 scope before any Phase 3 entry
  contract is issued.
