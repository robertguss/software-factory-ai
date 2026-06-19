# PROJECT KNOWLEDGE BASE

## OVERVIEW

`docs/` is a contract and decision surface for Conveyor, not a notes dump.

## STRUCTURE

```
docs/
├── BRAINSTORM.md              # living strategy and unresolved design context
├── adrs/                      # accepted architectural decisions
├── 2_implementation_plans/    # phase implementation plan material
├── phase-1.5/                 # slice-level acceptance gates and artifacts
├── phase-2/                   # later-phase release and gate artifacts
├── policies/                  # machine-readable policy decisions
├── schemas/                   # canonical schema registry and examples
└── future-schemas/            # parked schema ideas, not active registry
```

## WHERE TO LOOK

| Task | Location | Notes |
| --- | --- | --- |
| Understand current intent | `BRAINSTORM.md` | Treat as living strategy, not final authority. |
| Check durable decisions | `adrs/` | ADRs override brainstorm text when they conflict. |
| Add contract schemas | `schemas/` | Use `conveyor.<name>@1.json` naming and update registry context. |
| Trace phase gates | `phase-1.5/`, `phase-2/` | Keep gate docs tied to concrete acceptance evidence. |
| Change policy decisions | `policies/` | Policy docs affect runtime authority and safety. |

## CONVENTIONS

- Keep ADRs numbered and decision-oriented; do not bury new authority in
  brainstorm prose.
- Schema docs are canonical artifacts. Preserve stable names, versions, and
  compatibility notes.
- Phase docs should name the slice, acceptance gate, verification commands, and
  evidence expectations.
- When contract semantics change, update the relevant ADR/schema/phase doc
  together so reviewers do not have to reconcile drift.
- Keep markdown wrapped according to the root `.prettierrc`.

## ANTI-PATTERNS

- Do not use `docs/BRAINSTORM.md` to silently override an ADR.
- Do not rename schema files casually; references are content-addressed and
  versioned elsewhere.
- Do not describe UI, CLI, or static reports as authority. They are projections.
- Do not loosen evidence, policy, or acceptance language to match current code.
