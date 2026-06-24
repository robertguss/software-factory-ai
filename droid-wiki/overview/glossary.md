# Glossary

Project-specific terms used throughout the Conveyor codebase. These definitions come from `CONCEPTS.md` and the code itself.

## The factory loop

| Term | Definition |
| ---- | ---------- |
| **Run** | A single unattended execution of a selected set of slices in dependency order, identified by one run id for its whole lifetime. A run carries on past a parked slice rather than halting, and its outcome history is committed durably so an interrupted run can be resumed. |
| **Slice** | A contract-bearing unit of work. The atomic thing the factory builds and the gate judges. Named by a stable contract key (`SLICE-NNN`) that is identical across runs. Once a slice passes the gate, its result is durable and never re-executed. |
| **Epic** | A grouping of slices within a plan. Slices belong to exactly one epic. The stable key is unique per epic. |
| **Plan** | The top-level container for a project's work. A plan has requirements, epics, and slices. Imported from a `conveyor.plan@1` contract or authored via the task graph CLI. |
| **Resume** | Re-entering an interrupted run by folding its committed outcome history back into working state. Already-passed slices are replayed from the record, not re-executed. |
| **Rework** | Re-executing a slice within the same run after it fails the gate. All rework attempts belong to the same run and share its run id. |

## The verification gate

| Term | Definition |
| ---- | ---------- |
| **Trust gate** | The staged verification gate that decides whether a slice's work may merge without a human. Runs progressively stronger checks, combines them into a calibrated score, and can withhold judgment when confidence is low. |
| **Abstain** | The gate's verdict that is neither accept nor reject. When a signal is missing or untrustworthy, the gate withholds judgment and routes the slice to a human review queue. Abstention is what lets work merge unattended only when the gate is confident. |
| **Replay fidelity** | Whether a run's execution reproduces a known baseline. A verification dimension the gate can consider but which stays dormant until a real reproducibility check exists. |
| **Replay divergence** | The gate-facing verdict for replay fidelity, in one of three states: reproduced (`none`), diverged, or no-baseline (`baseline-absent`). A diverged verdict makes the gate abstain. |

## Contracts and evidence

| Term | Definition |
| ---- | ---------- |
| **Contract lock** | An immutable, machine-checkable acceptance contract that locks the public interface, required tests, and definition of done for a slice. Authored by a different actor than the implementer. |
| **Agent brief** | The implementation brief for a slice. Contains the locked instructions the agent follows. |
| **Test pack** | The set of tests associated with a slice, used by the gate's test execution stage. |
| **Run spec** | The immutable specification for one production width-1 slice attempt. Assembled from the slice's locked contract, work graph, and workspace context. |
| **Run attempt** | The parent identity for one execution attempt of a slice. Tracks status, outcome, base commit, and trace id. Multiple attempts (reworks) share the same slice. |
| **Station run** | A single execution of a station (implementer, evidence recorder, context scout, etc.) within a run attempt. |

## Agent execution

| Term | Definition |
| ---- | ---------- |
| **Station** | The execution abstraction. Each station implements the `Conveyor.Station` behaviour with a `station_key`, `station_spec`, `input_sha256`, `effects`, and `run` callback. The wrapper handles idempotency, leases, and artifacts. |
| **Adapter** | The coding-agent backend (Codex, Claude Code, Gemini CLI, fake, reference solution, mock degraded). Each implements the `Conveyor.AgentRunner` behaviour. |
| **Sandbox** | An isolated Docker container where agent execution happens. Each slice gets its own workspace. |
| **Credential lease** | A short-lived, revocable grant of environment variables to a sandbox. The `CredentialBroker` issues and revokes leases without persisting secret values. |

## Policy and safety

| Term | Definition |
| ---- | ---------- |
| **Policy profile** | A named set of command allowlists, denylists, env policies, and network policies. Profiles include `explore`, `implement`, `verify`, `release`, and `maintenance`. |
| **Normalized command** | A parsed, validated command ready for policy evaluation. Contains executable, argv, env keys, and network mode. |
| **Emergency stop** | An engaged stop state that blocks new station starts, provider calls, tool calls, claim publication, and external effects. Requires a `HumanDecision` to clear. |
| **Design laws** | Ten executable invariants governing the system. Each law ties to feature beads, invariant tests, and enforcing modules. See `lib/conveyor/design_laws.ex`. |

## Data and events

| Term | Definition |
| ---- | ---------- |
| **Factory** | The Ash domain (`Conveyor.Factory`) that manages all database-backed resources (48 resources). |
| **Ledger** | The append-only audit log (`Conveyor.Ledger`). Every state change is recorded as a `LedgerEvent` with an idempotency key. |
| **Run read model** | A read-only "run story" folded from a run's committed ledger stream. The data source for the CLI and LiveView. |
| **Cassette** | A recorded sequence of agent interactions that can be replayed for $0. Used for evals and deterministic testing. |

## Evaluation

| Term | Definition |
| ---- | ---------- |
| **Eval** | An evaluation run that measures the factory's quality. Eval types include lift duel, mutant gauntlet, golden thread, and sentinel tournament. |
| **Lift duel** | A comparison between the factory's production path and a vanilla agent path, measuring the "lift" the factory provides. |
| **Rung** | An eval maturity level. Rung 0 is DB-free property tests. Rung 1 is DB-backed integration tests. |
| **Scorecard** | An aggregated eval report (`conveyor.eval_scorecard@1`) with blocking metrics like false pass rate. |
