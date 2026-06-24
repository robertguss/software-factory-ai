# Features

Cross-cutting capabilities that span multiple systems. Each feature page
documents how a capability works end to end, its integration points, and entry
points for modification.

## Pages

| Feature | Summary |
| ------- | ------- |
| [Station pipeline](station-pipeline.md) | Execution abstraction that wraps each discrete step in a run attempt with idempotency, leases, and effects. |
| [Contract management](contract-management.md) | Authoring, locking, and verification of immutable acceptance contracts for slices. |
| [Sandbox isolation](sandbox-isolation.md) | Docker container isolation with network and filesystem policies for agent workspaces. |
| [Credential broker](credential-broker.md) | Issues and revokes short-lived credential leases to sandboxes without persisting secret values. |
| [Prompt building](prompt-building.md) | Assembles agent prompts from locked briefs, context packs, and run specs. |
| [Event sourcing](event-sourcing.md) | Append-only audit ledger that makes every state change durable, replayable, and crash-survivable. |
| [Emergency stop](emergency-stop.md) | Kill switch that halts the factory by blocking station starts, provider calls, and external effects. |
| [AGENTS.md generation](agents-md-generation.md) | Generates and lints project AGENTS.md content from configuration. |
| [CLI tools](cli-tools.md) | Mix task surfaces for operators: init, plan, author, run, and task graph commands. |
| [Task graph](task-graph.md) | DB-native task graph authoring and querying with dependency edges, cycle rejection, and readiness checks. |
