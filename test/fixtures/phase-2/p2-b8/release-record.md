# P2-B8 Release Record

Status: release evaluation recorded for the local/offline Contract Foundry
scope. The record does not grant production deployment authority.

## Limitations

- Full DB-backed `mix test` is blocked in this environment by PostgreSQL
  authentication for user `postgres`; B8.1 records this as a blocker, not a
  pass.
- The active grant is limited to an offline-only sample and local-dev authority.
- The pre-registered pilot missed the first-pass deterministic gate success and
  material dispute-rate quality hypotheses.
- There is no production deployment authority and no automatic Phase 3
  advancement.

## Decision Debt

| Debt | Owner | Next action | Autonomy effect |
| --- | --- | --- | --- |
| DB-backed release suite unavailable locally | release operator | restore a valid PostgreSQL test credential or run the DB suite in CI before production authority | blocks production authority |
| first_pass_gate_success below hypothesis | phase2_gate owner | harden generated contract gate feedback before Phase 3 autonomy expansion | caps to local_dev hardening |
| material_dispute_rate above hypothesis | phase2_gate owner | reduce ambiguity and contract-dispute rate with targeted hardening | caps to local_dev hardening |

## Active Grants

| Grant | owner | scope | expiry | compensating controls | autonomy effect |
| --- | --- | --- | --- | --- | --- |
| `qualification_grant:sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` | phase2_gate owner | `qualification-scope:p2-static-planning`; offline/local-dev Contract Foundry pilot/release evidence | 2026-07-19T00:00:00Z | B8.1 focused release suite, P2-B7 pilot evidence, empty bead dependency cycles, warnings-as-errors compile | max autonomy `local_dev`; no production deployment authority |

## WaiverBudget

WaiverBudget status: zero active waivers are consumed by the current P2-B8
release scope.

The current qualification grant has `waiver_refs: []`. Any future waiver must
record owner, scope, expiry, compensating controls, and autonomy effect before
it can influence release authority.

## Active Waivers

| Waiver | owner | scope | expiry | compensating controls | autonomy effect |
| --- | --- | --- | --- | --- | --- |
| none for current P2-B8 release scope | phase2_gate owner | none | none | none | no waiver-based authority |

## Residual Risks

| Risk | Evidence | Current treatment |
| --- | --- | --- |
| DB-backed behavior remains unverified locally | `MIX_ENV=test mix test` blocks before test execution on PostgreSQL auth | blocks production authority |
| first-pass gate success hypothesis missed | B8.2 quality comparison records 33.33% vs target >= 70% | targeted hardening required |
| material dispute-rate hypothesis missed | B8.2 quality comparison records 33.33% vs target < 20% | targeted hardening required |
| release scope is offline/local-dev only | active grant limitations include offline-only sample; no production deployment authority | restrict PhaseNextDecision to hardening/local-dev scope |
