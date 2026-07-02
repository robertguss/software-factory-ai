# Config-Surface Truth Audit

**Bead:** never-lie-mmxr.1 &nbsp;|&nbsp; **Generated from:** adversarially-verified multi-agent audit (66 agents) &nbsp;|&nbsp; **Date:** 2026-07-02

Every operator-editable configuration surface, traced to whether a production `mix conveyor.run` actually consumes it. Inert config is the most corrosive small lie: an operator edits a file before an unattended run and sleeps on a false belief. This table is the standing record; the flip-test guard (`test/conveyor/config_surface_truth_test.exs`) keeps it honest.

## Verdict legend

- **load_bearing** — production reads it and behavior depends on it (evidence = read site).
- **advisory** — feeds generated docs (AGENTS.md) by design; not a runtime control.
- **infra** — standard Phoenix/Ecto/endpoint plumbing, inherently load-bearing.
- **inert** — parsed/validated but never consumed, or consumed-but-ignored. **These are the lies.** Each shipped inert key carries an `# ADVISORY:` banner in its template; the wholly-inert `.conveyor/prompts/` surface is tracked for wiring.

## Summary

| Verdict | Count |
| --- | --- |
| load_bearing | 22 |
| advisory | 11 |
| infra | 11 |
| inert | 17 |
| **total** | **61** |


## `.conveyor/config.toml`

| Knob | Verdict | Evidence (file:line) | Consuming test |
| --- | --- | --- | --- |
| `[project].name` | advisory | lib/conveyor/agents_md.ex:43 (interpolated into generated AGENTS.md prose). Run path uses DB Factory.Project.name instead: lib/conveyor/planning/contract_builder.ex:52 reads project.name off Ash.get!(Project,...), never config. | none |
| `[project].repo_path` | advisory | lib/conveyor/agents_md.ex:43 only. No other reader of config.repo_path in lib/ (grep '.repo_path' returns just this site). | none |
| `[project].default_branch` | advisory | lib/conveyor/agents_md.ex:43 (AGENTS.md prose). Run/plan path reads DB Project.default_branch instead: lib/conveyor/planning/contract_builder.ex:52 and lib/mix/tasks/conveyor.plan.create.ex:110 both read it off the Ash resource, not config. | none |
| `[project].dev_branch` | advisory | lib/conveyor/agents_md.ex:124-126 (dev_branch/1 helper) → interpolated at agents_md.ex:43. Optional; grep '.dev_branch' finds no other reader. | none |
| `[project].default_autonomy_level` | inert | Parsed into ProjectConfig (config.ex:44-45,58) and enum-validated, but ProjectConfig.default_autonomy_level is never read anywhere in lib/. The run-path autonomy check reads the DB resource: lib/conveyor/slice_lifecycle.ex:130 and lib/conveyor/planning/plan_importer.ex:70 both read project.default_autonomy_level off Factory.Project, not config. | none |
| `[project].policies_dir` | load_bearing ⚑ | **(verify-corrected)** lib/conveyor/agents_md/linter.ex:88-89 (load_policy_denylist reads config.policies_dir via Path.expand, loads *.toml denylists) feeding check_forbidden_actions at linter.ex:59/195; consumed in production by mix conveyor.agents.lint at lib/mix/tasks/conveyor.agents.lint.ex:14. Config value is the operator's, required at lib/conveyor/config.ex:46. This refutes the auditor's 'only reader is doctor (doctor.ex:577)' claim. | none |
| `[project].prompts_dir` | inert | Parsed into ProjectConfig (config.ex:47) but grep '.prompts_dir' / 'prompts_dir' across lib/ returns no reader at all outside config.ex. Dead config value. | none |
| `[project].runs_dir` | inert | Only reader is the doctor diagnostic at lib/conveyor/doctor.ex:588 (check_artifact_dirs asserts the dir exists). No run-path artifact writer reads config.runs_dir. | none |
| `[project].blobs_dir` | inert | Only reader is lib/conveyor/doctor.ex:588 (same check_artifact_dirs loop as runs_dir). No run-path blob store reads config.blobs_dir. | none |
| `[project].quality_adapter` | advisory | lib/conveyor/agents_md.ex:91 (renders 'Treat code-quality context from <adapter> as advisory...' into AGENTS.md). Also matched as a literal 'codescent' string by the doctor optional-adapter check at lib/conveyor/doctor.ex:599. Not read by any run/gate stage. | none |
| `[[project.command_specs]].key` | advisory | Rendered into AGENTS.md at lib/conveyor/agents_md.ex:134 and :145. Run-path verify commands come from the plan, not config: lib/conveyor/stations/verify.ex:91 (commands = plan["verification_commands"]) and lib/conveyor/planning/run_spec_assembler.ex:623-635 (sources from plan_contract + DB project). | none |
| `[[project.command_specs]].argv` | advisory | Rendered into AGENTS.md at lib/conveyor/agents_md.ex:134,145,157 (render_argv). The argv actually executed by the run is built from plan/DB maps: command_runner.ex:116 constructs a CommandSpec from a map whose argv came from run_spec_assembler.ex:636 (list(command,"argv") off plan_contract), and NormalizedCommand.normalize! (normalized_command.ex:52) splits that — never the config struct. | none |
| `[[project.command_specs]].cwd` | inert | Parsed into CommandSpec.cwd (config.ex:145). tool_executor.ex:106/173 and normalized_command.ex:57 read command.cwd, but that struct is the one built by command_runner.ex:116 from a plan/DB map (default project.local_path at run_spec_assembler.ex:637), not the config.toml CommandSpec. | none |
| `[[project.command_specs]].profile` | advisory | Rendered into AGENTS.md at lib/conveyor/agents_md.ex:145 ([#{command.profile}, ...]). Not read by the run; the executed spec's profile defaults to 'verify' from the plan (run_spec_assembler.ex:638). | none |
| `[[project.command_specs]].required` | advisory | Rendered into AGENTS.md at lib/conveyor/agents_md.ex:145 (required/optional label). The run's required? flag comes from the plan/DB spec (run_spec_assembler.ex:639), not config. | none |
| `[[project.command_specs]].timeout_ms` | inert | Parsed into CommandSpec.timeout_ms (config.ex:147). Runtime timeout is read from the plan/DB-built struct at normalized_command.ex:63 (fed by command_runner.ex:116, default 120_000 at run_spec_assembler.ex:640) — never the config value. Not rendered into AGENTS.md. | none |
| `[[project.command_specs]].network` | advisory | Rendered into AGENTS.md at lib/conveyor/agents_md.ex:145 (network: #{command.network}). Run-path network enforcement comes from the policy profile + plan spec (run_spec_assembler.ex:641 default 'none'), not this config field. | none |
| `[[project.command_specs]].env_allowlist` | inert | Parsed into CommandSpec.env_allowlist (config.ex:149). normalized_command.ex:58 reads command_spec.env_allowlist, but off the plan/DB-built struct (command_runner.ex:116, sourced from run_spec_assembler.ex:642), not config. Not rendered into AGENTS.md. | none |
| `[[project.command_specs]].output_limit_bytes` | inert | Parsed into CommandSpec.output_limit_bytes (config.ex:150). No reader of the config struct's output_limit_bytes in lib/; the run's limit is carried on the plan/DB command map (run_spec_assembler.ex:643). | none |
| `[[project.command_specs]].result_format` | inert | Parsed into CommandSpec.result_format (config.ex:151). Run-path result_format is read off the plan/DB VerificationSuite: command_suite_runner.ex:92 and evidence/verification_rerunner.ex:265 read value(command_spec,"result_format") from the plan map (default 'junit' at run_spec_assembler.ex:647), not the config struct. | none |
| `[[project.command_specs]].result_adapter` | inert | Parsed into CommandSpec.result_adapter (config.ex:139,152). command_runner.ex:127 reads value(map,"result_adapter") off the plan/DB map, not the config struct; nothing reads the config CommandSpec.result_adapter field. Not in AGENTS.md. | none |
| `[[project.always_allowed_path_classes]] (name/globs) — NOT in shipped template` | load_bearing | lib/conveyor/planning/run_spec_assembler.ex:303 (load_scope_classes returns config.always_allowed_path_classes) → create_default_diff_policy! (run_spec_assembler.ex:290,337) writes it onto DiffPolicy.always_allowed_path_classes → the DiffScope gate stage consumes it at lib/conveyor/gate/stages/diff_scope.ex:123 to grant otherwise-out-of-scope files. | test/conveyor/run_spec_assembler_test.exs:54 (writes .conveyor/config.toml with [[project.always_allowed_path_classes]], asserts at :63 it lands on the DiffPolicy and at :67-69 that DiffScope grants docs/readme.md end-to-end). |

## `.conveyor/policies/*.toml`

| Knob | Verdict | Evidence (file:line) | Consuming test |
| --- | --- | --- | --- |
| `[policy].profile` | load_bearing | lib/conveyor/stations/implementer.ex:139 (Enum.find profile==:implement) and lib/conveyor/stations/verify.ex:116 (profile==:verify) select the enforced Policy; lib/conveyor/policy/profiles.ex:101-116 require_complete_profile_set gates run start (missing profile -> raise) | test/conveyor/policy/profiles_test.exs:50 (missing required profiles fail loudly); test/conveyor/plan_runner_db_test.exs:114 selects loaded policy by profile |
| `[policy].network` | load_bearing | lib/conveyor/policy/profiles.ex:58,74 -> network_policy["default"]; enforced at lib/conveyor/agent_runner/contained_exec.ex:97-110 (docker --network none/egress on the implement/ClaudeCode path) and lib/conveyor/policy/engine.ex:88-95 (network_allowed? on verify generic path) | test/conveyor/agent_runner/contained_exec_test.exs:49 (egress->--network bridge), :27/37 (none->--network none); test/conveyor/policy/engine_test.exs:61 (blocks network outside policy) |
| `[policy.env].allowlist` | load_bearing | lib/conveyor/policy/profiles.ex:73 -> env_policy (whole table); enforced at lib/conveyor/agent_runner/contained_exec.ex:123-128 (only allowlisted host env keys cross the docker boundary, implement path) and lib/conveyor/policy/engine.ex:82-86 (env_allowed? on verify generic path) | test/conveyor/agent_runner/contained_exec_test.exs:61 (only allowlisted env crosses; ANTHROPIC_API_KEY refuted); test/conveyor/policy/engine_test.exs:53 (blocks env outside allowlist) |
| `[policy].allowlist` | load_bearing | lib/conveyor/policy/profiles.ex:55-56,70 -> Policy.allowlist; enforced ONLY at lib/conveyor/policy/engine.ex:97-100 via lib/conveyor/tool_executor.ex:36, reached from lib/conveyor/verification/command_runner.ex:62 (verify GENERIC command engine). NOT enforced on implement path: lib/conveyor/agent_runner/claude_code.ex:150 hardcodes decision=allowed, never calls ToolExecutor | test/conveyor/policy/engine_test.exs:9,17 (allows match / blocks non-allowlisted) — Engine unit, hand-built Policy, not the loaded TOML |
| `[policy].denylist` | load_bearing | lib/conveyor/policy/profiles.ex:57,70 -> Policy.denylist; enforced ONLY at lib/conveyor/policy/engine.ex:102-105 via ToolExecutor (verify generic command engine). Not reached by ClaudeCode implement path (claude_code.ex:150) | test/conveyor/policy/engine_test.exs:25,33 (denylist after allowlist; blocks dangerous classes) — Engine unit, not loaded TOML |
| `[policy].name` | advisory | lib/conveyor/policy/profiles.ex:52,69 -> Policy.name (required_string, fail-closed at parse). Read only descriptively: lib/conveyor/agent_runner/pi.ex:204 policy_snapshot; tool_executor records use profile not name. No enforcement branch reads name | none (test/conveyor/policy/profiles_test.exs:16 asserts the parsed value, not any behavior) |
| `[policy].autonomy_ceiling` | inert | lib/conveyor/policy/profiles.ex:54,76 -> Policy.autonomy_ceiling (validated L0-L4). The only reader is lib/conveyor/agent_runner/pi.ex:211 policy_snapshot (pi adapter, NOT the production ClaudeCode adapter). ClaudeCode, ContainedExec, verify, and Engine never read policy.autonomy_ceiling | none for enforcement on the mix conveyor.run path |
| `[policy.env].deny_production_secrets` | inert | Stored inside env_policy map (lib/conveyor/policy/profiles.ex:73 copies the whole [policy.env] table). grep 'deny_production_secrets' across lib/ returns ZERO consumers | none |
| `[policy].future_gated` | inert | lib/conveyor/policy/profiles.ex:59-65 folds future_gated into budget_policy["future_gated"]. grep 'future_gated' across lib/ returns no consumer outside profiles.ex | none (test/conveyor/policy/profiles_test.exs:30 asserts it is stored in budget_policy, nothing reads it) |
| `[policy.budget].max_tool_calls` | inert | lib/conveyor/policy/profiles.ex:62-64 -> Policy.budget_policy map. Only reader of policy.budget_policy is lib/conveyor/agent_runner/pi.ex:210 (snapshot). Budget enforcement (lib/conveyor/policy/run_budget_guard.ex:120) reads the SEPARATE Factory.RunBudget resource's max_tool_calls, not policy.budget_policy | none (test/conveyor/policy/run_budget_guard_test.exs exercises the RunBudget resource, not the TOML value) |

## `.conveyor/prompts/*`

| Knob | Verdict | Evidence (file:line) | Consuming test |
| --- | --- | --- | --- |
| `.conveyor/prompts/implementation-prompt@1.md (src: priv/conveyor/templates/prompts/implementation-prompt@1.md)` | inert | lib/conveyor/prompt_builder.ex:134-222 — the implementer prompt body is a compiled-in heredoc in render_prompt/1 (invoked at build_builder line 50, called from lib/conveyor/stations/implementer.ex:104). No File.read of `.conveyor/prompts/implementation-prompt@1.md` exists anywhere in lib/ (grep of File.read* + `.conveyor/prompts` returns only the copy in lib/mix/tasks/conveyor.init.ex:25). The string `implementation-prompt@1` is used ONLY as the @template_version label (prompt_builder.ex:17) stamped on the RunPrompt row / instruction-source ref. | none — test/mix/tasks/conveyor_init_test.exs:22 only asserts File.regular? (materialization); test/conveyor/prompt_builder_test.exs:137-176 snapshots the compiled-in body, proving the text comes from code not the file |
| `.conveyor/prompts/reviewer@1.md (src: priv/conveyor/templates/prompts/reviewer@1.md)` | inert | lib/conveyor/reviewer/rubric.ex:41-74 — the reviewer prompt is a compiled-in string list in Rubric.render_prompt/2, invoked by the production reviewer Conveyor.Reviewer.ContainedReviewer at lib/conveyor/reviewer/contained_reviewer.ex:31 (the `:reviewer` fun RunReviewer calls). Rubric.load/1 (rubric.ex:26, path/1 at rubric.ex:91-93) reads `priv/conveyor/rubrics/<version>.json` — a JSON rubric artifact, NOT the `.conveyor/prompts/reviewer@1.md` markdown. No File.read of the reviewer markdown exists anywhere in lib/. `reviewer@1` is only a rubric-version label (rubric.ex:16; jobs/run_reviewer.ex:38) plus the file copied by conveyor.init.ex:26. | none — test/mix/tasks/conveyor_init_test.exs:23 only asserts File.regular? (materialization); test/conveyor/reviewer/rubric_test.exs tests the compiled-in render_prompt output |
| `project.prompts_dir config key (config.toml)` | inert | Parsed in lib/conveyor/config.ex:47 and stored on the struct at config.ex:60 / lib/conveyor/config/project_config.ex:15,31,43, but grep shows NO production read of `config.prompts_dir` / `.prompts_dir` to dereference the directory and load a prompt. It is the natural hook that would make the two files above load-bearing, and it too is never consumed. | none — test/conveyor/config_test.exs:20 and others only assert it parses to ".conveyor/prompts"; no test exercises loading a prompt from it |

## `config/runtime.exs env vars`

| Knob | Verdict | Evidence (file:line) | Consuming test |
| --- | --- | --- | --- |
| `DATABASE_URL` | infra | config/runtime.exs:24-25 (read, raises if missing) → consumed at config/runtime.exs:35 as Conveyor.Repo `url` | none |
| `POOL_SIZE` | infra | config/runtime.exs:36 → Conveyor.Repo `pool_size` (String.to_integer, default "10") | none |
| `SECRET_KEY_BASE` | infra | config/runtime.exs:44-45 (read, raises if missing) → consumed at config/runtime.exs:66 as ConveyorWeb.Endpoint `secret_key_base` | none |
| `PHX_HOST` | infra | config/runtime.exs:51 (default "example.com") → consumed at config/runtime.exs:57 as Endpoint `url: [host: host, ...]` | none |
| `PORT` | infra | config/runtime.exs:52 (String.to_integer, default "4000") → consumed at config/runtime.exs:64 as Endpoint `http: [port: port]` | none |
| `PHX_SERVER` | infra | config/runtime.exs:19-20 → sets ConveyorWeb.Endpoint `server: true` | none |
| `ECTO_IPV6` | infra | config/runtime.exs:31 (truthy on "true"/"1") → consumed at config/runtime.exs:37 as Conveyor.Repo `socket_options: [:inet6]` | none |
| `DNS_CLUSTER_QUERY` | infra | set at config/runtime.exs:54 (`config :conveyor, :dns_cluster_query`); value IS consumed at lib/conveyor/application.ex:13 → `{DNSCluster, query: Application.get_env(:conveyor, :dns_cluster_query) \|\| :ignore}`; dep {:dns_cluster, "~> 0.1.1"} at mix.exs:54 | none |

## `CLI per-plan/per-slice knobs`

| Knob | Verdict | Evidence (file:line) | Consuming test |
| --- | --- | --- | --- |
| `conveyor.run --adapter` | load_bearing | lib/mix/tasks/conveyor.run.ex:35,68 maps string->module via adapter!/1 and passes agent_adapter into PlanRunner; plan_runner.ex:82,91 threads it into run_spec_opts; run_spec_assembler.ex:163 writes it as the implement station's "adapter" (and agent_profile_snapshot at :230) which selects the AgentRunner that actually executes the slice | test/mix/tasks/conveyor_operator_tasks_test.exs:172 |
| `conveyor.run --workspace` | load_bearing | lib/mix/tasks/conveyor.run.ex:36,89 (+ isolate!/1 at 100-130) -> plan_runner.ex:89 threads workspace_path into run_spec_opts (consumed by serial_driver.ex:986-1003 for git reset/clean/commit + locked-test materialization at 894-901) AND plan_runner.ex:115 load_workspace_policies! reads .conveyor/policies from it | test/mix/tasks/conveyor_run_test.exs:78 |
| `conveyor.run --in-place` | load_bearing | lib/mix/tasks/conveyor.run.ex:106 resolve_workspace!/1 branches: with --in-place the run executes directly in --workspace, otherwise isolate!/1 copies to a throwaway dir. Load-bearing because the loop git-resets/cleans/commits the workspace, so this decides whether the operator's real dir is mutated | test/mix/tasks/conveyor_run_test.exs:92 |
| `conveyor.run --blob-root` | load_bearing | lib/mix/tasks/conveyor.run.ex:67 -> plan_runner.ex:90 (\|\| default_blob_root at :149) threads blob_root into run_spec_opts; consumed by serial_driver.ex:619 (run_slice_opts) and run_spec_assembler.ex:142,159,173 (baseline_health/implement/record_evidence station inputs) as the evidence blob store root | test/mix/tasks/conveyor_operator_tasks_test.exs:174 |
| `conveyor.run_slice --blob-root` | load_bearing | lib/mix/tasks/conveyor.run_slice.ex:25 passes blob_root (default ".conveyor/blobs") into RunSlice.run!; :31 also forwards it to Projector.project_run! | test/mix/tasks/conveyor_operator_tasks_test.exs:51-62 |
| `conveyor.run_slice --projection-root` | load_bearing | lib/mix/tasks/conveyor.run_slice.ex:31 forwards projection_root to Projector.project_run!; consumed at lib/conveyor/artifacts/projector/local_disk.ex:23-24 as the on-disk projection output directory (default ".conveyor/runs") | test/mix/tasks/conveyor_demo_test.exs:50 |
| `conveyor.plan.create --workspace-path` | load_bearing | lib/mix/tasks/conveyor.plan.create.ex:46,51 -> find_or_create_project!/2 at :95-98 uses it as Project.local_path (project identity / reuse key) | test/mix/tasks/conveyor_plan_cli_test.exs:145 |
| `conveyor.plan.create --intent` | load_bearing | lib/mix/tasks/conveyor.plan.create.ex:48,61 sets Plan.intent and :107 build_contract puts it as the contract "goal" | test/mix/tasks/conveyor_plan_cli_test.exs:94 |
| `conveyor.plan.create --title` | load_bearing | lib/mix/tasks/conveyor.plan.create.ex:47,60 sets Plan.title and :72 defaults the Epic.title/description from it | test/mix/tasks/conveyor_plan_cli_test.exs:94 |
| `conveyor.plan.create --verification-command` | load_bearing | lib/mix/tasks/conveyor.plan.create.ex:37 (:keep) -> verification_commands/1 at :121-129 -> build_contract :115 writes contract verification_commands (survives lock-time recompile onto the run path) | test/mix/tasks/conveyor_plan_cli_test.exs:122 |
| `conveyor.plan.create --epic-title` | load_bearing | lib/mix/tasks/conveyor.plan.create.ex:76 sets Epic.title (defaults to --title when absent) | none |
| `conveyor.plan.create --project-name` | load_bearing | lib/mix/tasks/conveyor.plan.create.ex:51,98 sets Project.name on create (defaults "conveyor-plan") | none |
| `conveyor.plan.import --workspace-path` | load_bearing | lib/mix/tasks/conveyor.plan.import.ex:24,54-58 import_opts/1 -> PlanImporter.import_result!/2 workspace_path (project local_path / reuse), defaulting to the document's directory | none |
| `conveyor.plan.approve --yes` | load_bearing | lib/mix/tasks/conveyor.plan.approve.ex:40 short-circuits confirm?/1 (the Mix.shell().yes? prompt) so approve_all!/1 runs non-interactively | test/mix/tasks/conveyor_plan_approve_test.exs:22 |
| `conveyor.plan_prepare --no-agents` | load_bearing | lib/mix/tasks/conveyor.plan_prepare.ex:22 `true <- Keyword.get(opts, :no_agents, false)` gates the whole command; also echoed to output at :49 | none |
| `conveyor.plan_prepare --format` | infra | lib/mix/tasks/conveyor.plan_prepare.ex:23,38-54 selects human vs json rendering only via render/2 | none |
| `conveyor.plan_lint --format` | infra | lib/mix/tasks/conveyor.plan_lint.ex:21,24 PlanLintCLI.parse_format + PlanLint.render(format:) selects human\|json\|sarif output only | test/mix/tasks/conveyor_plan_lint_test.exs |
| `conveyor.plan_audit (positional PLAN.md)` | infra | lib/mix/tasks/conveyor.plan_audit.ex:23 takes a single positional path; no OptionParser, no flags | test/mix/tasks/conveyor_plan_audit_test.exs |


⚑ = adversarial verify overturned the first-pass verdict (evidence column shows the corrected trace).

## Convention (new knobs)

Any new operator-editable configuration key added to a shipped template **must** either (a) be load-bearing with a consuming test and an entry in this table, or (b) carry an explicit `# ADVISORY:` banner in its template. The flip-test guard (`test/conveyor/config_surface_truth_test.exs`) fails CI on an un-audited shipped key.
