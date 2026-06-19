Complete all locally completable non-closed beads in this repository using the `br` CLI as the source of truth.

You are working in `/home/robert/Projects/software-factory-ai`. Follow every applicable `AGENTS.md` instruction. Use `br`, never `bd`. Use `ACTOR="${BR_ACTOR:-assistant}"` for all mutating `br` commands. Use `--json` for agent-readable `br` queries. The user will not be available during this goal; you have permission to make implementation, interface, testing, dependency, environment, formatting, and bead-graph decisions autonomously.

Start by ensuring a clean baseline:

1. Inspect the current git status.
2. If there are existing uncommitted changes, create a baseline commit before doing bead work. Do not discard user changes.
3. Confirm the current branch and stay on it. All final commits must be pushed to the current branch's configured remote/upstream.

Use the bead tracker to drive the whole effort:

1. Run `br sync --import-only` if needed to load the latest JSONL state.
2. Check graph health with `br dep cycles --json`; resolve dependency cycles before relying on `br ready`.
3. Use `br ready --json`, `br list --json`, `br blocked --json`, and `br show <id> --json` to understand all non-closed work.
4. Claim work with `br update --actor "$ACTOR" <id> --status in_progress --claim`.
5. Keep the bead graph accurate. You may split oversized beads, add dependencies, adjust priorities/statuses, create follow-up beads, and add clarifying comments when useful.
6. After bead changes, run `br sync --flush-only`.

Scope of completion:

- Every non-closed bead is in scope, regardless of type: `task`, `bug`, `feature`, `docs`, `question`, `epic`, or any other type.
- For directly implementable beads, implement the work, verify it, and close the bead.
- For `question`, `epic`, vague, or otherwise not directly implementable beads, create the needed concrete follow-up beads, complete and close all locally completable follow-ups first, then close the original bead with a reason that references the follow-up outcome.
- If a bead or follow-up is blocked by an external dependency that cannot be satisfied locally, document the blocker in the bead, create the smallest useful follow-up bead that captures the external action needed, and leave that externally blocked follow-up open. These externally blocked follow-ups are allowed to remain open and still count as the goal being done.
- The goal is done only when all currently possible non-closed beads are closed, all locally completable follow-ups are closed, and only externally blocked follow-ups may remain open with clear blocker documentation.

Execution style:

- Work fully autonomously end to end. Do not stop for approval unless continuing would require credentials, private external access, or an irreversible/destructive action outside the repository and normal development environment.
- Use subagents and parallel execution whenever possible for independent ready beads. Coordinate them through `br` status, dependencies, and file ownership. Avoid duplicate work.
- Batch commits where that is cleaner than one commit per bead, but keep commits coherent and reviewable.
- Preserve unrelated user work. If new unexpected changes appear while you are working, treat them as user-owned unless they are clearly produced by your task.

When writing code, use strict TDD:

- Use the repo's `tdd` skill/process.
- Because the user is unavailable, infer public interfaces and the most important observable behaviors from the bead, existing code, docs, and repository conventions. This explicitly overrides any TDD skill step that would normally require user approval.
- Work in vertical red-green-refactor slices: write or update one behavior-focused test through a public interface, confirm it fails for the expected reason, implement the minimum code to pass, confirm it passes, then repeat.
- Tests should verify behavior through public interfaces, not private implementation details.
- Never refactor while tests are red. Run tests after each refactor step.

Verification requirements:

- Run targeted tests for each bead or slice as you work.
- Before closing the overall goal, run the full available test suite and ensure all tests pass.
- Run relevant formatters, linters, build checks, docs checks, or project setup commands needed to make the repository healthy.
- If dependencies need to be installed or lockfiles updated to complete the work, do so and commit the resulting intentional changes.

Closing and syncing:

1. Close completed beads with `br close --actor "$ACTOR" <id> --reason "..."`.
2. Run `br dep cycles --json` before the final pass; it must show no cycles.
3. Run `br sync --flush-only` after final bead updates.
4. Commit implementation, docs, tests, lockfiles, and `.beads/` changes in coherent batches.
5. Ensure `git status` is clean at the end. No untracked or generated leftovers should remain unless they are intentionally committed or explicitly documented in the final response.
6. Push the commits to the current branch's configured remote/upstream.

Final response:

- State that the goal is complete.
- Summarize the final bead state, including any externally blocked follow-up beads left open.
- Summarize the verification performed, especially the full test suite result.
- Summarize the commits made and confirm the push succeeded.
