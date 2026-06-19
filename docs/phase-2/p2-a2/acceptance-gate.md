# P2-A2 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: Generic deterministic pass registry/cache, proposal-boundary decomposer,
candidate comparison and explicit selection, WorkGraph IR lowering, compiler
stable identity reconciliation, deterministic pass diagnostics, reusable partial
artifact salvage, and DecompositionSelection schema registration.

## Exit Criteria

### compiler passes run in unit tests without Oban/Postgres/provider

Evidence:

- `Conveyor.Planning.PassRegistry` runs pure pass functions through a restricted
  context and does not require Oban, Postgres, providers, wall clock, or process
  state.
- `PlanningPassRegistryTest` runs the pass registry in the no-start ExUnit
  harness and proves undeclared reads fail the pass boundary.

### malformed proposals never materialize

Evidence:

- `Conveyor.Planning.WorkGraphLowering` validates selected proposal schema,
  frozen PlanningSpec digest, required Slice identity fields, and required
  proposal lists before emitting `conveyor.work_graph@2`.
- `PlanningWorkGraphLoweringTest` proves malformed proposals return
  `status: :invalid_proposal` with `work_graph: nil`.

### candidates remain visible and unblended

Evidence:

- `Conveyor.Planning.Decomposer` emits artifact-only candidates and never
  assigns canonical IDs.
- `Conveyor.Planning.DecompositionSelection` records comparison rows and returns
  either one strictly dominant candidate or `:human_decision_required`.
- `PlanningDecomposerTest` and `PlanningDecompositionSelectionTest` prove
  primary/shadow candidates remain visible and `auto_blended?: false`.

### identical pass inputs/version yield identical output + cache hit

Evidence:

- `Conveyor.Planning.PassRegistry` cache keys include pass key, pass version,
  semantic digest, authority digest, and selectors.
- `PlanningPassRegistryTest` proves the first run misses cache and the same
  pass/input/version hits with the same output.

### an authority-input change misses the cache

Evidence:

- `Conveyor.Planning.PassRegistry` includes `authority_digest` in the
  content-addressed cache key.
- `PlanningPassRegistryTest` proves changing authority input produces a cache
  miss instead of reusing a stale result.

### reordering preserves unrelated IDs

Evidence:

- `Conveyor.Planning.StableIdentity` assigns Slice stable keys from semantic
  identity instead of list position and records `identity_actor: :compiler`.
- `PlanningStableIdentityTest` proves proposal reordering preserves keys and
  semantic changes produce explicit `supersedes_slice_key` lineage.

### partial valid artifacts survive one failed candidate fragment

Evidence:

- `Conveyor.Planning.PassDiagnostics` runs fragments independently, emits
  deterministic diagnostics for failed fragments, and content-addresses valid
  partial artifacts for reuse under partial authority.
- `PlanningPassDiagnosticsTest` proves valid Slice fragments remain reusable
  when a sibling fragment fails.

## Schema Evidence

- `conveyor.decomposition_selection@1` records planning run, candidate set
  reference/digest, selected candidate, actor/rationale, comparison reference,
  optional HumanDecision, and `auto_blended: false`.
- `EvidenceKernelResourcesTest` validates the schema against valid and
  missing-schema-version invalid examples and proves it is registered.

## Release Report

| Evidence source | Failed cases represented | Excluded cases |
| --- | --- | --- |
| `PlanningPassRegistryTest` | undeclared pass reads, stale cache reuse after authority/pass-version changes | none |
| `PlanningDecomposerTest` | canonical IDs minted in proposals, missing proposal artifacts, shadow run for low-risk plans | none |
| `PlanningDecompositionSelectionTest` | ties auto-selected, unapproved scope selected, candidates auto-blended | none |
| `PlanningWorkGraphLoweringTest` | stale PlanningSpec digest, missing stable key, partial WorkGraph materialized from malformed input | none |
| `PlanningStableIdentityTest` | order-based Slice keys, semantic change without supersession, agent-minted final IDs | none |
| `PlanningPassDiagnosticsTest` | one failed fragment erasing valid sibling artifacts, nondeterministic diagnostics, partial authority hidden | none |
| `conveyor.decomposition_selection@1` | missing schema version and unregistered schema resource | none |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the P2-A2 focused test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
