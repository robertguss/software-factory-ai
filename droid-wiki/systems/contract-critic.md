# Contract critic

The contract critic in `lib/conveyor/contract_critic/` challenges and repairs drafted contracts. It is the adversarial counterpart to the contract forge: where the forge drafts, the critic attacks. Critic lenses may challenge contracts and preserve disagreement, but they never approve, lock, or grant implementation authority. The critic projects cheapest-wrong attacks, records independence profiles, runs multi-lens reviews, compares repair diffs, and drives a bounded repair loop.

## CheapestWrong

`lib/conveyor/contract_critic/cheapest_wrong.ex` projects cheapest-wrong implementation attacks into `ContractChallengeCase` records. Each attack describes a case where the written contract is satisfied but the approved intent is violated. The `challenge!/1` function takes a contract id, evidence refs, and a list of attacks, then builds challenge cases with schema version `conveyor.contract_challenge_case@1`, a rule key (`contract_critic.cheapest_wrong.<attack_key>`), the written-contract-satisfied-by description, the approved-intent-violated description, evidence refs, materiality classification (`nonmaterial`, `review_only`, `material`, `breaking`), and a repair proposal. Each case is content-addressed.

## IndependenceProfile

`lib/conveyor/contract_critic/independence_profile.ex` records and enforces independence profiles for challenge roles. Four profiles are supported: `logical`, `context_separated`, `model_diverse`, and `human_or_deterministic`. The `record!/1` function builds a profile record with schema version `conveyor.independence_profile@1`, challenge role, profile, and evidence refs, content-addressed.

The `enforce!/1` function checks that high-risk change classes (`security`, `irreversible_migration`, `public_compat`, `autonomy_increasing`) have at least one strong profile (`model_diverse` or `human_or_deterministic`). If not, it returns a blocking `critic.independence_insufficient` finding.

## Lenses

`lib/conveyor/contract_critic/lenses.ex` is the pure multi-lens Contract Critic projection. Ten required lenses are evaluated:

1. **`intent_fidelity`** — does the contract match approved intent?
2. **`scope_delta`** — does the contract change scope?
3. **`principal_engineering`** — is the contract sound engineering?
4. **`interface_compatibility`** — are interfaces compatible?
5. **`test_loopholes`** — can tests be gamed?
6. **`reliability_observability`** — is the result observable and reliable?
7. **`security`** — are there security gaps?
8. **`cost_simplification`** — is the contract unnecessarily complex or costly?
9. **`hidden_decision`** — are there hidden decisions?
10. **`approval_cognitive_load`** — is approval too complex?

The `review/1` function runs all lenses, collects disagreements (when lens statuses diverge), and computes an overall status of `:passed` or `:challenged`. The result explicitly declares `can_approve?: false` and `can_lock?: false` to enforce that the critic never grants authority.

## RepairDiff

`lib/conveyor/contract_critic/repair_diff.ex` is the typed repair comparison with partial pass-output reuse. The `compare/1` function checks that the repair only changed rejected artifacts (the changed artifact refs must be a subset of the rejected artifact refs). If scope expanded beyond rejected artifacts, it returns a blocking `repair.scope_expanded` finding. On success, it builds a `conveyor.repair_diff@1` with before and after digests, comparison type (materiality), authority effect, changed artifact refs, reused pass outputs, and invalidated passes. The diff is content-addressed.

## RepairLoop

`lib/conveyor/contract_critic/repair_loop.ex` is the bounded automatic repair policy for Contract Critic findings. The `next_action/1` function returns `:repair` if completed rounds are below the max (default 2), otherwise `:park`. The `evaluate/1` function detects oscillation (repeated artifact digests) and non-progress (finding counts not decreasing) and parks the repair in those cases. The `route_change/1` function classifies a change: repair is allowed for normal changes, an amendment is required for material or breaking changes in amendment classes (plan, constraint, interface, acceptance), and an error is returned if repair would weaken policy or acceptance without normal authority.

## Key source files

| File | Purpose |
| ---- | ---- |
| `lib/conveyor/contract_critic/cheapest_wrong.ex` | Projects cheapest-wrong attacks into ContractChallengeCase records. |
| `lib/conveyor/contract_critic/independence_profile.ex` | Records and enforces independence profiles for challenge roles. |
| `lib/conveyor/contract_critic/lenses.ex` | Pure multi-lens Contract Critic projection with 10 required lenses. |
| `lib/conveyor/contract_critic/repair_diff.ex` | Typed repair comparison with partial pass-output reuse. |
| `lib/conveyor/contract_critic/repair_loop.ex` | Bounded automatic repair policy with oscillation and non-progress detection. |

## Related pages

- [Contract forge](contract-forge.md) — drafting contracts from plan requirements
- [Planning compiler](planning-compiler.md) — materiality policy and amendment enforcement
- [Contract management](../features/contract-management.md) — contract lock lifecycle
- [Contract lock](../primitives/contract-lock.md) — contract lock primitive
