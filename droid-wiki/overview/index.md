# Conveyor

Conveyor is an AI-first software factory on the BEAM. You bring a plan; Conveyor decomposes it into a dependency-ordered, contract-bearing work graph and runs a fleet of AI coding agents (Codex, Claude Code, Gemini CLI) in isolated containers to implement it. The verification gate decides what merges without you, 24/7, as autonomously as the gate can be trusted to allow.

The system is built in Elixir/OTP with Phoenix LiveView for the dashboard, Ash for the data model, Postgres for persistence, and Oban for background job orchestration. Docker provides container isolation for each agent's workspace.

## What Conveyor does

Conveyor turns a human-authored plan into autonomous code production. The pipeline is: plan import, work graph decomposition, contract authoring, agent execution in isolated sandboxes, evidence recording, gate verification, and integration. Each step is event-sourced, so runs are reproducible and debuggable after the fact.

The core insight is that contracts cap quality. Every task (called a "slice") carries an immutable, machine-checkable acceptance contract authored by a different actor than the implementer. The gate checks the contract against recorded evidence and decides: accept, reject, or abstain (route to human review).

## Who uses it

Conveyor targets teams who want autonomous code generation with safety guarantees. The operator interacts through a mix CLI (`mix conveyor.*`) and a Phoenix LiveView dashboard. The system is in active development, currently focused on a width-1 serial autonomous loop.

## Quick links

- [Architecture](architecture.md) - system architecture and component relationships
- [Getting started](getting-started.md) - prerequisites, install, build, test
- [Glossary](glossary.md) - domain vocabulary
- [How to contribute](../how-to-contribute/index.md) - working in this codebase
- [Systems](../systems/index.md) - internal building blocks
- [Features](../features/index.md) - cross-cutting capabilities
- [Primitives](../primitives/index.md) - foundational domain objects
- [Security](../security.md) - trust boundaries and safety design
- [Background](../background/index.md) - design decisions and pitfalls
- [Reference](../reference/index.md) - configuration, data models, dependencies
