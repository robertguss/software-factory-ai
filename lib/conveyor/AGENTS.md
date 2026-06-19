# PROJECT KNOWLEDGE BASE

## OVERVIEW

`lib/conveyor/` holds the core runtime domains for planning, station execution,
evidence, policy, review, and gate decisions.

## WHERE TO LOOK

| Task | Location | Notes |
| --- | --- | --- |
| OTP startup | `application.ex` | Supervision tree and process boundaries. |
| Ash resources | `factory.ex`, `factory/` | Database-backed domain model. |
| Planning compiler | `planning/` | Plan/spec lowering, graph analysis, audits. |
| Agent execution | `agent_runner/`, `jobs/run_*.ex` | Runner adapters and Oban jobs. |
| Evidence model | `evidence/`, `artifacts/`, `cassettes/` | Artifact capture, replay, comparison. |
| Gate behavior | `gate.ex`, `gate/` | Verification stages and finalizer. |
| Safety policy | `policy/`, `security/`, `credential_broker.ex` | Command normalization and guardrails. |
| AGENTS generation | `agents_md.ex`, `agents_md/linter.ex` | Project instruction generator/linter. |

## CONVENTIONS

- Keep resource modules and migrations aligned; Ash resource changes usually
  imply `priv/repo/migrations/` changes and focused tests.
- Model state machines explicitly with known states and database constraints.
- Keep policy decisions, effect attempts/receipts, evidence, and authority
  events separate; do not collapse them into convenience structs.
- Prefer deterministic compiler-style modules for planning transformations.
- Use Oban jobs as orchestration edges, not as hidden business-rule storage.
- Keep public structs and result types explicit; callers need inspectable gate,
  policy, and evidence reasons.

## ANTI-PATTERNS

- Do not let web/UI projection state authorize work or repair history.
- Do not write code that treats redacted evidence as equivalent to raw artifact
  bytes.
- Do not bypass policy normalization when adding command execution paths.
- Do not make a runner/reviewer/gate module both produce and approve its own
  acceptance contract.
- Do not hide destructive filesystem, git, network, or credential operations
  behind harmless-looking helper names.
