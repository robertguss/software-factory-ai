# Decomposition aid: breaking a plan into gate-friendly slices

This is the practical guide for turning a prose plan into Conveyor slices that
**pass the gate on the first honest attempt**. Every rule here is grounded in a
real dogfood finding, not theory — where a rule exists to avoid a specific
false-park, the finding is cited.

## Sizing: let the gate's caps set the slice boundary

The gate's `diff_scope` stage caps a slice's diff (files changed, allowed
paths). A slice is the wrong size when its honest implementation would blow
those caps.

- **One observable behavior per slice.** If you cannot state the slice's
  acceptance in one or two criteria, it is two slices.
- **Count the files the change _has_ to touch**, including the mechanical
  consequences (a new export, a wiring line). If that exceeds the per-slice
  `max_files_changed`, split — or, for genuinely mechanical touches, rely on the
  always-allowed classes (below) rather than inflating the cap.
- **Prefer more small slices.** Each slice gates independently and parks
  independently; a stuck small slice does not block its unrelated siblings.

## `likely_files` discipline + always-allowed classes

`diff_scope` checks changed paths against the slice's declared scope. Two
failure modes to author around:

- **Barrel/export files you can't predict.** Exporting a new public symbol from
  a package barrel (`__init__.py`, `index.ts`, `lib.rs`/`mod.rs`) is the normal
  mechanical consequence of in-scope work, but you don't know _which_ barrel
  until the code exists. Enumerating them per-slice in `likely_files` is brittle
  busywork. This is the `8mnx` finding: the gate blocked a correct public-API
  edit that wasn't in `likely_files`. The **always-allowed path classes**
  (`nyrl.1`) cover these deterministically. The `DiffScope` stage ships a
  conservative default class — `package_barrels` (`**/__init__.py`,
  `**/index.ts`, `**/index.js`, `**/lib.rs`, `**/mod.rs`) — and a project
  extends it via `DiffPolicy.always_allowed_path_classes`
  (`[%{"name" => …, "globs" => […]}]`). A file matching a class is not flagged
  `out_of_scope_path` and is recorded in gate evidence as `always_allowed_path`
  (`path X allowed via class Y`) — never a silent grant. Two guardrails:
  **protected paths beat allowed** (a class can never whitelist `tests/**` or a
  locked contract surface), and class grants are **not exempt from the size
  caps** (`max_files_changed`/`max_lines_added` still apply, so a barrel can't
  smuggle logic).
- **`likely_files` is a scope declaration, not a wish list.** List the files the
  slice is expected to touch; keep it tight. Over-broad `likely_files` weakens
  the scope signal; too-narrow parks correct work.

## Acceptance-command patterns

- Each acceptance criterion maps to a **locked, deterministic** verification
  command (a test id, a runner invocation) — not "looks right."
- Commands run in the network-isolated verify sandbox. No network, no external
  services; seed fixtures instead.
- Prefer criteria the gate can check by re-executing the locked test, so an
  accept is evidence, not self-report.

## Locked-test materialization (Option C) — the operator's mental model

You do **not** ask the agent to write its own acceptance tests. The gate
protects `tests/**` as a locked contract surface, so an agent-authored test file
is rejected by `diff_scope` (`locked_test_pack_or_contract_changed` +
`protected_path_change`) — this is the `dxgw` finding, and it is the gate
working as designed (an agent must never author its own oracle).

Instead, Conveyor uses **Option C, per-slice locked-test materialization**
(shipped in PR #40): each slice's locked acceptance tests are staged and
committed into the workspace _before_ the agent runs, so `base_commit` already
holds them. The agent then implements against a base that contains its red
tests, and never touches `tests/**` itself. Operator takeaway: author the tests
as part of the locked contract; the runtime puts them in place for you.

## Common false-park causes and how to author around them

| Symptom                                   | Cause                                            | Author around it                                       |
| ----------------------------------------- | ------------------------------------------------ | ------------------------------------------------------ |
| `out_of_scope_path` on a barrel file      | mechanical export not in `likely_files` (`8mnx`) | rely on always-allowed classes; don't over-enumerate   |
| `protected_path_change` on `tests/**`     | tried to let the agent write tests (`dxgw`)      | lock tests in the contract; Option C materializes them |
| `max_files_changed` exceeded              | slice too big                                    | split into independently-gateable slices               |
| slice parks with `no acceptance criteria` | criterion missing or vacuous                     | give every slice ≥1 falsifiable, test-backed criterion |

## See also

- [task-graph-authoring.md](task-graph-authoring.md) — turning these slices into
  an approved DB graph.
- [gap-log-template.md](gap-log-template.md) — recording what the gate teaches
  you each run.
- `docs/solutions/architecture-patterns/gate-rejects-agent-authored-tests-option-b-dead-end.md`
  — the full `dxgw` finding.
