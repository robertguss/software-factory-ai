# Phase 1 Success Questionnaire

Status: Phase 1 tracer is useful, but Phase 2 should invest in gate trust before parallelism.

Source: §28 of `PHASE-0-1-IMPLEMENTATION-PLAN.md`.

## Answers

### Does the loop feel right on a real change?

Yes for a single Slice. The loop now has a hermetic tracer path from seeded Slice to reported RunAttempt through `Conveyor.Demo`, `Conveyor.RunSlice`, artifact projection, replay, and manual integration capture. Evidence: `test/conveyor/e2e_tracer_test.exs` drives the full demo, checks `RunAttempt.status == :reported`, records a manual non-integration action, and verifies replay regenerates the same bundle root.

Remaining risk: this is still a fake-runner tracer. Live Pi coverage remains intentionally behind `@tag :live_agent`.

### Can plan audit distinguish executable handoff from vague prose?

Mostly yes. Plan audit and readiness are schema-backed rather than prose-only: `Conveyor.PlanAuditor`, `Conveyor.Traceability`, `Conveyor.Readiness`, AgentBrief/TestPack/ContractLock resources, and the design-law invariant suite all check contract shape, traceability, and handoff completeness. Evidence: `test/conveyor/design_laws_invariant_test.exs`, `test/conveyor/plan_import_test.exs`, and the ContractLock gate tests.

Remaining risk: the plan compiler still needs more negative examples before it should be trusted for broad incoming plans.

### Can the gate reject labeled bad changes with zero false negatives on the initial mutant set?

The harness exists and measures false negatives, but the current fixture suite still demonstrates why this must stay a trust gate. Evidence: `Conveyor.Jobs.RunGateCanary`, `mix conveyor.gate_canary`, and `test/mix/tasks/conveyor_gate_canary_test.exs` write `canary/mutants.json` and return the canary-specific exit code when false negatives are present.

Verdict: not yet a Phase-2 parallelism unlock. Gate hardening is the next investment.

### Is the Pi/RPC seam clean enough to keep, or should the next adapter be prioritized?

Keep the seam. The fake and Pi runners share conformance-oriented behavior around RunPrompt, PatchSet capture, policy, and event recording. Evidence: `test/conveyor/agent_runner_fake_test.exs`, `test/conveyor/agent_runner_pi_test.exs`, and `test/support/agent_runner_conformance.ex`.

Next adapter work should be incremental and contract-driven, not a redesign.

### Are the Ash schemas stable under a real run?

Stable enough for Phase 1. The tracer now exercises RunSpec, RunAttempt, StationRun, StationEffect, artifacts, reviews, gate results, human approvals, external changes, RunBundle, retrospective, and replay. Evidence: full test suite passed with `358 passed, 1 excluded` during this implementation run; schema-focused tests cover the resources under `test/conveyor/factory/`.

Remaining risk: swarm-readiness has explicit Phase-1 placeholders for metrics that do not yet deserve dedicated columns.

### Does `AGENTS.md` reduce prompt ambiguity?

Yes. The repo-level instructions forced consistent `br` usage, prevented `bd`, and required test-first implementation. The AGENTS linter and generator also encode the expected command and safety guidance. Evidence: `test/conveyor/agents_md_test.exs`, `test/conveyor/agents_md_linter_test.exs`, and this run’s bead workflow.

### Does CodeScent provide useful scout/gate signals without being mistaken for proof?

Yes, as an advisory signal only. The UI/report surface labels CodeScent as a delta, and the gate/code-quality tests keep it separate from RunCheck proof. Evidence: `lib/conveyor/code_quality_adapter/code_scent.ex`, `test/conveyor/code_quality_adapter_test.exs`, and `test/conveyor/gate_stages_code_quality_test.exs`.

### Are artifacts reviewable enough to support eventual PR generation?

Yes for Phase 1. The projector now writes manifest, dossier, evidence, gate, review, PR body, diff, and retrospective artifacts; replay regenerates the bundle deterministically. Evidence: `test/conveyor/artifacts/projector_test.exs`, `test/conveyor/replay_test.exs`, and `test/mix/tasks/conveyor_report_test.exs`.

### Did policy block anything useful or miss anything dangerous?

Policy blocking is useful but still needs a threat-coverage audit. The policy engine blocks secret, network, budget, and scope violations in focused tests. Evidence: `test/conveyor/gate_stages_policy_secret_test.exs`, `test/conveyor/policy/run_budget_guard_test.exs`, `test/conveyor/tool_executor_test.exs`, and `test/conveyor/sandbox/network_policy_test.exs`.

Remaining risk: `software-factory-ai-iqb.15.4` exists because every §12.0 threat class still needs a mapped test/canary/doctor check.

## Phase 2/3 Assumptions

Phase 2 assumptions hold if it focuses on trust: stronger canary coverage, threat-matrix completeness, and better plan-compiler negatives.

Phase 3 parallelism does not hold yet. More agents should wait until gate false negatives and threat coverage are materially improved.

## Recommended Next Investment

Invest next in the gate: finish the threat-matrix completeness audit, reduce canary false negatives, and add missing negative fixtures. A better plan compiler is second. Parallelism should wait until the single-run trust loop is harder to fool.
