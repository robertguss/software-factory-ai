# Sandbox isolation

Agent execution is isolated in Docker containers so that a compromised or injected agent cannot reach the conductor, the database, or the host. Conveyor's sandbox layer materializes a workspace from a pinned base commit, runs policy-checked commands inside the container, and reaps the workspace when it is done. Docker is necessary but not sufficient: policy limits intent on top of the container limits.

## Docker sandbox runner

`Conveyor.Sandbox.DockerRunner` (`lib/conveyor/sandbox/docker_runner.ex`) is the Docker-backed implementation of the `Conveyor.Sandbox.Runner` behaviour. It provides three operations:

- `materialize/2` — prepares a workspace from the RunSpec's `base_commit`. It resolves the source repo root and project prefix via `git rev-parse`, creates a temp workspace root under `System.tmp_dir()/conveyor-workspaces`, runs `git archive` to extract the base commit into the workspace, creates a Docker container with hardened defaults, and records a `WorkspaceMaterialization` row. The `.conveyor` directory is mounted read-only so contracts and policy cannot be mutated from inside the container.
- `exec/3` — runs a `NormalizedCommand` inside the container with `docker exec`, passing only allowlisted environment keys. The working directory is translated to the in-container `/workspace` mount.
- `destroy/2` — delegates to `WorkspaceCleanup` to remove the container and apply the cleanup policy.

The workspace is mounted at `/workspace` read-write. The container runs `sleep infinity` so it stays alive across multiple exec calls within a station.

## Network policy

`Conveyor.Sandbox.NetworkPolicy` (`lib/conveyor/sandbox/network_policy.ex`) defines the network posture for sandbox containers. The default for every station is `:none`, which produces `--network none` in Docker args. Egress mode exists but raises unless an explicit external proxy network is provided.

The policy maintains a set of internal hosts that must never appear in an egress allowlist: `localhost`, `127.0.0.1`, `conductor`, `db`, `postgres`, `host.docker.internal`, and the private IP prefixes. `validate_egress_allowlist!/1` rejects any allowlist that includes a conductor or internal host. This enforces the mandatory rule from the safety policy: no sandbox profile may route to the conductor's Postgres database, ledger, or internal services.

## Sandbox profiles

`Conveyor.Sandbox.DockerProfile` (`lib/conveyor/sandbox/docker_profile.ex`) produces the hardened Docker `create` arguments. The defaults are:

- non-root user `65532:65532`
- `--network none` unless overridden
- `--security-opt no-new-privileges:true`
- `--cap-drop ALL`
- `--read-only` root filesystem
- `--tmpfs /tmp:rw,noexec,nosuid,size=64m`
- `--pids-limit 256`, `--cpus 1.0`, `--memory 512m`

`required_security_options/0` returns `["seccomp"]`. The doctor command fails hard when these constraints are unavailable for the selected policy profile.

## Workspace materialization

`Conveyor.Sandbox.Materialized` (`lib/conveyor/sandbox/materialized.ex`) is the runtime handle returned by `materialize/2`. It carries the `WorkspaceMaterialization` record, the project path, the deletable root path, the container id, and the image ref.

`Conveyor.Factory.WorkspaceMaterialization` (`lib/conveyor/factory/workspace_materialization.ex`) is the Ash resource that tracks the checkout lifecycle. It records the `purpose` (`:baseline`, `:acceptance_calibration`, `:implement`, `:gate`, `:canary`, `:post_integration`), `base_commit`, paths, container id, mount mode, head tree digest, and cleanup state. The `root_path` is persisted separately from `path` because subdirectory projects need the parent temp root removed too, and the reaper only has the DB record.

## Policy-checked execution

`Conveyor.Sandbox.PolicyExecutor` (`lib/conveyor/sandbox/policy_executor.ex`) is the seam between the sandbox and the policy engine. `execute!/4` takes a `Materialized` workspace, a `NormalizedCommand`, a `Policy`, and options, then delegates to `Conveyor.ToolExecutor` with a runner closure that calls `DockerRunner.exec/3`. The policy boundary lives in `ToolExecutor`; the sandbox only runs commands that have already been normalized and allowed.

`Conveyor.Sandbox.Runner` (`lib/conveyor/sandbox/runner.ex`) defines the behaviour and a minimal host command runner used behind `ToolExecutor` for non-Docker paths. It returns a `Result` with exit code, stdout, stderr, and duration.

## Cleanup and reaper

`Conveyor.Sandbox.WorkspaceCleanup` (`lib/conveyor/sandbox/workspace_cleanup.ex`) enforces the cleanup policy. `cleanup/2` removes the container with `docker rm -f`, then applies the policy:

- `:preserve_always` — keep the workspace
- `:preserve_on_failure` — keep only when the `failed?` option is set
- `:delete` — remove the workspace directory with `File.rm_rf/1`

It updates the `WorkspaceMaterialization` row with `cleanup_status` (`:deleted`, `:preserved`, or `:failed`) and `cleaned_at`. `tree_sha256/1` computes a content-addressed digest of the workspace tree by walking files, sorting them, and hashing their relative paths and contents.

`Conveyor.Sandbox.Reaper` (`lib/conveyor/sandbox/reaper.ex`) is a conductor child that reaps orphaned workspaces. `reap!/1` reads all `WorkspaceMaterialization` records with `cleanup_status: :pending`, calls `WorkspaceCleanup.cleanup/2` with `failed?: true`, and returns a `Result` counting deleted, preserved, and failed workspaces. It is driven by the periodic `ReapSandboxes` Oban job.

## Safety policy reference

The sandbox layer implements the controls defined in `SAFETY_POLICY.md`. The policy treats safety as a product contract: Docker limits blast radius, while policy limits intent. Both layers are required for every autonomous or semi-autonomous agent run. The threat model table in `SAFETY_POLICY.md` maps each threat class to primary defenses and a required Phase 1 check, including host escape, internal state corruption, secret exposure, and supply-chain drift.

## Key source files

| File | Purpose |
| --- | --- |
| `lib/conveyor/sandbox/docker_runner.ex` | Docker-backed sandbox runner (materialize, exec, destroy) |
| `lib/conveyor/sandbox/runner.ex` | Runner behaviour and minimal host command runner |
| `lib/conveyor/sandbox/docker_profile.ex` | Hardened Docker create arguments |
| `lib/conveyor/sandbox/network_policy.ex` | Network mode and egress allowlist validation |
| `lib/conveyor/sandbox/policy_executor.ex` | Policy-checked command execution inside a sandbox |
| `lib/conveyor/sandbox/materialized.ex` | Runtime handle for a materialized workspace |
| `lib/conveyor/factory/workspace_materialization.ex` | Tracked checkout/workspace lifecycle resource |
| `lib/conveyor/sandbox/workspace_cleanup.ex` | Cleanup policy enforcement and tree digest |
| `lib/conveyor/sandbox/reaper.ex` | Orphan workspace reaping service |
| `SAFETY_POLICY.md` | Threat model and default Phase 1 controls |

## Related pages

- [Sandbox Docker container lifecycle](../systems/sandbox.md) — sandbox system internals
- [Policy engine and command normalization](../systems/policy-engine.md) — command normalization and denial
- [Credential broker](credential-broker.md) — scoped credential leases for sandboxed agents
- [Architecture](../overview/architecture.md) — OTP supervision including the reaper
- [Station pipeline](station-pipeline.md) — where sandboxes are materialized and destroyed
