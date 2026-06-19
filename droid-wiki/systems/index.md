# Systems

Conveyor's runtime is composed of internal building blocks, each with a clear boundary and contract. These systems live under `lib/conveyor/` and implement the deterministic conductor side of the determinism boundary: planning, gating, policy, evidence, artifacts, agent execution, sandboxing, replay, qualification, and statistical quality. This page lists them with one-line descriptions and links to the individual pages.

## Systems

| System | Criticality | Description |
| ---- | ---- | ---- |
| [Planning compiler](planning-compiler.md) | critical | Pure-function compiler passes that lower plans into work graphs, with auditing, decomposition, selective recompilation, and pilot retrospectives. |
| [Gate](gate.md) | critical | Deterministic stage-composed verification that decides whether a run attempt passes, fails, or needs rework. |
| [Policy engine](policy-engine.md) | normal | Command normalization, allowlist/denylist enforcement, budget guards, and violation handling for agent tool calls. |
| [Evidence recording](evidence-recording.md) | critical | Independent capture of machine evidence, diffs, logs, acceptance mapping, and verification reruns in clean containers. |
| [Artifact projection](artifact-projection.md) | normal | Content-addressed blob storage and Postgres-to-disk projection of run artifacts. |
| [Agent runner](agent-runner.md) | critical | Behaviour and adapters for launching, monitoring, capturing, and canceling coding agents in isolated containers. |
| [Sandbox](sandbox.md) | normal | Docker-backed container lifecycle, network isolation, workspace materialization, and cleanup. |
| [Cassettes](cassettes.md) | normal | Recording and replay of station runs for freshness checks, deterministic replay, and divergence diagnostics. |
| [Qualification](qualification.md) | normal | Offline-verifiable bundles, gate evaluation, grant issuance, and phase-next decisions for scope authorization. |
| [Contract forge](contract-forge.md) | normal | Drafting of AgentBrief contracts from plan requirements, with archetype templates, interface policy, and falsifier seeds. |
| [Contract critic](contract-critic.md) | normal | Multi-lens contract criticism, cheapest-wrong attacks, independence profiles, and bounded repair loops. |
| [Battery](battery.md) | normal | Live statistical quality sampling, measurement studies, secondary confirmation, and release reporting. |

## Related pages

- [Architecture](../overview/architecture.md) — system topology, OTP supervision, station pipeline
- [Station pipeline](../features/station-pipeline.md) — execution flow across stations
- [Contract management](../features/contract-management.md) — contract lock lifecycle
- [Primitives](../primitives/index.md) — foundational domain objects (slice, run attempt, evidence, contract lock)
