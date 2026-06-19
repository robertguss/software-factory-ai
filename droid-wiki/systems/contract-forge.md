# Contract forge

The contract forge in `lib/conveyor/contract_forge/` drafts AgentBrief contracts from plan requirements. It is the authoring side of the actor separation principle: the agent that writes code must not author its own acceptance contract. The forge materializes contracts from contract-author RoleViews, applies archetype templates, validates interface policy, derives verification obligations, and derives falsifier seeds.

## ContractAuthor

`lib/conveyor/contract_forge/contract_author.ex` materializes draft AgentBrief contracts from contract-author RoleViews. The `materialize/1` function takes a role view, archetype, acceptance criteria, behavior, change class, authorized scope, risk level, rollout, recovery, and out-of-scope declarations. It:

1. Fetches the archetype template via `ArchetypeTemplates`.
2. Partitions the bounded context into requirements (REQ-*) and decisions (DEC-*).
3. Builds the contract with schema version `conveyor.agent_brief_contract@1`, source refs, archetype, change class, normalized acceptance criteria, verification obligations, authorized scope, risk (level and required review lenses), assumptions, challenge cases, rollout, recovery, out-of-scope, and claim coverage.
4. Derives verification obligations via `VerificationObligationDeriver`.
5. Derives falsifier seeds via `FalsifierSeedDeriver`.

If obligation derivation fails, the materialization is blocked with findings. The result carries the status, authority effect (always `:none` since the forge drafts but does not approve), role view, contract, obligations, falsifier seeds, and findings.

## ArchetypeTemplates

`lib/conveyor/contract_forge/archetype_templates.ex` defines deterministic contract archetype templates. These are minimum obligation floors, not prompt folklore. Contract authors may add stricter obligations, but downstream tools can rely on these stable keys. Archetypes include:

- **`bugfix_regression`** — regression reproduced, fix verifies regression, no neighbor regression. Lenses: bug reproduction, test integrity.
- **`crud_endpoint`** — CRUD paths, validation errors, authorization boundary. Lenses: API compatibility, data integrity.
- **`pure_refactor`** — behavior lock, public interface unchanged, performance not worse. Lenses: behavior equivalence, interface stability.
- **`schema_migration`** — forward migration, rollback restore, backfill validation. Lenses: migration safety, data integrity.
- **`dependency_update`** — lockfile delta reviewed, compatibility suite, security advisory check. Lenses: supply chain, compatibility.
- **`public_interface_change`** — compatibility policy, consumer impact, versioning or migration. Lenses: API compatibility, consumer contracts.
- **`security_hardening`** — and additional archetypes.

Each template carries minimum obligations, required review lenses, and falsifier seed families.

## InterfacePolicy

`lib/conveyor/contract_forge/interface_policy.ex` performs deterministic interface lock, compatibility, rollout, and migration safety checks. The `validate/1` function checks that externally visible interfaces have strong lock levels (`strict`, `compatible_superset`, `review_required`), non-weak compatibility policies (not `none` or `informational`), and rollout declarations. The `validate_migration/1` function checks migration safety profiles for forward migration, rollback restore, and backfill validation requirements.

## FalsifierSeedDeriver

`lib/conveyor/contract_forge/falsifier_seed_deriver.ex` derives compiler-owned falsifier seeds from upgraded AgentBrief contracts. It extracts seeds from six acceptance criterion fields: falsifying conditions (`table_negative_row`), boundary examples (`boundary_transform`), forbidden predicates (`forbidden_predicate`), property counterexamples (`property_counterexample`), metamorphic relations (`metamorphic_relation`), and interface incompatibility cases (`interface_incompatibility`). Each seed carries a stable id, family, source acceptance criterion id, payload, and a `preservation_required` flag.

The `verify_preserved/2` function checks that all original seeds are present or explicitly superseded in a translated set, producing `falsifier_seed_dropped` blocking findings for any missing seeds.

## VerificationObligationDeriver

`lib/conveyor/contract_forge/verification_obligation_deriver.ex` derives `VerificationObligation` projections from upgraded AgentBrief contracts. For each acceptance criterion, it checks that machine-checkable criteria have at least one falsifying condition (blocking finding `acceptance_criterion_missing_falsifier` if missing), then builds an obligation with schema version `conveyor.verification_obligation@1`, slice id, acceptance ref, obligation kind, required flag, evidence requirement ref, and pending status.

## Key source files

| File | Purpose |
| ---- | ---- |
| `lib/conveyor/contract_forge/contract_author.ex` | Materializes draft AgentBrief contracts from contract-author RoleViews. |
| `lib/conveyor/contract_forge/archetype_templates.ex` | Deterministic contract archetype templates with minimum obligations. |
| `lib/conveyor/contract_forge/interface_policy.ex` | Interface lock, compatibility, rollout, and migration safety checks. |
| `lib/conveyor/contract_forge/falsifier_seed_deriver.ex` | Derives compiler-owned falsifier seeds from acceptance criteria. |
| `lib/conveyor/contract_forge/verification_obligation_deriver.ex` | Derives VerificationObligation projections from contracts. |

## Related pages

- [Contract critic](contract-critic.md) — criticizing and repairing drafted contracts
- [Planning compiler](planning-compiler.md) — decomposition and work graph lowering
- [Contract management](../features/contract-management.md) — contract lock lifecycle
- [Contract lock](../primitives/contract-lock.md) — contract lock primitive
