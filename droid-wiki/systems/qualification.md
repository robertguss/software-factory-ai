# Qualification

The qualification system in `lib/conveyor/qualification/` determines whether
plans and contracts are qualified for execution at a given scope. It produces
offline-verifiable bundles, evaluates a pure qualification gate, issues
immutable grants, and updates phase-next decisions. Qualification is the bridge
between deterministic evidence and live statistical quality: a grant records
what scope is supported, by what evidence, and under what limitations.

## Bundle

`lib/conveyor/qualification/bundle.ex` is the offline-verifiable qualification
bundle projection and verifier. A bundle carries the grant id, registry digest,
canonicalization profile, scope digest, scope lattice digest, evidence root
digest, root manifest digest, run digest, hard invariant verdicts, canary refs,
replay anchors, waiver refs, waiver availability, and signature status.

Verification is intentionally pure: `verify_offline/1` checks only fields
carried in the bundle and never consults the live database. It validates scope
digest equality, presence of required digests (registry, evidence root, root
manifest, run), that all hard invariant verdicts passed, non-empty canary refs
and replay anchors, waiver availability, and signature status presence. The
result records whether the check was performed without a live database and the
verified status.

## Gate

`lib/conveyor/qualification/gate.ex` is the pure qualification gate evaluator.
It checks whether an evidence package is eligible to become a scoped grant
candidate but does not issue authority by itself. The gate evaluates 15 required
hard blockers: registry, canonicalization, attestations, derivation, policy,
scope, deterministic conformance, safety trace assertions, canaries,
meta-canaries, poison pill, fencing, role view, hidden oracle, and test
integrity. It also checks three required replay modes (strict, full, hybrid) and
live sample policy (worst required stratum result must be `quality_floor_met` or
`miss_observed`).

The gate returns a status of `:passed` or `:blocked`, an authority effect
(`qualification_grant_candidate` or `none`), findings with rule keys, and the
live sample policy summary.

## Grants

`lib/conveyor/qualification/grants.ex` is the pure grant issuance projection. A
`QualificationGrant` is immutable evidence about a supported scope. The
`issue/1` function checks denial reasons (gate not passed, scope lattice not
passed, scope not covered) and either issues a grant or denies with reasons.

On success, it builds four projections:

- **Grant** — scope, scope ref, evidence root digest, success rate bands,
  limitations, invalidation triggers, max autonomy, issuance and expiry
  timestamps.
- **Scope lattice** — worst required stratum result, unassessed strata,
  per-stratum results.
- **AdmissionPermit** — derived current-authority projection for one effectful
  run boundary, with permit digest, grant ref, and invalidation triggers.
- **PermitCheckpoint** — checkpoint of the permit with a valid-until timestamp
  and checkpoint digest.

Default invalidation triggers are `policy_digest_changed` and
`scope_digest_changed`.

## PhaseNextDecision

`lib/conveyor/qualification/phase_next_decision.ex` updates the
`PhaseNextDecision` after qualification review. It compares the requested scope
against the grant scope: if the grant covers the request, the branch is
`balanced` with authorization result `authorized`; otherwise the branch is
`gate_first` with `hardening_required`. The decision records selected branches
with responses, blocks-requested-grant flags, justification refs, stop-the-line
entries, and a content-addressed decision digest.

## Report

`lib/conveyor/qualification/report.ex` is the canonical release-facing
projection for scoped qualification grants. It keeps authority-critical grant
facts structured so a prose summary cannot hide blockers, limitations, waivers,
expiry, or residual risk. Each grant report carries the grant id, scope ref,
deterministic evidence root, live quality intervals, limitations, unassessed
capabilities, active waivers (with owner, compensating controls, max autonomy,
expiry), issuance and expiry timestamps, invalidation triggers, max autonomy,
and residual risks.

## Key source files

| File                                                | Purpose                                                                             |
| --------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `lib/conveyor/qualification/bundle.ex`              | Offline-verifiable qualification bundle projection and verifier.                    |
| `lib/conveyor/qualification/gate.ex`                | Pure qualification gate evaluator with 15 hard blockers and replay checks.          |
| `lib/conveyor/qualification/grants.ex`              | Grant issuance, scope lattice, admission permit, and permit checkpoint projections. |
| `lib/conveyor/qualification/phase_next_decision.ex` | Phase-next decision update after qualification review.                              |
| `lib/conveyor/qualification/report.ex`              | Canonical release-facing projection for scoped qualification grants.                |

## Related pages

- [Planning compiler](planning-compiler.md) — layered roots and attestations
  feed qualification bundles
- [Cassettes](cassettes.md) — replay anchors feed qualification bundles
- [Battery](battery.md) — live sampling produces quality intervals for grants
- [Contract management](../features/contract-management.md) — contract lock
  lifecycle
