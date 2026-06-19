# Emergency stop

Conveyor has a global emergency stop that blocks work before it starts. An engaged stop blocks new station starts, provider calls, tool calls, claim publication, external effects, and budget reservations. It is not a soft suggestion: the station wrapper checks it before acquiring a lease, and clearing it requires a human decision.

## EmergencyStop module

`Conveyor.EmergencyStop` (`lib/conveyor/emergency_stop.ex`) implements pure emergency-stop state transitions. It is deliberately a pure module: the state is a map, and every function returns a new map.

`engage/3` produces an engaged state map with `scope`, `scope_id`, `status: :engaged`, `actor`, `reason`, `trace_id`, and `engaged_at`. ADR-11 defines the blocked actions, encoded in a `MapSet`:

- `:run_attempt`
- `:planning_run`
- `:provider_call`
- `:tool_call`
- `:claim_publish`
- `:effect`
- `:budget_reservation`

`blocks?/2` returns true only when the state is engaged and the action is in the blocked set. This is the predicate the station wrapper and policy engine consult before allowing work.

`clear/2` transitions an engaged state to `:clear`, but only when a `human_decision_id` is provided. It raises `ArgumentError` if the human decision is missing. The cleared state records `cleared_by`, `human_decision_id`, and `cleared_at`. This means an engaged stop cannot be cleared by automation alone; a human must have made and recorded a decision.

`to_record/1` projects the in-memory state (with atoms) onto the `conveyor.emergency_stop_state@1` wire/persistence shape (with string enums and `project_id` for project scope). This separation keeps the pure logic ergonomic while the persisted record is schema-conformant.

## Shadow controls

`Conveyor.ShadowControls` (`lib/conveyor/shadow_controls.ex`) provides optional Tutor and retry-escalation shadow decisions. These are measurement and advisory surfaces. They do not close work, satisfy verification obligations, or consume escalation tiers for contract, policy, adapter, or infrastructure faults.

`tutor_advice/1` produces a `conveyor.tutor_shadow@1` record that is explicitly `advisory_only`, `can_close_slice: false`, `can_satisfy_obligation: false`, and `authority_effect: "none"`. The tutor may advise but never decide.

`retry_escalation/1` decides whether to escalate a retry to a higher agent profile. Only `implementation_failure` and `validation_failure` categories are retryable. If the current profile is at the top of the ladder (or unknown), it returns `route_without_escalation` with `consumes_tier: false` rather than claiming a tier-consuming escalation to a nonexistent profile. Otherwise it returns `new_attempt_with_next_profile` with `consumes_tier: true`.

The shadow controls are named "shadow" because they run alongside the real authority path without touching it. They exist to measure whether advice or escalation would have helped, not to exercise authority.

## Budget reservations

`Conveyor.BudgetReservations` (`lib/conveyor/budget_reservations.ex`) is the budget envelope and reservation helper. `envelope/1` creates an envelope with `token_limit`, `cost_limit`, `concurrency_limit`, and `active_reservations`. `reserve/3` checks the request against the envelope and returns `{:ok, reservation}` or `{:deny, reason}` for token, cost, or concurrency limits. `commit/2` transitions a reserved reservation to committed with actuals. `before_spend/1` is the gate: it returns `:ok` only for a `:reserved` reservation, denying nil (`reservation_required`) and committed (`reservation_consumed`) reservations.

Budget is a policy-controlled stop. The station wrapper's `validate_claim_controls!/1` rejects execution when `budget_status` is not `:reserved`. Budget exhaustion is not an ordinary agent failure; the run records consumed counters and moves the slice to `needs_rework`, `parked`, or `failed` according to policy. Non-progress exhaustion (repeated identical failures, no patch progress, output flooding) is also budget exhaustion.

## Key source files

| File | Purpose |
| --- | --- |
| `lib/conveyor/emergency_stop.ex` | Pure emergency-stop state transitions and blocked action set |
| `lib/conveyor/shadow_controls.ex` | Advisory tutor and retry-escalation shadow decisions |
| `lib/conveyor/budget_reservations.ex` | Budget envelope, reservation, commit, and before-spend gate |
| `lib/conveyor/station.ex` | Station wrapper checks emergency stop and budget before execution |
| `SAFETY_POLICY.md` | Budget exhaustion as a policy-controlled stop |

## Related pages

- [Station pipeline](station-pipeline.md) — where claim controls gate execution
- [Policy engine and command normalization](../systems/policy-engine.md) — policy enforcement layers
- [Architecture](../overview/architecture.md) — determinism boundary and control plane
- [Credential broker](credential-broker.md) — provider calls blocked by an engaged stop
