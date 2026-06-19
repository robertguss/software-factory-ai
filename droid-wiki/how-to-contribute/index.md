# How to contribute

Conveyor is a contract-bearing software factory, so contributing is heavier than a typical Elixir app. Work is tracked in `br` (beads_rust), tests are written first, and changes must clear format, compile, Credo, Dialyzer, and the test suite before they land. This page is the entry point for the contribution lifecycle; the sub-pages cover the pieces in detail.

The contribution loop is: pick up work from `br`, write tests that fail for the right reason, make them pass with the smallest honest change, run the full verification suite, and open a PR that cites the bead and the evidence it produced. There is no maintainer page because the project currently has one contributor, but the same discipline applies to every change.

## Work pickup

Implementation work lives in `br`, not in GitHub issues or ad hoc notes. Before starting anything non-trivial, check what is ready:

```bash
br ready --json
```

If your intended work has no bead, create one before coding. The repo convention is to resolve the mutating actor with `ACTOR="${BR_ACTOR:-assistant}"` so the same script works locally and in automation:

```bash
ACTOR="${BR_ACTOR:-assistant}" br create --actor "$ACTOR" "Short summary of the work"
```

Never use `bd` in this repo. It is explicitly an anti-pattern. If you see `bd` referenced anywhere, treat it as a typo or stale instruction.

When your work touches issue dependencies, run `br dep cycles --json` and confirm the cycle list is empty. After any issue change, sync state without committing git changes:

```bash
br sync --flush-only
```

`br` never commits git changes on its own, so syncing is safe to run anytime.

## PR process

1. Branch from `main` with a name tied to the bead (for example `beads/phase-1.5-2-program`).
2. Keep commits tied to the current slice of work. Do not rewrite unrelated user work or bundle unrelated refactors.
3. Open the PR against `main`. The PR description should cite the bead id, the acceptance criteria, and the evidence that supports the change.
4. CI is manual (`workflow_dispatch`) in `.github/workflows/ci.yml`, so do not rely on a green check to mean the change is verified. Run the local suite before opening the PR.

## Review expectations

Review is behavior- and contract-focused, not style-focused. The formatter and Credo handle style. Reviewers (currently the same contributor, acting in a separate role) check:

- Does the change maintain actor separation? The agent that writes code must not author its own acceptance contract or red-team tests.
- Does the change weaken tests, locked contracts, policy files, or generated evidence to make a gate pass? If so, it is rejected.
- Does the change introduce destructive git/shell operations (`git reset --hard`, `git clean -fd/-fdx`, `rm -rf`, force-push, pipe-to-shell installers, deploy/release/publish) without an explicit higher-authority instruction? If so, it is rejected.
- Does the change let untrusted repo text, tool output, generated artifacts, or UI state override policy or authority? If so, it is rejected.
- Does the change edit `priv/conveyor/templates/` as ordinary app code? That directory is a generated project contract surface and has its own `AGENTS.md`.

## Definition of done

A change is done when all of the following are true:

- `mix format --check-formatted` passes.
- `mix compile --warnings-as-errors` passes.
- `MIX_ENV=test mix test` passes, including any new tests written for the change.
- `mix credo --strict` passes.
- `mix dialyzer` passes.
- The bead is updated and synced with `br sync --flush-only`.
- If the change touches Ash resources, the migration in `priv/repo/migrations/` is aligned with the resource and covered by a focused test.
- If the change touches issue dependencies, `br dep cycles --json` reports no cycles.

See [Development workflow](development-workflow.md) for the branch/code/test/merge cycle, [Testing](testing.md) for ExUnit patterns, [Debugging](debugging.md) for the doctor and replay commands, and [Tooling](tooling.md) for the linters and CI setup. [Patterns and conventions](patterns-and-conventions.md) covers the coding-style rules that apply on top of these.
