# P2-B3 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: adversarial multi-lens Contract Critic, cheapest-wrong challenge cases,
IndependenceProfile enforcement, bounded repair, and typed repair diff with
partial pass-output reuse.

## Exit Criteria

### planted loopholes/scope-laundering are caught

Evidence:

- `Conveyor.ContractCritic.CheapestWrong` projects cheapest-wrong attacks into
  stable `ContractChallengeCase` records with rule keys, evidence refs,
  materiality labels, and repair proposals.
- `ContractCriticCheapestWrongTest` proves a planted deleted-row loophole is
  preserved as `contract_critic.cheapest_wrong.ignore_deleted_rows`.

### disagreement is retained

Evidence:

- `Conveyor.ContractCritic.Lenses` runs the required lens catalog and keeps
  independent lens results rather than collapsing them to one score.
- `ContractCriticLensesTest` proves disagreeing `pass` and `fail` lens outcomes
  remain represented in the review output.

### no repair weakens semantics without authority

Evidence:

- `Conveyor.ContractCritic.RepairLoop` routes material plan, constraint,
  interface, and acceptance changes to amendment.
- `ContractCriticRepairLoopTest` proves policy/acceptance weakening without
  normal authority returns a blocking `repair.policy_or_acceptance_weakening`
  finding.

### oscillation parks

Evidence:

- `Conveyor.ContractCritic.RepairLoop` enforces a default two-round automatic
  repair bound and evaluates repair history for oscillation/non-progress.
- `ContractCriticRepairLoopTest` proves repeated artifact digests park the
  repair with evidence refs.

### unaffected passes/artifacts are reused

Evidence:

- `Conveyor.ContractCritic.RepairDiff` emits typed repair comparisons with
  before/after digests and pass reuse/invalidations derived from pass input
  refs.
- `ContractCriticRepairDiffTest` proves unchanged interface-graph pass inputs
  reuse the previous output while changed TestPack inputs invalidate only that
  pass.

### the Critic cannot approve/lock

Evidence:

- `Conveyor.ContractCritic.Lenses` emits `authority_effect: :none`,
  `can_approve?: false`, and `can_lock?: false`.
- `ContractCriticLensesTest` proves the Critic review cannot approve or lock.
- `Conveyor.ContractCritic.IndependenceProfile` proves critical-lens
  independence is recorded and enforced independently from authority.
- `ContractCriticIndependenceTest` proves high-risk changes require
  `model_diverse` or `human_or_deterministic` evidence.

## Release Report

| Evidence source                   | Failed cases represented                                                                      | Excluded cases |
| --------------------------------- | --------------------------------------------------------------------------------------------- | -------------- |
| `ContractCriticLensesTest`        | missing lens coverage, disagreement collapse, accidental approve/lock authority               | none           |
| `ContractCriticCheapestWrongTest` | planted loophole not recorded as a stable challenge case                                      | none           |
| `ContractCriticIndependenceTest`  | role-label-only independence for high-risk changes                                            | none           |
| `ContractCriticRepairLoopTest`    | repair loops beyond bounds, oscillation/non-progress, semantic weakening without authority    | none           |
| `ContractCriticRepairDiffTest`    | scope-expanded repair changes, unnecessary pass invalidation, missing typed comparison digest | none           |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the focused P2-B3 Contract Critic test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `mix format ... --check-formatted`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
