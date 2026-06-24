# Development workflow

The Conveyor development loop is a strict branch, test, code, verify, PR, merge
cycle. Work is tracked in `br`, tests are written before implementation, and
every change clears the full verification suite before it lands. This page walks
through each stage and the exact commands to use.

The repo is solo today, but the workflow is designed to stay honest as more
actors (human or agent) join. The discipline that keeps it honest is actor
separation, locked contracts, and a deterministic gate, and the same discipline
applies to everyday contributions.

## Branch

Branch from `main` and name the branch after the bead it implements. The recent
history uses names like `beads/phase-1.5-2-program`, which keeps the git log
greppable by bead id.

```bash
git checkout -b beads/<bead-id>-<short-slug>
```

Do not bundle unrelated refactors into a bead-scoped branch. If you spot
something worth fixing while working, file a new bead or add a clarifying
comment and come back to it.

## Track work with `br`

`br` is the source of truth for implementation work. Never use `bd`. Resolve the
mutating actor once and reuse it for the session:

```bash
ACTOR="${BR_ACTOR:-assistant}"
```

Common commands:

```bash
# See what is ready to pick up
br ready --json

# Create a bead for new work
br create --actor "$ACTOR" "Short summary"

# After any issue change, sync state without committing git changes
br sync --flush-only

# When touching issue dependencies, confirm no cycles
br dep cycles --json
```

`br` never commits git changes, so `br sync --flush-only` is safe to run
anytime. If a cycle appears after a dependency edit, fix it before proceeding;
the cycle list must be empty.

## TDD: red, green, refactor

Conveyor uses strict TDD (see `.agents/skills/tdd/SKILL.md`). The loop is
narrow:

1. **Red.** Write a test that fails for the right reason. The test should
   exercise a public interface, not a private implementation detail. For
   database-backed behavior, `use Conveyor.DataCase`; for web behavior,
   `use ConveyorWeb.ConnCase`.
2. **Green.** Make the smallest honest change that turns the test green. Do not
   weaken the test to match the implementation.
3. **Refactor.** Clean up the code without changing behavior. Re-run the test
   after each refactor step.

The agent that writes code must not author its own acceptance contract or
red-team tests. Contract authoring (`Conveyor.ContractForge`), implementation
(AgentRunner), review (`Conveyor.Jobs.RunReviewer`), and gate evaluation
(`Conveyor.Gate`) are separate actors, and that separation is enforced at the
resource level.

## Code

Follow the conventions in
[Patterns and conventions](patterns-and-conventions.md):

- Run `mix format --check-formatted` before committing. The formatter is
  authoritative.
- Run `mix credo --strict` to catch code smells.
- Run `mix dialyzer` for type checking. The PLT includes `:ex_unit` and `:mix`.
- Put business rules in `Conveyor.*` modules, not controllers or LiveViews. The
  web layer is a projection only.
- Keep Ash resources and migrations aligned. A resource change usually implies a
  migration in `priv/repo/migrations/` and a focused test.
- Model state machines explicitly with `ash_state_machine`. Keep states and
  database constraints aligned.
- Reference files using full paths from repo root in backticks when documenting,
  and keep markdown wrapped according to `.prettierrc` with `proseWrap: always`.

## Commit

Keep commits tied to the current bead. The recent history uses messages like
`add eval plans`, `fix bugs`, and `chore: close completed program containers`.
There is no enforced commit-message format, but the message should explain why
the change is needed, not just what it does.

Do not rewrite unrelated user work. Do not use destructive git operations
(`git reset --hard`, `git clean -fd/-fdx`, `rm -rf`, force-push) unless an
explicit higher-authority instruction allows the action.

## Run the full verification suite

Before opening a PR, run the full suite in order. The commands are pinned in the
root `AGENTS.md`:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix test
mix credo --strict
mix dialyzer
```

`mix test` is aliased to create and migrate the test database first, so it is
safe to run as a single command. If you are iterating on one file, run it
directly to stay fast:

```bash
MIX_ENV=test mix test test/conveyor/gate_test.exs
```

Then run the wider surface before opening the PR.

## PR and merge

Open the PR against `main`. The description should cite the bead id, the
acceptance criteria, and the evidence that supports the change. CI is manual
(`workflow_dispatch`) in `.github/workflows/ci.yml`, so a green check is not
sufficient evidence that the change is verified. The local suite is the gate.

After merge, update the bead status and sync:

```bash
br sync --flush-only
```

See [Testing](testing.md) for the test framework details,
[Debugging](debugging.md) for troubleshooting, and [Tooling](tooling.md) for the
build and lint tooling.
