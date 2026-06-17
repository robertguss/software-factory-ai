# Conveyor Safety Policy

Conveyor treats safety as a product contract, not a deployment detail. Docker is
necessary but not sufficient. Policy rule: Docker necessary but not sufficient.
Docker limits blast radius, while policy limits intent. Both layers are required
for every autonomous or semi-autonomous agent run.

This policy defines the Phase 0 threat model and the default Phase 1 controls
for policy profiles, command denial, sandbox execution, image identity, egress,
credentials, and conductor isolation.

## Threat Model

Each threat class must have at least one Phase 1 test, canary, or doctor check.
The test surface may be implemented as a unit/integration test, a gate canary, a
doctor audit, or a security eval fixture, but every row must have concrete
coverage before the system can claim the corresponding control is enforced.

| Threat | Example | Primary defenses | Required Phase 1 check |
| --- | --- | --- | --- |
| Malicious repository content | Comments or docs tell the agent to ignore Conveyor rules. | Prompt trust labels, instruction hierarchy, prompt-injection evals. | Prompt-injection fixture verifies untrusted repo text cannot override system, developer, project, or run policy. |
| Malicious tool output | Test output asks the agent to exfiltrate secrets. | Tool-output trust labels, RunCheck, policy. | Tool-output fixture verifies generated logs and test output are treated as untrusted evidence, not instructions. |
| Agent policy evasion | Agent tries shell tricks, wrapper scripts, symlinks, or indirect command execution. | Command grammar, sandbox, egress policy, denylist. | Command-policy test rejects normalized shell tricks, symlink writes, and disallowed executable families. |
| Test weakening | Agent edits tests or fixtures to make failures disappear. | Locked read-only TestPack, contract lock, RunCheck. | Gate check verifies protected tests and fixtures remain read-only and match approved content digests. |
| Secret exposure | Logs, prompts, diffs, or artifacts contain credentials. | Secret scanner, redaction/quarantine, environment allowlist. | Redaction test plants synthetic secrets and verifies prompts, logs, artifacts, and diffs are quarantined or redacted. |
| Supply-chain drift | Image, dependency, or tool version changes between runs. | Container image digest, dependency lock, SBOM, provenance. | Freshness check compares image digest, lockfiles, SBOM, and tool versions against the RunSpec. |
| Artifact tampering | Manifest points to changed or missing logs. | Content-addressed artifacts, digest verification, RunCheck. | Artifact manifest test mutates or removes evidence and verifies digest validation fails closed. |
| Reviewer rubber stamp | Reviewer accepts an inadequate dossier. | Actor separation, rubric schema, reviewer evals, later bug correlation. | ReviewerHealth eval verifies the reviewer is distinct from the implementer and must return structured rubric evidence. |
| Gate false negative | Known-bad mutant passes. | Gate canaries, stop-the-line policy. | Gate canary runs known-bad mutants through the same gate path and fails the build if a mutant passes. |
| Internal state corruption | Agent network probes the conductor Postgres database or ledger. | Conductor DB and ledger are unreachable from the sandbox network; agent egress is segregated from the internal application database. | Network-isolation doctor verifies sandbox DNS, routes, and egress rules cannot reach Postgres, the ledger, or internal Conveyor services. |
| Host escape or overreach | Container gets host credentials, privileged runtime access, or the Docker socket. | Rootless/no-privilege sandbox, no host home mount, no Docker socket. | Sandbox doctor verifies non-root execution, no privileged container, no host home mount, no Docker socket, and no-new-privileges. |

## Enforcement Layers

Policy is enforced at two layers:

1. Sandbox constraints that remain true even if the agent ignores instructions.
2. Command and tool policy that approves or rejects invocations before
   execution when the adapter supports interception.

Adapters that cannot provide pre-exec command interception may still be used,
but their `AgentProfile.capabilities` must mark command policy as
`observe_only`, and their autonomy ceiling must remain below profiles that can
enforce command policy before execution.

## Policy Profiles

| Profile | Allowed intent | Default permissions |
| --- | --- | --- |
| `explore` | Understand the repository and gather context. | Read, search, and context tools only; no source edits. |
| `implement` | Produce a bounded patch in the workspace. | Source edits allowed inside declared write roots; dangerous git, filesystem, network, and deploy commands are blocked. |
| `verify` | Build, test, lint, and inspect evidence. | Build/test/lint/CodeScent commands allowed; no source edits except tool-owned cache writes. |
| `release` | Future release automation. | Deployment commands require explicit repo policy and human approval until release policy is implemented. |
| `maintenance` | Future dangerous maintenance workflows. | Dangerous commands require human approval, incident logging, and explicit policy grants. |

Each profile records:

- profile name and autonomy ceiling;
- command allowlist and denylist;
- read roots, write roots, and cache roots;
- environment variable policy;
- network policy;
- CPU, memory, process, output, and wall-clock budgets.

## Minimum Denylist

The following actions are denied by default unless a narrower repository policy
explicitly grants them for a higher-autonomy profile with human approval:

- destructive filesystem operations outside declared write roots, including
  `rm -rf`, recursive `chmod` or `chown`, mass delete, and symlink-mediated
  deletion;
- `git reset --hard`;
- `git clean -fd` and `git clean -fdx`;
- `git push --force` and `git push --force-with-lease`;
- `chmod` or `chown` outside the workspace;
- pipe-to-shell installers, remote script execution, and package lifecycle
  scripts such as `curl | sh` or `wget | sh`, unless explicitly approved by
  toolchain policy;
- `sudo` commands inside workers;
- access to `~/.ssh`, cloud credentials, production environment files, or
  production database URLs;
- package installs outside the pinned container image or project virtual
  environment;
- network calls except allowlisted package registries, provider APIs, package
  mirrors, or code-quality endpoints;
- deploy, release, publish, package-upload, infrastructure-apply, or
  production-data commands at autonomy levels L0 through L2.

A policy violation creates an `Incident`, stops the run, records evidence, and
moves the Slice to `policy_blocked` or `failed` depending on severity. Phase 1
prefers false positives over silent policy bypass.

## Command Grammar And Path Normalization

Conveyor prefers structured command execution over raw shell execution.
`command_specs[]` and adapter tool calls are normalized before policy checks:

```elixir
%{
  executable: "pytest",
  argv: ["-q"],
  cwd: ".",
  env_keys: ["PYTHONPATH"],
  stdin_ref: nil,
  network: :none,
  write_roots: ["."],
  read_roots: [".", "/conveyor/locked_tests"],
  timeout_ms: 120_000
}
```

Policy evaluation order:

1. Reject raw shell strings unless the profile explicitly allows shell.
2. Resolve the executable path inside the container.
3. Normalize `cwd`, symlinks, read roots, and write roots.
4. Reject writes outside the materialized workspace or declared cache roots.
5. Allow only configured executable families for the station profile.
6. Apply denylist checks as defense-in-depth.
7. Record the policy decision before execution.

Default Phase 1 profiles allow only the command families needed by the sample
project: `python`, `pytest`, package-manager commands already baked into the
image or project virtual environment, `git diff`, `git status`, `rg`, and
configured code-quality tools. General shell, deployment CLIs, host filesystem
access, and credential discovery are blocked unless a specific profile grants a
narrow exception.

Budget exhaustion is a policy-controlled stop, not an ordinary agent failure.
The run records consumed budget counters and moves the Slice to `needs_rework`,
`parked`, or `failed` according to policy.

Non-progress exhaustion is also budget exhaustion. Phase 1 detects repeated
identical command failures, no patch progress for `max_no_diff_progress_ms`,
excessive rewrites of the same file, output flooding, and heartbeats without
meaningful station progress.

## Sandbox Run Spec

Phase 1 Docker containers default to:

- non-root user;
- rootless Docker where available;
- no privileged containers;
- no Docker socket mount;
- no host home-directory mount;
- read-only mounts for contracts, policies, and `.conveyor`;
- read-write mount only for the materialized workspace;
- `no-new-privileges`;
- seccomp or AppArmor profile where available;
- CPU, memory, process, output-size, and wall-clock limits;
- `network=none` by default;
- allowlisted egress proxy only for explicitly approved package or provider
  calls.

The doctor command reports host capabilities and fails hard when required
sandbox constraints are unavailable for the selected policy profile.

## Image, Egress, And Credential Policy

Each executable station uses a pinned toolchain image:

```yaml
image:
  ref: ghcr.io/conveyor/sample-python-runner:2026-06-01
  digest: sha256:...
  sbom_ref: artifacts/sbom.cyclonedx.json
```

The gate records the immutable image digest in `RunSpec`, `ToolInvocation`, and
provenance. Mutable tags are human-friendly labels only; the digest is the
identity.

Gate and canary stations may use only image-baked dependencies or read-only
content-addressed caches unless a project policy explicitly approves network
bootstrap. Any dependency lockfile change is a diff-scope event and updates the
RunSpec freshness key.

| Station | Default network | Allowed egress |
| --- | --- | --- |
| `scout` | none | Optional code-quality adapter endpoint. |
| `implement` | none | Provider API only when required by the adapter. |
| `verify` / `gate` | none | None unless dependency bootstrap is explicitly approved. |
| `canary` | none | None. |

No station's allowed egress may include the conductor's own network. The
AshPostgres database, ledger, and any internal Conveyor service must be
unreachable from the sandbox network so that a compromised or injected agent
cannot probe or mutate conductor state. Approved egress is brokered to external
hosts only.

Provider credentials are issued through a `CredentialBroker`. Raw provider
secrets are not injected into worker containers unless no safer adapter mode
exists. Provider credentials are represented as short-lived `CredentialLease`
records that are:

- scoped to one run or station;
- exposed only as named environment keys allowed by policy;
- never written into prompts, artifacts, or child process logs;
- revoked or invalidated on cancellation, policy violation, or run completion.

## Sandbox And Tool-Execution Boundary

Pi and other agent adapters are not the security boundary. The safer boundary is
layered:

- Conveyor owns tool execution.
- The sandbox owns filesystem, process, and network limits.
- The `CredentialBroker` owns provider access.
- The agent adapter is a reasoning loop and event stream.

The conductor-network-unreachable rule is mandatory: no sandbox profile may
route to the conductor's Postgres database, ledger, internal services, or other
control-plane endpoints. This rule is enforced by sandbox network configuration,
doctor checks, and gate evidence.
