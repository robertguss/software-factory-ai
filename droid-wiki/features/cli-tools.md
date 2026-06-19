# CLI tools

Conveyor's operator surface is a set of mix tasks in `lib/mix/tasks/`. They are thin: parse args, call `Conveyor.*` modules, format output, and return stable exit codes. Business logic lives in the core modules, not in the tasks. Downstream automation reads these commands, so output and exit codes are contracts.

## Command reference

| Command | Purpose |
| --- | --- |
| `mix conveyor.init PROJECT_PATH` | Scaffolds `.conveyor/` config, policies, prompts, artifact dirs, and an initial AGENTS.md |
| `mix conveyor.agents PROJECT_PATH` | Regenerates AGENTS.md from `.conveyor/config.toml` |
| `mix conveyor.agents.lint PROJECT_PATH` | Lints AGENTS.md against config and policy; exits 0/1 |
| `mix conveyor.plan_lint PLAN.md --format human\|json\|sarif` | Deterministic, non-authorizing plan lint |
| `mix conveyor.plan_prepare PLAN.md --no-agents --format human\|json` | Builds a static, non-authorizing plan preparation package |
| `mix conveyor.plan_audit PLAN.md` | Audits a normalized plan contract and imports it into the work graph |
| `mix conveyor.contract_lint agent_brief.json --format human\|json\|sarif` | Non-authorizing lint on a compiler contract or agent brief |
| `mix conveyor.contract_diff --old OLD.json --new NEW.json` | Prints a classified contract diff as JSON |
| `mix conveyor.seed_sample` | Seeds the Phase 1 sample tasks work graph |
| `mix conveyor.run_slice RUN_ATTEMPT_ID [--blob-root PATH] [--projection-root PATH]` | Runs one RunAttempt through its station plan and projects artifacts |
| `mix conveyor.verify RUN_ATTEMPT_ID [--blob-root PATH] [--projection-root PATH]` | Independently re-projects and verifies a RunAttempt artifact bundle |
| `mix conveyor.show SLICE_ID` | Prints compact machine-readable slice and latest run attempt status |
| `mix conveyor.replay` | Rebuilds the R0 human timeline from LedgerEvent records |
| `mix conveyor.replay RUN_ATTEMPT_ID [--blob-root PATH] [--projection-root PATH]` | Re-projects a single run attempt's artifact bundle |
| `mix conveyor.report RUN_ATTEMPT_ID [--blob-root PATH] [--projection-root PATH]` | Regenerates the static artifact report for a run attempt |
| `mix conveyor.doctor [PROJECT_PATH]` | Runs Conveyor prerequisite checks |
| `mix conveyor.demo [--blob-root PATH] [--projection-root PATH]` | Runs the hermetic Phase-1 Conveyor tracer demo |
| `mix conveyor.gate_canary PROJECT_ID [--manifest PATH] [--output PATH]` | Runs the gate-canary fixture suite for a project |
| `mix conveyor.compiler_structure_gate --input compiler-structure.json` | Runs the internal, non-authorizing compiler structure gate |
| `mix conveyor.qualification_bundle --input artifacts.json [--format human\|json]` | Builds an offline-verifiable qualification bundle |
| `mix conveyor.qualification_bundle_verify --offline bundle.json [--format human\|json]` | Verifies a qualification bundle without the live database |
| `mix conveyor.qualification_gate PROJECT_ID --scope k=v[,k=v] --input package.json [--format human\|json]` | Runs the scoped Conveyor qualification gate |
| `mix conveyor.mark_externally_merged RUN_ATTEMPT_ID --external-commit SHA --actor ACTOR` | Records a manual external integration decision (merged) |
| `mix conveyor.mark_externally_merged RUN_ATTEMPT_ID --not-integrated --actor ACTOR` | Records a manual external integration decision (not integrated) |
| `mix conveyor.diff_artifacts ARTIFACT_A ARTIFACT_B [--markdown]` | Compares two artifact subject descriptors |
| `mix conveyor.diff_runs RUN_A RUN_B [--section SECTION] [--markdown]` | Compares two run subject descriptors |
| `mix conveyor.diff_plans REV_A REV_B [--markdown]` | Compares two plan revision descriptors |
| `mix conveyor.diff_candidates CANDIDATE_A CANDIDATE_B [--markdown]` | Compares two candidate descriptors |
| `mix conveyor.diff_grants GRANT_A GRANT_B [--markdown]` | Compares two qualification grant descriptors |
| `mix conveyor.why_different LEFT RIGHT [--markdown]` | Explains why two subject descriptors differ |
| `mix conveyor.why_stale SUBJECT_JSON` | Explains why a subject descriptor is stale |

## Conventions

All tasks follow a few conventions. Tasks that need the application call `Mix.Task.run("app.start")` before doing work. Tasks that write files use idempotency: `conveyor.init` does not overwrite existing files, `conveyor.agents` overwrites by default. Exit codes are stable and sourced from `Conveyor.CLI.ExitCodes` or the relevant module's `exit_code/1` function. Most tasks accept a `--format` flag (`human`, `json`, or `sarif`) where output shape matters.

The evidence time machine diff commands (`diff_runs`, `diff_plans`, `diff_candidates`, `diff_grants`, `diff_artifacts`, `why_different`, `why_stale`) share a common implementation in `Conveyor.EvidenceTimeMachineCommands` and delegate to `Conveyor.Evidence.TimeMachine`. They all compare JSON subject descriptors and can emit markdown.

## Non-authorizing tasks

Several tasks are explicitly non-authorizing: `plan_lint`, `plan_prepare`, `contract_lint`, and `compiler_structure_gate` never invoke agents or execution authority. They are deterministic checks that operators can run before committing to a run. `plan_prepare` is marked `--no-agents` and reports `provider_credentials_required` so operators know what a real run would need without starting one.

## Key source files

| File | Purpose |
| --- | --- |
| `lib/mix/tasks/conveyor.init.ex` | Scaffolds a repository for Conveyor |
| `lib/mix/tasks/conveyor.agents.ex` | Generates AGENTS.md from config |
| `lib/mix/tasks/conveyor.agents.lint.ex` | Lints AGENTS.md against config and policy |
| `lib/mix/tasks/conveyor.plan_lint.ex` | Non-authorizing plan lint |
| `lib/mix/tasks/conveyor.plan_prepare.ex` | Static, non-authorizing plan preparation package |
| `lib/mix/tasks/conveyor.plan_audit.ex` | Audits and imports a normalized plan contract |
| `lib/mix/tasks/conveyor.contract_lint.ex` | Non-authorizing contract or agent brief lint |
| `lib/mix/tasks/conveyor.contract_diff.ex` | Classified contract diff |
| `lib/mix/tasks/conveyor.seed_sample.ex` | Seeds the Phase 1 sample tasks work graph |
| `lib/mix/tasks/conveyor.run_slice.ex` | Runs a RunAttempt station plan |
| `lib/mix/tasks/conveyor.verify.ex` | Re-projects and verifies a RunAttempt bundle |
| `lib/mix/tasks/conveyor.show.ex` | Shows slice and latest run attempt status |
| `lib/mix/tasks/conveyor.replay.ex` | Replays the ledger timeline or re-projects a run |
| `lib/mix/tasks/conveyor.report.ex` | Regenerates a run attempt artifact report |
| `lib/mix/tasks/conveyor.doctor.ex` | Runs prerequisite checks |
| `lib/mix/tasks/conveyor.demo.ex` | Runs the hermetic Phase-1 demo |
| `lib/mix/tasks/conveyor.gate_canary.ex` | Runs the gate-canary fixture suite |
| `lib/mix/tasks/conveyor.compiler_structure_gate.ex` | Non-authorizing compiler structure gate |
| `lib/mix/tasks/conveyor.qualification_bundle.ex` | Builds a qualification bundle |
| `lib/mix/tasks/conveyor.qualification_bundle_verify.ex` | Verifies a qualification bundle offline |
| `lib/mix/tasks/conveyor.qualification_gate.ex` | Runs the scoped qualification gate |
| `lib/mix/tasks/conveyor.mark_externally_merged.ex` | Records a manual external integration decision |
| `lib/mix/tasks/conveyor.evidence_time_machine_commands.ex` | Shared diff/why-stale command implementation |
| `lib/mix/tasks/conveyor.diff_artifacts.ex` | Compares two artifact descriptors |

## Related pages

- [AGENTS.md generation](agents-md-generation.md) — the agents and agents.lint tasks in detail
- [Contract management](contract-management.md) — the contract_diff and contract_lint tasks in detail
- [Station pipeline](station-pipeline.md) — the run_slice task in detail
- [Evidence recording and verification rerunner](../systems/evidence-recording.md) — verify, replay, report, and diff tasks
- [Architecture](../overview/architecture.md) — where CLI tasks sit in the system
