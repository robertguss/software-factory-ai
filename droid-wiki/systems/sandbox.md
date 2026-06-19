# Sandbox

The sandbox system in `lib/conveyor/sandbox/` is how Conveyor creates, isolates, and cleans up the Docker containers that agents and gate verification run inside. Every command an agent or gate stage executes goes through a materialized sandbox workspace with hardened Docker defaults, network isolation, and policy-checked execution. The sandbox is the physical enforcement layer behind the policy engine's decisions.

## DockerRunner

`lib/conveyor/sandbox/docker_runner.ex` is the Docker-backed sandbox runner. It implements the `Conveyor.Sandbox.Runner` behaviour with three operations:

- **`materialize/2`** — resolves the project source context, prepares workspace paths, archives a clean checkout at the run spec's base commit via `git archive`, creates a Docker container with the hardened profile, mounts the workspace, and records a `WorkspaceMaterialization` record. Returns a `Materialized` handle.
- **`exec/3`** — runs a `NormalizedCommand` inside the container via `docker exec`, setting the working directory and environment. Returns a `Runner.Result` with exit code, stdout, stderr, and duration.
- **`destroy/2`** — delegates to `WorkspaceCleanup` to remove the container and clean up the workspace according to its cleanup policy.

## DockerProfile

`lib/conveyor/sandbox/docker_profile.ex` defines hardened Docker defaults for sandbox containers. The `create_args/1` function produces the `docker create` argument list:

- Non-root user (default `65532:65532`)
- Network isolation via `NetworkPolicy.docker_args/1`
- `no-new-privileges:true`
- All capabilities dropped (`--cap-drop ALL`)
- Read-only root filesystem
- tmpfs at `/tmp` with noexec, nosuid, 64m limit
- PID limit (default 256)
- CPU limit (default 1.0)
- Memory limit (default 512m)

The `required_security_options/0` function returns `["seccomp"]`, indicating the minimum security options a container must have.

## NetworkPolicy

`lib/conveyor/sandbox/network_policy.ex` provides network policy helpers for sandbox containers. It maintains a set of internal hosts (localhost, conductor, db, postgres, host.docker.internal, private IP ranges) that must never appear in an egress allowlist. Station defaults are all `:none` (no network) for scout, implement, verify, gate, and canary stations. The `docker_args/1` function translates a network mode to Docker flags: `:none` produces `--network none`, and `:egress` raises because it requires an explicit external proxy network. The `validate_egress_allowlist!/1` function rejects any allowlist that includes conductor or internal hosts.

## PolicyExecutor

`lib/conveyor/sandbox/policy_executor.ex` runs policy-checked commands inside a materialized sandbox. It takes a `Materialized` handle, a `NormalizedCommand`, and a `Policy`, then delegates to `Conveyor.ToolExecutor` with the Docker runner as the execution backend. The policy boundary lives in `ToolExecutor`; this module only runs commands that have already been normalized and allowed.

## Materialized

`lib/conveyor/sandbox/materialized.ex` is the runtime handle for a materialized sandbox workspace. It carries the `WorkspaceMaterialization` record, the project path, the root path, the container id, and the image ref. This handle is what `DockerRunner.exec/3` and `WorkspaceCleanup.cleanup/2` operate on.

## WorkspaceCleanup

`lib/conveyor/sandbox/workspace_cleanup.ex` enforces cleanup policy for materialized sandbox workspaces. Cleanup policies are:

- **`preserve_always`** — workspace is always preserved.
- **`preserve_on_failure`** — workspace is preserved only when the `failed?` opt is set.
- **Default** — workspace is deleted.

Cleanup removes the Docker container, deletes the workspace path (unless preserving), and updates the `WorkspaceMaterialization` record with cleanup status and timestamp. The `tree_sha256/1` function computes a content-addressed digest of the entire workspace tree by hashing each file's relative path and SHA-256, used by the gate to record the head tree digest.

## Runner

`lib/conveyor/sandbox/runner.ex` defines the sandbox runner behaviour and a minimal host command runner used behind `ToolExecutor`. The behaviour requires `materialize/2`, `exec/3`, and `destroy/2`. The `exec/1` function runs a `NormalizedCommand` directly on the host (used for non-sandboxed execution paths) with the command's cwd, environment keys, and stderr-to-stdout. The `Result` struct carries exit code, stdout, stderr, and duration.

## Reaper

`lib/conveyor/sandbox/reaper.ex` is the sandbox cleanup and orphan reaping service. It is a supervised conductor child that scans for `WorkspaceMaterialization` records with `pending` cleanup status and runs `WorkspaceCleanup` on each. The `Result` struct counts deleted, preserved, and failed workspaces. The reaper is invoked periodically by the `ReapSandboxes` Oban job.

## Key source files

| File | Purpose |
| ---- | ---- |
| `lib/conveyor/sandbox/docker_runner.ex` | Docker-backed sandbox runner: materialize, exec, destroy. |
| `lib/conveyor/sandbox/docker_profile.ex` | Hardened Docker defaults: non-root, no-new-privileges, cap-drop, read-only, limits. |
| `lib/conveyor/sandbox/network_policy.ex` | Network isolation helpers with internal host detection. |
| `lib/conveyor/sandbox/policy_executor.ex` | Runs policy-checked commands inside a materialized sandbox. |
| `lib/conveyor/sandbox/materialized.ex` | Runtime handle for a materialized sandbox workspace. |
| `lib/conveyor/sandbox/workspace_cleanup.ex` | Cleanup policy enforcement and workspace tree hashing. |
| `lib/conveyor/sandbox/runner.ex` | Sandbox runner behaviour and minimal host command runner. |
| `lib/conveyor/sandbox/reaper.ex` | Periodic sandbox cleanup and orphan reaping service. |

## Related pages

- [Agent runner](agent-runner.md) — how agents are launched and monitored in containers
- [Policy engine](policy-engine.md) — command normalization and allowlist enforcement
- [Evidence recording](evidence-recording.md) — clean workspace materialization for gate reruns
- [Architecture](../overview/architecture.md) — OTP supervision and Oban workers
