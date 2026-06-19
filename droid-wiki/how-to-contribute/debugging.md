# Debugging

Conveyor is a deterministic core with stochastic agents at the edges, so debugging splits into two modes: debugging the BEAM conductor (logs, doctor, replay, evidence inspection) and debugging agent runs (gate failures, policy violations, sandbox issues). This page is a runbook for both.

The first tool to reach for is `mix conveyor.doctor`. It checks prerequisites, config, sandbox constraints, and project files, and it fails hard when a required constraint is missing. The second is the run evidence under `.conveyor/runs/<run_attempt_id>/`, which is the durable projection of what actually happened. The third is `mix conveyor.replay`, which rebuilds the human timeline from the append-only ledger.

## Logs

Logger is configured in `config/config.exs`:

```elixir
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
```

Dev logs are trimmed in `config/dev.exs`:

```elixir
config :logger, :console, format: "[$level] $message\n"
```

Test logs are set to warning and above in `config/test.exs`:

```elixir
config :logger, level: :warning
```

Production logs are set to info in `config/prod.exs`. Runtime production configuration, including the database URL and secret key base, is loaded from env vars in `config/runtime.exs`.

When debugging a specific run, the structured evidence under `.conveyor/runs/` is more useful than console logs. Logs are best-effort observation; the ledger and the projected artifacts are the source of truth for what happened and when.

## The doctor command

`mix conveyor.doctor` runs prerequisite and health checks for a Conveyor project. It is the first thing to run when something feels off.

```bash
mix conveyor.doctor
mix conveyor.doctor /path/to/project
```

The doctor (`lib/conveyor/doctor.ex`) checks, in order:

- Config load from `.conveyor/config.toml`.
- Runtime versions (Elixir, OTP, Phoenix, Ash, Oban) against `Conveyor.ToolMatrix.latest_tested_versions()`.
- Oban is configured with `Conveyor.Repo`.
- Postgres is reachable.
- Docker is installed and reachable.
- Docker sandbox constraints (seccomp, no-new-privileges, rootless preferred) match `Conveyor.Sandbox.DockerProfile.required_security_options()`.
- Git is installed and the project path is a git repository.
- Sample repo path and base ref are valid and clean (when configured).
- Project files exist: `AGENTS.md`, at least one `verify` command spec, all five policy profiles, writable `runs_dir` and `blobs_dir`.
- Optional adapters (CodeScent, Pi, provider credential) are present when configured.
- Secret posture: doctor fails if run with `MIX_ENV=prod`.

The doctor returns a `Result` with findings, each a `Finding` with `check`, `severity` (`:failure` or `:warning`), `message`, and `next_actions`. Exit codes follow `Conveyor.Cli.ExitCodes`: success, malformed-artifact-or-schema failure (config issues), policy-or-secret safety violation, or infrastructure/doctor failure. The Mix task in `lib/mix/tasks/conveyor.doctor.ex` formats the result and halts with the exit code.

## Inspecting run evidence

Every run writes durable evidence under `.conveyor/runs/<run_attempt_id>/`. Postgres is the source of truth; disk is a projection. The projection contains:

- `manifest.json` - machine-readable run manifest.
- `dossier.md` - human-readable run report with diff, acceptance mapping, commands, quality delta, reviewer verdict, and gate result.
- `evidence.json` - aggregated machine evidence.
- `review.json` - reviewer verdict.
- `gate.json` - deterministic gate verdict and freshness keys.
- diffs, command logs, CodeScent results, provenance, and a PR-body draft.

Read these files together. The dossier cites machine artifact digests, so a claim in the dossier should be traceable to a digest in the manifest. The artifact projector (`lib/conveyor/artifacts/projector.ex`) projects Postgres records to disk; the blob store (`lib/conveyor/artifacts/blob_store.ex`) handles content-addressed storage.

To inspect a specific run from the CLI:

```bash
mix conveyor.show <run_attempt_id>
```

## The replay command

`mix conveyor.replay` rebuilds the R0 human timeline from `LedgerEvent` records. The ledger is append-only and idempotent, so the timeline is deterministic.

```bash
# Rebuild the full ledger timeline
mix conveyor.replay

# Rebuild and project a single run attempt to disk
mix conveyor.replay <run_attempt_id> [--blob-root PATH] [--projection-root PATH]
```

The replay module (`lib/conveyor/replay.ex`) sorts ledger events by `occurred_at` and id, prints them as JSON lines, and can project a single run attempt through `Conveyor.Artifacts.Projector.project_run!/2`. The Mix task is in `lib/mix/tasks/conveyor.replay.ex`.

Use replay when the on-disk projection is stale or missing, or when you need to reconstruct the exact event order for a diagnosis.

## Common failure modes

### Gate failures

A gate failure means the deterministic gate (`lib/conveyor/gate.ex`) composed stage results into a fail verdict. The gate validates schema versions, digest consistency, required evidence, policy, and review freshness before any result can be treated as accepted.

To diagnose:

1. Read `gate.json` for the failed stage and the findings.
2. Read the corresponding stage evidence (for example, `evidence.json` for the RecordEvidence stage, `review.json` for the Reviewer stage).
3. Check the freshness keys in the gate result. A freshness miss means an input changed (contract, policy, AGENTS.md, diff policy, autonomy ceiling, verification commands, project command specs) and the old evidence is no longer valid for the current `RunSpec`.
4. If a canary passed, that is a stop-the-line event: the gate caught a known-bad mutant as good. Do not retry; investigate the gate.

### Policy violations

A policy violation creates an `Incident`, stops the run, records evidence, and moves the `Slice` to `policy_blocked` or `failed` depending on severity. Phase 1 prefers false positives over silent policy bypass.

To diagnose:

1. Find the `Incident` record and the `PolicyDecision` it cites. Every consequential action must cite a versioned `PolicyDecision` with stable reason codes.
2. Check the policy profile in `.conveyor/policies/<profile>.toml`. The five profiles are `explore`, `implement`, `verify`, `release`, and `maintenance`.
3. Check the command spec in `.conveyor/config.toml`. Policy evaluation order is: reject raw shell, resolve executable, normalize cwd/symlinks/roots, reject writes outside the workspace, allow only configured executable families, apply the denylist, record the decision.
4. If the violation is a denylist hit, check `SAFETY_POLICY.md` for the minimum denylist. Denylist entries are defense-in-depth; the primary boundary is the command grammar and sandbox.

Do not loosen policy to make a run pass. If a policy block is wrong, fix the policy through the normal ADR/schema path and re-run.

### Sandbox issues

Sandbox issues usually show up as Docker errors or doctor failures. The sandbox (`lib/conveyor/sandbox/`) runs agents in isolated Docker containers with these defaults:

- non-root user, rootless Docker where available
- no privileged containers, no Docker socket mount, no host home mount
- read-only mounts for contracts, policies, and `.conveyor`
- read-write mount only for the materialized workspace
- `no-new-privileges`, seccomp or AppArmor where available
- CPU, memory, process, output-size, and wall-clock limits
- `network=none` by default, allowlisted egress proxy only for approved calls

To diagnose:

1. Run `mix conveyor.doctor` and look for `sandbox_constraints` or `sandbox_rootless` findings.
2. Check that Docker is running and supports the required security options.
3. If a sandbox failed to start, check the `StationRun` and `WorkspaceMaterialization` records for the error.
4. If the agent could not reach an allowlisted endpoint, check the egress policy for the station profile. No station's allowed egress may include the conductor's own network; the Postgres database, ledger, and internal services must be unreachable from the sandbox.

### Credential broker issues

The credential broker (`lib/conveyor/credential_broker.ex`) issues short-lived, scoped `CredentialLease` records. Raw provider secrets are not injected into worker containers unless no safer adapter mode exists.

To diagnose:

1. Check the `CredentialLease` records for the run spec or station run.
2. A lease is `active`, `revoked`, or `expired`. Expired or revoked leases cannot be reused.
3. `expire_stale!/1` revokes leases past their `expires_at`; the doctor warns if `CONVEYOR_PROVIDER_TOKEN` is absent.
4. If the agent saw a credential in a prompt or log, that is a secret-exposure incident. Check the redactor (`lib/conveyor/security/redactor.ex`) and the redaction policy for the artifact.

### Stale worker or duplicate effect

If a station worker crashes and a retry takes over, the lease epoch and fencing token prevent the stale worker from publishing. Effect attempts and receipts (`lib/conveyor/factory/effect_attempt.ex`, `lib/conveyor/factory/effect_receipt.ex`) reconcile pending or ambiguous external effects before repeating or compensating.

To diagnose:

1. Check the `StationRun` lease epoch and the `EffectAttempt`/`EffectReceipt` records.
2. An `outcome_unknown` effect attempt means the external system may have accepted the effect even though the worker crashed before recording success. Reconcile before retrying.
3. `non_reconcilable` external effects are prohibited at L1 unless explicitly human-authorized.

## Key source files

| File | Purpose |
| ---- | ------- |
| `lib/conveyor/doctor.ex` | Prerequisite and health checks, finding aggregation, exit codes. |
| `lib/mix/tasks/conveyor.doctor.ex` | Doctor Mix task wrapper. |
| `lib/conveyor/replay.ex` | Ledger timeline rebuild and run projection. |
| `lib/mix/tasks/conveyor.replay.ex` | Replay Mix task wrapper. |
| `lib/conveyor/artifacts/projector.ex` | Projects Postgres records to `.conveyor/runs/<id>/`. |
| `lib/conveyor/artifacts/blob_store.ex` | Content-addressed blob storage (SHA-256). |
| `lib/conveyor/credential_broker.ex` | Issues and revokes short-lived credential leases. |
| `lib/conveyor/security/redactor.ex` | Secret scanning and redaction for projected artifacts. |
| `lib/conveyor/gate.ex` | Deterministic gate composition and verdict. |
| `lib/conveyor/factory/incident.ex` | Policy, safety, and operational incident record. |
| `config/config.exs` | Logger and Oban config. |
| `config/runtime.exs` | Production runtime config from env vars. |

See [Testing](testing.md) for diagnosing test failures, [Tooling](tooling.md) for the lint and type-check commands, and [Security](../security.md) for the threat model and enforcement layers.
