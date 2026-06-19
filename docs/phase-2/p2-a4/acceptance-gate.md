# P2-A4 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: Static decision package, placeholder prompt dry-compile, compiler
property checks, static/headless report projection, internal
`compiler_structure_gate`, and deterministic no-agent lint wedge.

## Exit Criteria

### acyclicity/stable-identity/traceability/scope-provenance/interface-consistency/atomicity/invalidation/digest-separation properties pass

Evidence:

- `PlanningCompilerPropertiesTest` uses generated Slice chains and compiler
  artifacts to cover acyclicity, stable identity, traceability, scope
  provenance, interface consistency, atomicity, invalidation behavior, and
  digest separation.
- The property suite composes `Conveyor.Planning.SliceDependency`,
  `Conveyor.Planning.StableIdentity`, `Conveyor.Planning.InterfaceGraph`,
  `Conveyor.Planning.GraphAnalyses`,
  `Conveyor.Planning.StructuralDryRun`,
  `Conveyor.Planning.ArtifactInputIndex`, and
  `Conveyor.Planning.StaticDecisionPackage`.

### pass cache + derivation impact tests pass

Evidence:

- `PlanningCompilerPropertiesTest` proves identical pass inputs/version reuse the
  `Conveyor.Planning.PassRegistry` cache and authority/pass-version changes miss
  the cache.
- `PlanningCompilerPropertiesTest` also proves derivation and impact behavior by
  exercising `Conveyor.Planning.ArtifactInputIndex` and
  `Conveyor.Planning.StructuralDryRun`.

### all hard structural blockers clear

Evidence:

- `PlanningPlanLintTest` proves `Conveyor.Planning.PlanLint` detects missing hard
  constraints, unmeasurable ACs, ambiguous interfaces, human-decision blockers,
  weak oracle paths, and critical context-budget impossibility.
- The same test proves a complete non-authorizing lint contract passes with no
  findings.

### no ContractLock/approval/implementation authority is created

Evidence:

- `PlanningStaticDecisionPackageTest` proves
  `Conveyor.Planning.StaticDecisionPackage` emits `authority_effect: :none` and
  does not create ContractLock, approval, or ready-Slice authority.
- `PlanningPlanLintTest` and `Mix.Tasks.ConveyorPlanLintTest` prove lint and
  `plan_prepare --no-agents` results retain non-authorizing flags and do not use
  agents, provider credentials, or an implementer.

### `compiler_structure_gate` passes

Evidence:

- `Mix.Tasks.ConveyorCompilerStructureGateTest` proves
  `mix conveyor.compiler_structure_gate` passes complete static packages with no
  hard blockers and exits two for hard blockers.
- `Conveyor.Planning.CompilerStructureGate` fails closed if a package attempts to
  create ContractLock, approval, ready-Slice, or implementer authority.

### no-agent lint runs without a QualificationGrant and produces the same deterministic diagnostics as the full compiler

Evidence:

- `Mix.Tasks.ConveyorPlanLintTest` proves `mix conveyor.plan_lint`,
  `mix conveyor.contract_lint`, and `mix conveyor.plan_prepare --no-agents` run
  through DB-free no-start tests without provider credentials, AgentRunner,
  Cassettes, or a QualificationGrant.
- `PlanningPlanLintTest` proves human, JSON, and SARIF output are rendered from
  the same canonical `Conveyor.Planning.PlanLint` findings.

### SARIF and static Markdown are projections of the same canonical findings

Evidence:

- `PlanningStaticReportTest` proves JSON and static human/Markdown-compatible
  report bodies are projections of the same canonical static compiler findings.
- `PlanningPlanLintTest` proves SARIF result rule IDs, source anchors, and
  canonical finding IDs are projected from the same canonical lint findings.

## Release Report

| Evidence source | Failed cases represented | Excluded cases |
| --- | --- | --- |
| `PlanningStaticDecisionPackageTest` | missing required artifacts, authority accidentally emitted by the static package | none |
| `PlanningPromptDryCompileTest` | missing prompt placeholders, provider/implementer launch during dry compile | none |
| `PlanningCompilerPropertiesTest` | cycles, unstable IDs, missing traceability, unsafe atomicity, invalidation ambiguity, cache contamination, digest conflation | none |
| `PlanningStaticReportTest` | JSON/static human projection drift, missing canonical finding keys | none |
| `Mix.Tasks.ConveyorCompilerStructureGateTest` | structural blockers passing, authority-creating packages passing | none |
| `PlanningPlanLintTest` | missing hard constraints, unmeasurable ACs, ambiguous interfaces, orphan/static blockers, weak oracle paths, invalid suppressions, critical context impossibility | none |
| `Mix.Tasks.ConveyorPlanLintTest` | CLI drift for `plan_lint`, `contract_lint`, and `plan_prepare --no-agents`; SARIF/source-anchor loss; accidental provider/agent requirements | none |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the P2-A4 focused test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
