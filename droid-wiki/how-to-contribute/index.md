# How to contribute

This page covers how to pick up work, open a pull request, and meet the review
bar in the Conveyor codebase. For the branch-code-test-PR-merge cycle, see
[development workflow](development-workflow.md). For test frameworks and
patterns, see [testing](testing.md). For linters, formatters, and CI, see
[tooling](tooling.md). For coding style and architectural conventions, see
[patterns and conventions](patterns-and-conventions.md).

## Picking up work

Implementation work is tracked in `br` (beads), not `bd`. To find tasks whose
dependencies are satisfied and are ready to start:

```bash
br ready --json
```

The output is JSON describing each ready issue, its stable key, and its
dependencies. Pick one, assign yourself by setting `BR_ACTOR` to your handle,
and create a branch.

If no bead exists for the work you want to do, create one:

```bash
ACTOR="${BR_ACTOR:-assistant}"
br create --actor "$ACTOR"
```

After any change to issue state (create, update, close), run:

```bash
br sync --flush-only
```

`br` never commits git changes, so you handle staging and commits yourself.

## PR process

The repo uses GitHub pull requests. Push your branch to `origin` and open a PR
against `main`. Keep PRs focused on a single bead or a single coherent change.
If a change spans multiple beads, open one PR per bead when possible.

### Before you push

Run the full local verification chain so CI does not fail on something you could
have caught locally:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
MIX_ENV=test mix test
mix credo --strict
mix dialyzer
```

If you touched issue dependencies, also confirm there are no cycles:

```bash
br dep cycles --json
```

The output must be an empty list.

## Review expectations

Conveyor follows strict TDD. A PR that adds behavior should include a failing
test that the change makes pass. A PR that fixes a bug should include a
regression test that reproduces the bug first. Do not weaken, delete, or rewrite
locked tests to get green output.

Credo runs in strict mode and Dialyzer runs with `.dialyzer_ignore.exs` for
known false positives. Both must pass with zero warnings. The formatter
(`mix format`) is enforced; `mix format --check-formatted` will fail CI on
unformatted code.

The codebase enforces a separation of concerns that reviewers will check:

- Web code in `lib/conveyor_web/` is projection only. Business rules belong in
  `Conveyor.*` modules.
- The module that writes code must not author its own acceptance contract.
  Contract author and implementer are different actors.
- Policy decisions, effect attempts, evidence, and authority events are distinct
  resources. Do not collapse them into convenience structs.
- The ledger (`lib/conveyor/ledger.ex`) is append-only. Never update or delete
  ledger entries.

For the full set of architectural rules, see
[patterns and conventions](patterns-and-conventions.md).

## Definition of done

A change is done when all of the following hold:

- **Mapped acceptance evidence** - The change has tests tied to the behavior or
  contract it implements, not just implementation details. Acceptance-gate tests
  reference evidence and contract semantics.
- **Successful verification** - The full local chain passes: format check,
  compile with warnings-as-errors, test suite, Credo strict, Dialyzer.
- **Independent review when required** - Changes that affect policy, gate logic,
  or safety constraints need review from someone who did not author the change.
  The contract author and implementer are different actors by design.
- **Passing deterministic gate** - The verification gate
  (`lib/conveyor/gate.ex`) decides accept, reject, or abstain based on recorded
  evidence. A passing run means the gate found sufficient evidence for the
  contract. If the gate abstains, the slice routes to human review at `/parked`.

## CI

CI runs on GitHub Actions with a manual `workflow_dispatch` trigger. It uses
PostgreSQL 16 and Python 3.13 (for the eval toolchain runner). The CI pipeline
runs format check, compile, tests, Rung-0 evals, cassette replay, lift-duel
report, eval scorecard gate, Credo, and Dialyzer. See [tooling](tooling.md) for
details on each step.
