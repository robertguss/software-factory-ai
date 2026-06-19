# Phase 0/1 Retrospective

Status: accepted

Date: 2026-06-19

Baseline: [phase-1-baseline-freeze.json](phase-1-baseline-freeze.json)

## Summary

The local Phase 0/1 baseline has enough deterministic schema, gate, projection,
policy-template, and sample-runner surface to start P15-A0. It does not yet
prove generated-contract quality or live adapter qualification. That uncertainty
is intentionally carried into `PhaseNextDecision` instead of hidden behind a
premature broad grant.

## Loop and Authority

Measured signal: the repository contains public Mix tasks for CI, canary,
reporting, replay, plan audit, run execution, and external-merge marking. The
baseline freeze captures `mix.lock`, `mise.toml`, policy templates, and prompt
templates by digest.

Answer: authority is sufficiently explicit for a local single-repo tracer, but
not yet sufficient for fleet or broad autonomous execution. Later work must use
typed PolicyDecision and authority-root artifacts before activating larger
scopes.

## Gate Canary Health

Measured signal: `lib/mix/tasks/conveyor.gate_canary.ex` and
`lib/conveyor/eval_suites.ex` are frozen in the baseline. Existing tests include
gate, canary, run bundle, and artifact projection coverage.

Answer: canary infrastructure exists, but P15-A0 should still treat the canary
set as baseline evidence rather than final qualification. False-negative canary
findings remain stop-the-line.

## Adapter Events and Cancellation

Measured signal: agent runner implementations and event recorder modules exist,
with test coverage for fake and PI adapters. The baseline does not contain a
live-provider qualification grant.

Answer: adapter behavior is locally testable, but live event loss, cancellation,
and capability-truth claims remain P15-B responsibilities.

## Sandbox and Role Boundaries

Measured signal: sandbox runner, Docker profile, network policy, policy
executor, credential broker, and AGENTS.md linter tests are present. The Phase 1
baseline freezes policy templates and the sample runner profile.

Answer: local boundaries are inspectable and testable. They are not a prompt
injection boundary by themselves and must be lifted into RoleViews and
ToolContracts in P15-A2.

## Evidence Integrity

Measured signal: artifact projection, run bundle, evidence, review, gate, and
schema examples are present and baseline-digested. The new
`conveyor.phase_next_decision@1` schema makes the branch decision an explicit
artifact.

Answer: evidence integrity is strong enough for P15-A0 artifacts. It still needs
canonical DigestRef, SchemaRegistryEntry, attestation envelope, and root
construction work before later release authority.

## Context Recall

Measured signal: Context Scout implementation and tests exist. No P15-A0
measured incident currently proves repeated necessary-file omissions.

Answer: `context_first` is not selected in the initial decision, but the golden
journey suite keeps context omissions visible as a regression class.

## Operability

Measured signal: report, replay, retrospective projection, LiveView run viewer,
and artifact projector tests exist. Operators can inspect machine artifacts, but
some diagnosis still depends on knowing which projection to open.

Answer: select `operability_first` as a non-blocking branch. It does not block
minimum P15-A0 progress, but typed comparison and failure taxonomy need to stay
visible in every golden journey.
