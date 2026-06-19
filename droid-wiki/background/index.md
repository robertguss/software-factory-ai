# Background

Conveyor's design is driven by a set of accepted ADRs, a small set of anti-patterns, and the migration context from Phase 0/1 to Phase 1.5/2. This page is the entry point for the why behind the code.

The code is implementation-heavy now, and the root docs are still the authority for product direction and safety constraints. When the code and the docs disagree, the docs win. When an ADR and `docs/BRAINSTORM.md` disagree, the ADR wins.

## Sub-pages

- [Design decisions](design-decisions.md) - the 22 accepted ADRs that shape the architecture, with a one-line summary of each.
- [Pitfalls and danger zones](pitfalls.md) - the known anti-patterns from the `AGENTS.md` hierarchy, and why each one is a trap.

## Where the authority lives

| Surface | Location | Role |
| ------- | -------- | ---- |
| ADRs | `docs/adrs/` | Accepted architectural decisions. Override brainstorm text when they conflict. |
| Living strategy | `docs/BRAINSTORM.md` | Unresolved design context. Treat as living, not final. |
| Phase plans | `docs/2_implementation_plans/`, `docs/phase-1.5/`, `docs/phase-2/` | Slice-level acceptance gates and artifacts. |
| Schemas | `docs/schemas/` | Canonical schema registry and examples. Use `conveyor.<name>@1.json` naming. |
| Policies | `docs/policies/` | Machine-readable policy decisions. Affect runtime authority and safety. |
| Safety policy | `SAFETY_POLICY.md` | Threat model, enforcement layers, sandbox run spec, credential broker. |
| Autonomy levels | `AUTONOMY_LEVELS.md` | L0-L4 autonomy dial definitions. |
| Project knowledge base | `AGENTS.md` | Generated project instructions; the root file covers this repo. |

## Migration context

Phase 0/1 proved the station loop and gate canaries at CLI scale. Phase 1.5 inserts four increments between Phase 1 and Phase 2 to preserve the two public release gates (`qualification_gate` and `phase2_gate`) while creating smaller stopping points for evidence, schemas, and the generated-contract path. The program can validly stop after P15-B with a qualified, diagnosable, single-slice factory; that is an accepted outcome, not a failed Phase 2.

See [Design decisions](design-decisions.md) for the ADRs that encode this and [Pitfalls and danger zones](pitfalls.md) for the anti-patterns that keep the migration honest.
