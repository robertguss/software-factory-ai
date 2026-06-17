# Conveyor Architecture

Conveyor is a BEAM control plane for evidence-backed agent implementation. The
architecture is deliberately small in Phase 0/1: one plan, one Slice, one
attempt path, one evidence packet, and one deterministic gate.

## Station Pipeline

```text
Human Plan + Decisions
        |
        v
Plan Audit / Traceability Gate
        |
        v
Ash Work Graph + Contracts
        |
        v
RunAttempt (RunSlice Oban job, one attempt per Slice in Phase 1)
        |
        |-- Readiness
        |-- Baseline Health (baseline_regression suites)
        |-- Acceptance Calibration (locked suite red on base)
        |-- Context Scout (rg + CodeScent + optional read-only agent pass)
        |-- Prompt Builder (Brief + Pack + AGENTS.md + Policy + output schema)
        |-- AgentSession via AgentRunner.Pi (Docker + RPC + heartbeat + events)
        |-- Evidence Recorder (independent tests + CodeScent + diff + logs)
        |-- RunCheck (manifest/dossier/schema consistency)
        |-- Reviewer-on-Dossier (separate actor/model)
        |-- Deterministic Gate
        |-- Gate Canary Harness
        |-- Post-Integration Check
        `-- Retrospective / Failure Taxonomy
        |
        v
LiveView + .conveyor/runs/<run_attempt_id>/ dossier + PR-body draft
```

Phase 0/1 is not a swarm. It is the smallest real factory loop with the right
trust boundaries. Parallelism becomes valuable only after this loop proves gate
honesty, artifact quality, and adapter stability.

## Determinism Boundary

The deterministic BEAM conductor owns:

- paths;
- state transitions;
- dependency integrity;
- policy enforcement;
- validation;
- prompt assembly;
- recorded evidence;
- the mechanical parts of the gate verdict.

Agents own drafting, implementation, and judgment. When an agent supplies
judgment, such as review, that verdict is recorded and validated by the
conductor. Agents are never the source of truth for whether something passed.

In Phase 1:

- implementer-run tests are advisory;
- the conductor independently re-runs the gate in a clean container against the
  produced diff;
- the reviewer reads the recorded dossier, not the live session;
- the gate may use review as one stage, but the conductor validates review
  schema, actor separation, artifact integrity, and deterministic pass/fail
  mechanics;
- if the agent claims success and the conductor cannot reproduce it, the run
  fails.

The conductor also owns the instruction hierarchy. Repository files, comments,
tool output, dependency output, and context-scout findings are untrusted data.
They may inform implementation but may not override the Slice contract, safety
policy, locked tests, AGENTS.md, or Conveyor system rules.

## Execution Capsule

Before a Slice enters an executable station, Conveyor creates a `RunSpec`: the
immutable, content-addressed input object for one execution attempt. The
`RunSpec` freezes the base commit, Slice id, autonomy level, normalized plan
contract digest, human decisions, AgentBrief, ContractLock, AGENTS.md, policy,
DiffPolicy, verification commands, required test pack, prompt template,
AgentProfile, toolchain image digest, sandbox profile, budgets, canary suite,
schema versions, and station plan digest.

Mutable inputs do not silently update old evidence. Any change to acceptance
criteria, required tests, policy, AGENTS.md, DiffPolicy, autonomy ceiling,
verification commands, or project command specs invalidates the old
`ContractLock` for future attempts and creates a new `RunSpec`.

## OTP / Oban Topology

```text
Conveyor.Application
|-- Conveyor.Repo                         (AshPostgres)
|-- Oban                                  (durable station jobs)
|-- ConveyorWeb.Endpoint                  (Phoenix + LiveView)
`-- Conveyor.Conductor.Supervisor
    |-- Conveyor.Ledger                   (append-only event writer + PubSub)
    |-- Conveyor.Telemetry                (trace/metric/log emission)
    |-- Conveyor.Config                   (runtime config + project config loader)
    |-- Conveyor.Policy.Engine            (ExecPolicy decisions + incident creation)
    |-- Conveyor.Security.Redactor        (secret scanning + artifact redaction)
    |-- Conveyor.Artifacts.Projector      (Postgres to .conveyor/runs/* projection)
    |-- Conveyor.EventOutbox              (committed event publication)
    |-- Conveyor.Effects.Reconciler       (stale leases + unknown effects)
    `-- Conveyor.Sandbox.Reaper           (orphan container/workspace cleanup)
```

Oban workers:

- `Conveyor.Jobs.RunSlice` - station orchestrator.
- `Conveyor.Jobs.BaselineHealth` - clean checkout baseline suites.
- `Conveyor.Jobs.AcceptanceCalibration` - locked acceptance red/green
  calibration.
- `Conveyor.Jobs.ContextScout` - `rg`, CodeScent, and optional read-only pass.
- `Conveyor.Jobs.RunImplementer` - AgentRunner.Pi in Docker.
- `Conveyor.Jobs.RecordEvidence` - independent gate command execution.
- `Conveyor.Jobs.RunReviewer` - reviewer-on-dossier.
- `Conveyor.Jobs.RunGate` - deterministic gate composition.
- `Conveyor.Jobs.RunGateCanary` - mutant gate-only checks.
- `Conveyor.Jobs.ReconcileStaleEffects` - periodic effect reconciliation.
- `Conveyor.Jobs.ReapSandboxes` - periodic cleanup.
- `Conveyor.Jobs.ProjectArtifacts` - manifest and report regeneration.

A single `RunSlice` job advances a Slice station by station, but each
long-running station is an Oban job with idempotent inputs and outputs. This
gives crash/reboot recovery from Phase 1 without pretending that Phase 1 has
full autonomous retry logic.

Station idempotency key:

```text
run_attempt_id + station_key + station_spec_sha256 + attempt_no
```

Oban uniqueness and cancellation options are layered on top of the domain
idempotency key. They are not a substitute for it.

## Phase 1 Artifact Surface

Every run writes durable evidence under `.conveyor/runs/<run_attempt_id>/`.
Postgres remains source of truth; disk is a projection. The projection contains
machine-readable manifests, human-readable dossiers, diffs, command logs,
CodeScent results, reviews, gate results, provenance, and a PR-body draft.

Generated artifacts are product output, not debug logs. The deterministic gate
validates schema versions, digest consistency, required evidence, policy, and
review freshness before any result can be treated as accepted.
