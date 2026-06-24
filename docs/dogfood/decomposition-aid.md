# Decomposition Aid — prose plan → verified `conveyor.plan@1`

Turn a hand-written prose plan into a `conveyor.plan@1` work-graph that
`mix conveyor.run` can execute, using an external AI to **draft** and you to
**verify**. This is deliberately external and human-gated — in-factory
autonomous authoring (PlanFoundry / ContractForge / ContractCritic) is M5 /
ADR-27 and out of scope here.

The authority for the shape is `docs/schemas/conveyor.plan@1.json` (plus
`docs/schemas/conveyor.work_graph@2.json` for the dependency graph). The worked
example is `samples/gx/conveyor.plan.yml` — read it before drafting.

---

## Part A — Drafting prompt

Paste this into an external AI (Claude / Codex), followed by your prose plan.

> You are drafting a `conveyor.plan@1` work-graph for an autonomous build. Emit
> **only** YAML conforming to `conveyor.plan@1` (mirror the structure of
> `samples/gx/conveyor.plan.yml`). Required top-level keys:
>
> - `schema_version: conveyor.plan@1`
> - `project: {key, base_ref}`
> - `goal` — one paragraph, the hermetic/deterministic outcome
> - `non_goals` — explicit exclusions
> - `requirements` — list of `{key: REQ-NNN, text, risk: low|medium|high, source_ref, status}`
> - `acceptance_criteria` — list of `{key: AC-NNN, text, requirement_refs, required_test_refs}`; every requirement needs at least one, and each names concrete `path::test_name` references
> - `verification_commands` — list of `{key, argv, profile}` (e.g. `{key: pytest, argv: ["pytest","-q"], profile: verify}`)
> - `decisions` — list of `{key: DEC-NNN, decision, rationale}` for the load-bearing choices (interfaces frozen, hermeticity boundary)
> - `slices` — list of `{key: SLICE-NNN, title, requirement_refs, likely_files, conflict_domains, autonomy_ceiling}`; one small, independently verifiable concern each
> - `work_dependencies` — list of `{from: SLICE-NNN, to: SLICE-NNN, kind}`; add an edge **only** when the `to` slice needs the `from` slice's frozen interface
>
> Rules: keep the target greenfield, read-only, and deterministic (no network,
> no clock, no dict/set iteration-order dependence). Freeze the smallest possible
> set of cross-slice interfaces and name them in `decisions`. Size for ~10–20
> slices to start. Do not invent fields outside the schema.

---

## Part B — Verification checklist (you, before any run)

Run top to bottom. Any failure means fix the draft, not the run.

1. **Schema valid** — the draft conforms to `docs/schemas/conveyor.plan@1.json`; the dependency graph conforms to `conveyor.work_graph@2.json`.
2. **Lint clean** — `mix conveyor.plan_lint <plan.yml>` and `mix conveyor.plan_audit <plan.yml>` both pass. These catch unknown-reference, self-loop, and cycle errors in `work_dependencies` — the same errors the loader rejects at load time, so a clean lint means the run will start.
3. **Coverage** — every `REQ-NNN` has at least one `AC-NNN` whose `required_test_refs` name real, locked tests. No orphan requirement, no acceptance criterion without a test ref.
4. **Locked tests present in the workspace** — the tests named in `required_test_refs` exist in the target workspace, are locked, and are RED before the run (mirror `samples/gx/` — stubs + locked tests + a verification command the gate runs). The agent's job is to turn them green; if they are absent or already green, the gate proves nothing.
5. **Slices are small and single-concern** — each slice owns one capability and a tight `likely_files` set; `conflict_domains` are distinct (this is what later parallelism keys on).
6. **Dependency edges are real** — a `work_dependencies` edge exists only where the `to` slice needs the `from` slice's frozen interface. A *missing* edge (false independence) detonates later; a *spurious* edge only over-serializes (harmless now).
7. **Target is greenfield and safe** — a fresh project with nothing to lose. There is no blast-radius container yet, so do not point a run at an existing repo you care about.
8. **Dry-run before live (mandatory).** Run the plan on a free deterministic adapter first:
   ```
   mix conveyor.run <plan.yml> --adapter reference_solution --workspace <ws>
   ```
   This exercises the harness and graph with zero agent stochasticity, so any failure here is a decomposition or harness gap — not the agent. Only once it is clean:
   ```
   mix conveyor.run <plan.yml> --adapter codex --workspace <ws>
   ```

---

## What this is not

- **Not** autonomous decomposition. You draft with an external AI and verify by hand; conveyor does not author the graph (that is M5).
- **Not** a correctness guarantee. The dry-run validates the harness; the live run tests whether the agent can actually build each slice. Read the result with `mix conveyor.run_view <run_id>` and log gaps (see `docs/dogfood/gap-log-template.md`).
