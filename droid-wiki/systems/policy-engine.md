# Policy engine

The policy engine in `lib/conveyor/policy/` is Conveyor's command decision
service. Every tool call an agent makes passes through normalization,
allowlist/denylist evaluation, environment and network checks, and budget
enforcement before it is allowed to execute. The engine is a supervised
conductor child that runs inside the determinism boundary: agents propose
commands, the conductor decides whether they may run.

## Engine

`lib/conveyor/policy/engine.ex` is the execution policy decision service. It is
a `Conveyor.Conductor.Child` that exposes `evaluate!/2`, which takes a `Policy`
record and a `NormalizedCommand` and returns a `Decision` struct.

The `Decision` struct carries:

- **`status`** — `:allowed` or `:blocked`
- **`reason`** — `:allowed`, `:not_allowlisted`, `:denylisted`,
  `:env_not_allowed`, or `:network_not_allowed`
- **`message`** — human-readable explanation
- **`policy_profile`** — which profile the decision was made under
- **`command`** — the evaluated command text

Evaluation order is: environment keys must be allowed, network mode must be
within policy, command must be allowlisted, and command must not be denylisted.
Allowlist and denylist matching is prefix-based: a pattern matches if the
command text equals it or starts with it followed by a space.

## NormalizedCommand

`lib/conveyor/policy/normalized_command.ex` defines the canonical command shape
used before policy evaluation and sandbox execution. A `NormalizedCommand`
carries the executable, argv, cwd, env keys, stdin ref, network mode (`:none`,
`:loopback`, `:egress`), write roots, read roots, and timeout.

Normalization is strict: raw shell commands are rejected (no `bash -c` strings),
argv must contain only strings, and workspace paths are resolved,
symlink-resolved, and checked against the workspace root to prevent escapes.
Read roots may be absolute (resolved and symlink-resolved) or relative (resolved
under the workspace root). Write roots must stay under the workspace root.

## Profiles

`lib/conveyor/policy/profiles.ex` loads policy profile TOML files into `Policy`
records. Five profiles are required and the loader rejects an incomplete set:

- **`explore`** — read-only exploration; lowest autonomy ceiling.
- **`implement`** — implementation work; may write to the workspace.
- **`verify`** — verification and gate reruns; may run tests in clean
  containers.
- **`release`** — release-facing operations; future-gated by default.
- **`maintenance`** — cleanup and reconciliation; future-gated by default.

Each profile defines an allowlist, denylist, env policy, network policy, budget
policy, and autonomy ceiling (L0 through L4). The loader validates required
fields, profile names, and autonomy ceiling format, then upserts each policy as
an Ash `Policy` record.

## RunBudgetGuard

`lib/conveyor/policy/run_budget_guard.ex` applies per-run budget caps and stops
work on budget exhaustion. It tracks ten caps: max tool calls, max command
count, max output bytes, max repeated commands, max same-file rewrites, max
no-diff progress time, max idle time, max wall clock, max tokens, and max cost
in cents.

When a budget cap is exceeded, the guard performs a transactional update: marks
the budget as exhausted, fails the run attempt with outcome `needs_rework` and
category `budget_exhausted`, transitions the slice to `needs_rework`, and writes
an idempotent `budget.exhausted` ledger event. The `Result` struct carries the
updated budget, exceeded cap, finding, and affected run attempt, slice, and
ledger event.

Contract faults and contract changes do not consume the retry budget: the
`retry_budget_effect` is `not_consumed_contract_fault` or
`not_consumed_contract_change` respectively.

## ViolationHandler

`lib/conveyor/policy/violation_handler.ex` records policy violations and stops
affected work. When the engine blocks a command, the handler creates an
`Incident` with category `policy_violation`, stops the run attempt with outcome
`policy_blocked` and category `policy_violation`, transitions the slice (to
`failed` on critical severity, `policy_blocked` otherwise), and writes an
idempotent `policy.blocked` ledger event with the incident id, tool invocation
id, policy profile, decision reason, and command.

## Key source files

| File                                        | Purpose                                                                             |
| ------------------------------------------- | ----------------------------------------------------------------------------------- |
| `lib/conveyor/policy/engine.ex`             | Execution policy decision service with `evaluate!/2` and `Decision` struct.         |
| `lib/conveyor/policy/normalized_command.ex` | Canonical command shape with workspace path resolution and escape prevention.       |
| `lib/conveyor/policy/profiles.ex`           | Loads policy profile TOML files into `Policy` records; validates required profiles. |
| `lib/conveyor/policy/run_budget_guard.ex`   | Per-run budget caps with transactional stop and ledger event on exhaustion.         |
| `lib/conveyor/policy/violation_handler.ex`  | Records policy violations, stops work, and writes ledger events.                    |

## Related pages

- [Gate](gate.md) — gate stage composition, including `policy_compliance` and
  `secret_safety` stages
- [Agent runner](agent-runner.md) — how agents are launched and monitored
- [Sandbox](sandbox.md) — how policy-checked commands execute in containers
- [Architecture](../overview/architecture.md) — OTP supervision and conductor
  services
