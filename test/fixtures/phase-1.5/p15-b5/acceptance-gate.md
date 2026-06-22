# P15-B5 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: Expanded canaries, meta-canaries, trust-tool clean controls, and the
bounded behavior oracle for pure-refactor fixtures.

## Exit Criteria

### every trust tool catches its planted defect and passes its clean boundary

Evidence:

- `test/fixtures/phase-1.5/p15-b5/trust-tool-canaries.json` lists every P15-B5 trust
  tool, its planted catch canary, clean boundary, blocking miss key, and
  meta-canary references.
- `TrustToolCanariesTest` proves the manifest covers every required trust tool
  and that every tool has catch, clean-boundary, block-on-miss, and meta-canary
  metadata.
- `test/fixtures/phase-1.5/p15-b5/clean-controls.json` maps every trust tool to at least
  one clean-control fixture with `grant_scope: no_new_authority`.
- `GateCanaryFixturesTest` proves the gate mutant corpus declares archetype
  coverage and that each mutant remains patch-applicable.

### behavior drift is detected; a genuine refactor passes

Evidence:

- `Conveyor.BehaviorOracleAdapter` runs base and candidate functions across the
  same bounded input set, normalizes declared nondeterministic paths, and
  compares observable output/state.
- `BehaviorOracleAdapterTest` proves planted silent drift returns `diverged`
  with a `first_divergence_index`.
- `BehaviorOracleAdapterTest` also proves a genuine refactor with only declared
  nondeterministic variation returns `no_divergence_observed`.

### result is `no_divergence_observed`, not a general proof

Evidence:

- `Conveyor.BehaviorOracleAdapter` emits
  `"equivalence_claim": "bounded_observation_only"` for every result.
- `BehaviorOracleAdapterTest` asserts the successful refactor result is
  `no_divergence_observed` and never a general equivalence proof.
- `BehaviorOracleAdapterTest` proves empty bounded-input fixtures return
  `inconclusive` rather than passing vacuously.

### one meta-canary miss blocks the affected grant

Evidence:

- `trust-tool-canaries.json` records a `blocks_on_miss` key for every trust
  mechanism, so a missed canary has an explicit affected-grant blocker.
- `TrustToolCanariesTest` proves every trust tool has non-empty
  `meta_canary_refs` and a non-empty `blocks_on_miss`.
- `clean-controls.json` keeps clean-control fixtures scoped to
  `no_new_authority`, preventing a clean boundary from widening the grant that
  a missed meta-canary would block.

### release report includes all failed/excluded cases

Evidence:

- The release report below names every P15-B5 evidence source and whether any
  cases were excluded from the local DB-free verification pass.
- Failed cases from red TDD cycles were retained in the focused tests:
  missing trust-tool manifest, missing clean-control manifest, missing behavior
  oracle adapter, missing divergence metadata, runner errors, and empty bounded
  inputs.

## Release Report

| Evidence source | Failed cases represented | Excluded cases |
| --- | --- | --- |
| `GateCanaryFixturesTest` | patch-inapplicable mutants and missing archetype metadata | none |
| `TrustToolCanariesTest` | missing trust tool canary metadata, missing clean controls, invalid clean-control refs | none |
| `BehaviorOracleAdapterTest` | silent behavior drift, runner execution error, missing bounded inputs | none |
| `trust-tool-canaries.json` | all trust-tool catch canaries and `blocks_on_miss` keys | none |
| `clean-controls.json` | all trust-tool false-positive clean boundaries | none |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the B5 focused test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
