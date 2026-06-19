# P2-B1 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: Contract Forge AgentBrief schema, archetype templates, interface policy,
VerificationObligation derivation, compiler-derived falsifier seeds, and
contract-author RoleView normalization.

## Exit Criteria

### every contract states current/desired/non-goal/scope/recovery

Evidence:

- `AgentBriefContractSchemaTest` proves `conveyor.agent_brief_contract@1`
  requires current and desired behavior, authorized scope, recovery, and
  out-of-scope/non-goal material.
- `ContractAuthorTest` proves `Conveyor.ContractForge.ContractAuthor`
  materializes a schema-valid contract from a per-Slice RoleView and preserves
  behavior, authorized scope, recovery, and out-of-scope fields.

### public/cross-Slice interface ownership + compatibility are explicit

Evidence:

- `InterfacePolicyTest` proves `Conveyor.ContractForge.InterfacePolicy`
  requires public and cross-Slice interfaces to state owner, lock level,
  compatibility policy, rollout intent/environment, and migration safety.
- `AgentBriefContractSchemaTest` and `ContractAuthorTest` keep constraints and
  claims in the normalized contract source references so interface authority is
  traceable to the contract input.

### internal implementation freedom is preserved

Evidence:

- `InterfacePolicyTest` proves internal interfaces may remain informational and
  do not require public/cross-Slice compatibility authority.
- `ContractArchetypeTemplatesTest` proves archetype templates describe contract
  shape and review lenses without granting implementation authority.
- `ContractAuthorTest` proves contract-author materialization emits
  `authority_effect: :none`.

### machine ACs have a falsifying condition + seeds

Evidence:

- `VerificationObligationDeriverTest` proves
  `Conveyor.ContractForge.VerificationObligationDeriver` blocks
  machine-checkable acceptance criteria that lack falsifying conditions.
- `FalsifierSeedDeriverTest` proves
  `Conveyor.ContractForge.FalsifierSeedDeriver` emits compiler-owned falsifier
  seeds for table negative rows, boundary transforms, forbidden predicates,
  property counterexamples, metamorphic relations, and interface
  incompatibility cases.
- `ContractAuthorTest` proves the contract-author RoleView feeds
  VerificationObligation and falsifier-seed derivation while keeping the
  serialized AgentBrief contract schema-valid.

### a scope addition requires approval

Evidence:

- `InterfacePolicyTest` proves protected-path scope additions without approval
  are blocking findings.
- `AgentBriefContractSchemaTest` requires authorized scope to be explicit,
  including protected paths, before a contract can validate.

### every Slice explains why it is independently verifiable

Evidence:

- `VerificationObligationDeriverTest` proves each acceptance criterion maps to a
  concrete VerificationObligation with an evidence requirement.
- `ContractAuthorTest` proves a per-Slice contract derives verification
  obligations and falsifier seeds from the Slice acceptance criteria.
- `ContractArchetypeTemplatesTest` proves archetype templates include required
  acceptance sections and review lenses for independently verifiable Slice
  contracts.

## Release Report

| Evidence source | Failed cases represented | Excluded cases |
| --- | --- | --- |
| `AgentBriefContractSchemaTest` | missing required AgentBrief fields, invalid digests, non-schema contract output | none |
| `ContractArchetypeTemplatesTest` | incomplete archetype templates, missing review lenses, template/schema drift | none |
| `InterfacePolicyTest` | public/cross-Slice interfaces without ownership, compatibility, rollout, migration safety, or scope-addition approval | none |
| `VerificationObligationDeriverTest` | machine-checkable ACs without falsifying conditions, missing evidence requirements | none |
| `FalsifierSeedDeriverTest` | dropped compiler-derived falsifier seeds, missing seed families | none |
| `ContractAuthorTest` | RoleView normalization drift, accidental authority emission, invalid AgentBrief output, dropped derivation input | none |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the focused P2-B1 Contract Forge test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `mix format ... --check-formatted`
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
