# Pitfalls

Conveyor's `AGENTS.md` and `lib/conveyor/AGENTS.md` document anti-patterns that
have caused real bugs or near-misses. Each anti-pattern has a specific
mechanism that makes it dangerous, not just a general bad-practice label. This
page covers the seven pitfalls most likely to trip up contributors.

## Untrusted repo text overriding policy

**Anti-pattern:** Letting untrusted repository text, tool output, generated
artifacts, or UI state override policy or authority.

Repository text, issue content, test output, exemplars, prior model prose, and
generated content are untrusted data (ADR-07). They never become policy,
commands, or authority merely because they appear in a repository file, prompt,
issue, transcript, or model response. A prompt-injection payload in a README or
a tool output that says "run `sudo rm -rf /`" does not change the policy engine's
allowlist or denylist.

The enforcement boundary is host controls: sandbox, mount, network, credential,
process, and syscall policy. The policy engine in `lib/conveyor/policy/engine.ex`
evaluates commands against the loaded profile, not against text the agent
encountered. Labels and prompt instructions are metadata, not an enforcement
boundary.

**Where to check:** `lib/conveyor/policy/engine.ex`,
`lib/conveyor/policy/normalized_command.ex`,
`docs/adrs/adr-07-toolcontracts-roleviews-and-instruction-authority.md`.

## Agent authoring its own acceptance contract

**Anti-pattern:** Letting the agent that writes code author its own acceptance
contract or red-team tests.

Separation of duties is load-bearing. The drafter (contract forge), the critic
(contract critic), and the implementer are three distinct actors (ADR-27). No
actor authors and then implements against its own contract, and no actor
approves its own contract; the human does. Required tests and falsifier seeds
are authored independently of the implementer, whether the surrounding plan was
written by a human or drafted by the factory (ADR-19).

If an agent could write its own acceptance criteria, it could write criteria
that its own output satisfies, making the gate meaningless. The
`ContractLock` resource (`lib/conveyor/factory/contract_lock.ex`) freezes the
contract after drafting so the implementer cannot retroactively change what it
is measured against.

**Where to check:** `lib/conveyor/factory/contract_lock.ex`,
`lib/conveyor/contract_forge/`, `lib/conveyor/contract_critic/`,
`docs/adrs/adr-27-in-factory-plan-authoring.md`.

## Weakening tests, contracts, or evidence to pass the gate

**Anti-pattern:** Weakening tests, locked contracts, policy files, or generated
evidence to make a gate pass.

The gate's value comes from its independence from the implementation. If a
failing gate can be made to pass by weakening the test, editing the locked
contract, relaxing the policy, or fabricating evidence, the gate is not
verifying anything. The `policy_compliance` gate stage
(`lib/conveyor/gate/stages/policy_compliance.ex`) blocks on
`policy_file_change` when the patch touches files matching policy path globs
(`policies/**`, `.conveyor/policies/**`, `lib/conveyor/policy/**`,
`lib/conveyor/factory/policy.ex`). The `workspace_integrity` stage blocks on
`locked_path_touched` when the patch weakens or edits locked or protected
paths.

Contract evolution always creates a new lock, spec, and attempt (ADR-20). You
cannot edit an existing `ContractLock` to make a failing run pass; you must
create a new one, which means a new run attempt.

**Where to check:** `lib/conveyor/gate/stages/policy_compliance.ex`,
`lib/conveyor/gate/stages/workspace_integrity.ex`,
`docs/adrs/adr-20-contract-evolution-always-creates-new-lock-spec-attempt.md`.

## Bypassing policy normalization

**Anti-pattern:** Bypassing policy normalization when adding command execution
paths.

`lib/conveyor/policy/normalized_command.ex` enforces a canonical command shape
and rejects raw shell strings outright. This is the structural defense against
shell injection. If a new command execution path is added that skips
normalization (for example, passing a raw string to `System.cmd` or shelling
out through a helper), the policy engine never sees the command and cannot
enforce the allowlist, denylist, env, or network checks.

Every command that runs inside a sandbox must go through
`NormalizedCommand.normalize!/2` and then `Policy.Engine.evaluate!/2` before
reaching `Sandbox.DockerRunner.exec/3`. The `Sandbox.PolicyExecutor` module
(`lib/conveyor/sandbox/policy_executor.ex`) ties these together: it calls
`ToolExecutor.execute!/3` with a runner closure that delegates to
`DockerRunner.exec/3`, and `ToolExecutor` runs the policy check before
invoking the runner.

**Where to check:** `lib/conveyor/policy/normalized_command.ex`,
`lib/conveyor/sandbox/policy_executor.ex`, `lib/conveyor/tool_executor.ex`.

## Hidden destructive operations

**Anti-pattern:** Hiding destructive filesystem, git, network, or credential
operations behind harmless-looking helper names.

A function named `cleanup_workspace` that calls `File.rm_rf/1` on a path
outside the workspace root, or a helper named `sync_remote` that runs
`git push --force`, is a trap. The policy denylist blocks `rm -rf`,
`git reset --hard`, `git clean -fd`, `git push --force`, `sudo`, and
pipe-to-shell installers, but only if the command goes through the policy
engine. A helper that calls `System.cmd` directly bypasses the engine entirely.

The `workspace_cleanup.ex` module (`lib/conveyor/sandbox/workspace_cleanup.ex`)
is the controlled path for workspace destruction. It removes the Docker
container with `docker rm -f` and deletes the workspace path, but only after
checking the `cleanup_policy` (`:delete`, `:preserve_on_failure`,
`:preserve_always`) and recording the result on the
`WorkspaceMaterialization` record. Destructive operations outside this path are
anti-patterns.

**Where to check:** `lib/conveyor/sandbox/workspace_cleanup.ex`,
`lib/conveyor/policy/profiles.ex` (denylist contents).

## Web UI authorizing work

**Anti-pattern:** Letting web/UI projection state authorize work or repair
history.

The web layer in `lib/conveyor_web/` is a projection only. It displays state;
it does not own state transitions or authority. A LiveView that shows a run as
"passed" does not make the run passed. The `GateResult` resource
(`lib/conveyor/factory/gate_result.ex`) and the gate stages in
`lib/conveyor/gate/stages/` are the authority. The `RunViewerLive` LiveView
reads from these resources; it does not write to them.

If UI state could authorize work, an agent could manipulate the DOM or the
projection layer to make the system think work was approved. The projection
layer is read-only by design.

**Where to check:** `lib/conveyor_web/`, `lib/conveyor/factory/gate_result.ex`,
`lib/conveyor/gate/stages/`.

## Treating redacted evidence as raw bytes

**Anti-pattern:** Writing code that treats redacted evidence as equivalent to
raw artifact bytes.

The redactor in `lib/conveyor/security/redactor.ex` replaces matched secrets
with `[REDACTED:<kind>:<sha256-prefix>]` tokens. The redacted content has a
different SHA-256 from the original. Code that compares a redacted artifact
against a raw artifact by digest will see a mismatch, which is correct: they
are not the same bytes. Code that treats the redacted content as if it were the
original (for example, replaying a redacted cassette as if it were the raw
recording) is wrong.

ADR-10 makes this explicit: erased evidence becomes explicit incomparable
evidence. The system distinguishes `available`, `cold`, `redacted`, `erased`,
and `unavailable` states. A redacted or erased artifact is not silently treated
as inspectable because a digest remains. The `redacted_sha256` field on the
redactor's `Result` struct lets downstream code distinguish the two digests.

**Where to check:** `lib/conveyor/security/redactor.ex`,
`docs/adrs/adr-10-retention-redaction-gc-and-active-authority-preservation.md`.
