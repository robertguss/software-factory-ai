# Development workflow

The cycle is: create a bead, branch, write tests first, implement, verify
locally, push, open a PR, merge. For test specifics see [testing](testing.md).
For lint and build tooling see [tooling](tooling.md).

## Track work in br

All implementation work is tracked in `br` (beads), never `bd`. Resolve the
actor once and reuse it:

```bash
ACTOR="${BR_ACTOR:-assistant}"
```

Find ready work:

```bash
br ready --json
```

Create a bead if none exists for your work:

```bash
br create --actor "$ACTOR"
```

After any issue change, sync the `.beads/` state:

```bash
br sync --flush-only
```

`br` never commits git changes. You stage and commit yourself.

If your work touches issue dependencies, confirm there are no cycles before
pushing:

```bash
br dep cycles --json
```

The output must be an empty list.

## Branch

Create a branch from `main`:

```bash
git checkout -b my-feature
```

Keep one branch per bead when possible. If a change spans multiple beads, split
into multiple branches and PRs.

## Test first (TDD)

Conveyor uses strict TDD. Write a failing test that describes the behavior you
want, run it to confirm it fails for the right reason, then implement until it
passes. Keep the red-green-refactor loop narrow.

For database-backed tests, the test alias creates and migrates the test database
first, so you do not need to run `ecto.create` or `ecto.migrate` separately:

```bash
MIX_ENV=test mix test path/to/your_test.exs
```

See [testing](testing.md) for fixture patterns, property-based testing, and
hermetic adapters.

## Implement

Write the production code in `lib/conveyor/` for core logic or
`lib/conveyor_web/` for web projections. Business rules live in `Conveyor.*`
modules. Web code in `lib/conveyor_web/` is projection only: it displays
authority but does not create it.

Database-backed state goes through Ash resources in `lib/conveyor/factory/`. Use
state machine transitions explicitly. Never bypass a transition with a raw
`Ash.update!` that skips `transition_state`.

For the full set of coding conventions, see
[patterns and conventions](patterns-and-conventions.md).

## Verify locally

Run the full chain before pushing. CI runs these same checks, so catching
failures locally saves a round trip:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix test
mix credo --strict
mix dialyzer
```

If you want to format automatically instead of just checking:

```bash
mix format
```

## Push and open a PR

Push your branch and open a pull request against `main`:

```bash
git push -u origin my-feature
```

Keep the PR description focused on what changed and why. Link the bead it
implements.

## Merge

After review approval and green CI, merge the PR. Squash or rebase per the
repo's existing history style.

## Destructive operations

Do not use destructive git or shell operations unless an explicit
higher-authority instruction allows it. This includes `git reset --hard`,
`git clean -fd` / `-fdx`, `rm -rf`, force-push, pipe-to-shell installers, and
deploy or release commands. These can destroy uncommitted work or untracked
files that belong to other contributors.
