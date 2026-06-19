# Features

Conveyor's capabilities are the cross-cutting behaviors that span station boundaries. They are not single modules but coordinated mechanisms that the runtime relies on for honest execution, isolation, evidence, and operator control.

## Cross-cutting capabilities

- [Station pipeline](station-pipeline.md) — the core execution flow that advances a RunAttempt station by station with idempotent wrappers, leases, and ledger events.
- [Contract management](contract-management.md) — how contracts are drafted, criticized, locked, and evolved into new locks when requirements change.
- [Sandbox isolation](sandbox-isolation.md) — Docker-backed workspace materialization, network policy, hardened container defaults, and reaping.
- [Credential broker](credential-broker.md) — short-lived scoped credential leases that never persist secret values.
- [Prompt building](prompt-building.md) — versioned implementation prompts with explicit instruction-source trust labels and an untrusted banner.
- [Event sourcing](event-sourcing.md) — append-only idempotent ledger, transactional outbox, segment writer, and durable catch-up replay.
- [Emergency stop](emergency-stop.md) — global emergency stop, shadow controls, and budget reservations that block work before it starts.
- [AGENTS.md generation](agents-md-generation.md) — generation and linting of repo-local project instruction files from Conveyor config.
- [CLI tools](cli-tools.md) — the operator mix task surface for init, lint, audit, run, verify, doctor, and diagnostics.

## Related areas

- [Systems](../systems/index.md) — internal building blocks (planning compiler, gate, policy engine, evidence recording, agent runner, sandbox).
- [Primitives](../primitives/index.md) — foundational domain objects (slice, run attempt, contract lock).
- [Architecture](../overview/architecture.md) — system topology, OTP supervision, and the determinism boundary.
