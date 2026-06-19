# Conveyor Schema Compatibility

This directory is the Phase 1 local schema registry for Conveyor public
artifacts. RunCheck and plan audit validate exact schema versions from this
registry; they do not best-effort parse unknown versions.

## Registry

| Schema version | File | Golden valid example | Golden invalid example |
| --- | --- | --- | --- |
| `conveyor.plan@1` | `conveyor.plan@1.json` | `examples/conveyor.plan.valid.json` | `examples/conveyor.plan.invalid.missing-schema-version.json` |
| `conveyor.run_spec@1` | `conveyor.run_spec@1.json` | `examples/conveyor.run_spec.valid.json` | `examples/conveyor.run_spec.invalid.missing-base-commit.json` |
| `conveyor.station_plan@1` | `conveyor.station_plan@1.json` | `examples/conveyor.station_plan.valid.json` | `examples/conveyor.station_plan.invalid.empty-stations.json` |
| `conveyor.evidence@1` | `conveyor.evidence@1.json` | `examples/evidence.valid.json` | `examples/evidence.invalid.missing-ac-evidence.json` |
| `conveyor.review@1` | `conveyor.review@1.json` | `examples/conveyor.review.valid.json` | `examples/conveyor.review.invalid.missing-reviewer.json` |
| `conveyor.gate@1` | `conveyor.gate@1.json` | `examples/conveyor.gate.valid.json` | `examples/conveyor.gate.invalid.missing-stages.json` |
| `conveyor.run_bundle@1` | `conveyor.run_bundle@1.json` | `examples/conveyor.run_bundle.valid.json` | `examples/conveyor.run_bundle.invalid.missing-bundle-root.json` |
| `conveyor.phase_next_decision@1` | `conveyor.phase_next_decision@1.json` | `examples/conveyor.phase_next_decision.valid.json` | `examples/conveyor.phase_next_decision.invalid.missing-selected-branches.json` |
| `conveyor.digest_ref@1` | `conveyor.digest_ref@1.json` | `examples/conveyor.digest_ref@1.valid.json` | `examples/conveyor.digest_ref@1.invalid.missing-schema-version.json` |
| `conveyor.resource_ref@1` | `conveyor.resource_ref@1.json` | `examples/conveyor.resource_ref@1.valid.json` | `examples/conveyor.resource_ref@1.invalid.missing-schema-version.json` |
| `conveyor.subject_ref@1` | `conveyor.subject_ref@1.json` | `examples/conveyor.subject_ref@1.valid.json` | `examples/conveyor.subject_ref@1.invalid.missing-schema-version.json` |
| `conveyor.schema_registry_entry@1` | `conveyor.schema_registry_entry@1.json` | `examples/conveyor.schema_registry_entry@1.valid.json` | `examples/conveyor.schema_registry_entry@1.invalid.missing-schema-version.json` |
| `conveyor.attestation_statement@1` | `conveyor.attestation_statement@1.json` | `examples/conveyor.attestation_statement@1.valid.json` | `examples/conveyor.attestation_statement@1.invalid.missing-schema-version.json` |
| `conveyor.lifecycle_contract@1` | `conveyor.lifecycle_contract@1.json` | `examples/conveyor.lifecycle_contract@1.valid.json` | `examples/conveyor.lifecycle_contract@1.invalid.missing-schema-version.json` |
| `conveyor.root_manifest@1` | `conveyor.root_manifest@1.json` | `examples/conveyor.root_manifest@1.valid.json` | `examples/conveyor.root_manifest@1.invalid.missing-schema-version.json` |
| `conveyor.policy_bundle@1` | `conveyor.policy_bundle@1.json` | `examples/conveyor.policy_bundle@1.valid.json` | `examples/conveyor.policy_bundle@1.invalid.missing-schema-version.json` |
| `conveyor.decision_contract@1` | `conveyor.decision_contract@1.json` | `examples/conveyor.decision_contract@1.valid.json` | `examples/conveyor.decision_contract@1.invalid.missing-schema-version.json` |
| `conveyor.policy_decision@1` | `conveyor.policy_decision@1.json` | `examples/conveyor.policy_decision@1.valid.json` | `examples/conveyor.policy_decision@1.invalid.missing-schema-version.json` |
| `conveyor.tool_contract@1` | `conveyor.tool_contract@1.json` | `examples/conveyor.tool_contract@1.valid.json` | `examples/conveyor.tool_contract@1.invalid.missing-schema-version.json` |
| `conveyor.role_view@1` | `conveyor.role_view@1.json` | `examples/conveyor.role_view@1.valid.json` | `examples/conveyor.role_view@1.invalid.missing-schema-version.json` |
| `conveyor.enforcement_profile@1` | `conveyor.enforcement_profile@1.json` | `examples/conveyor.enforcement_profile@1.valid.json` | `examples/conveyor.enforcement_profile@1.invalid.missing-schema-version.json` |
| `conveyor.observed_effect_summary@1` | `conveyor.observed_effect_summary@1.json` | `examples/conveyor.observed_effect_summary@1.valid.json` | `examples/conveyor.observed_effect_summary@1.invalid.missing-schema-version.json` |
| `conveyor.actor_identity@1` | `conveyor.actor_identity@1.json` | `examples/conveyor.actor_identity@1.valid.json` | `examples/conveyor.actor_identity@1.invalid.missing-schema-version.json` |
| `conveyor.actor_action@1` | `conveyor.actor_action@1.json` | `examples/conveyor.actor_action@1.valid.json` | `examples/conveyor.actor_action@1.invalid.missing-schema-version.json` |
| `conveyor.provider_contract@1` | `conveyor.provider_contract@1.json` | `examples/conveyor.provider_contract@1.valid.json` | `examples/conveyor.provider_contract@1.invalid.missing-schema-version.json` |
| `conveyor.provider_egress_record@1` | `conveyor.provider_egress_record@1.json` | `examples/conveyor.provider_egress_record@1.valid.json` | `examples/conveyor.provider_egress_record@1.invalid.missing-schema-version.json` |
| `conveyor.effect_attempt@1` | `conveyor.effect_attempt@1.json` | `examples/conveyor.effect_attempt@1.valid.json` | `examples/conveyor.effect_attempt@1.invalid.missing-schema-version.json` |
| `conveyor.effect_receipt@1` | `conveyor.effect_receipt@1.json` | `examples/conveyor.effect_receipt@1.valid.json` | `examples/conveyor.effect_receipt@1.invalid.missing-schema-version.json` |
| `conveyor.authority_event@1` | `conveyor.authority_event@1.json` | `examples/conveyor.authority_event@1.valid.json` | `examples/conveyor.authority_event@1.invalid.missing-schema-version.json` |
| `conveyor.observation_segment@1` | `conveyor.observation_segment@1.json` | `examples/conveyor.observation_segment@1.valid.json` | `examples/conveyor.observation_segment@1.invalid.missing-schema-version.json` |
| `conveyor.artifact_input@1` | `conveyor.artifact_input@1.json` | `examples/conveyor.artifact_input@1.valid.json` | `examples/conveyor.artifact_input@1.invalid.missing-schema-version.json` |
| `conveyor.artifact_address@1` | `conveyor.artifact_address@1.json` | `examples/conveyor.artifact_address@1.valid.json` | `examples/conveyor.artifact_address@1.invalid.missing-schema-version.json` |
| `conveyor.station_run_lease_ext@1` | `conveyor.station_run_lease_ext@1.json` | `examples/conveyor.station_run_lease_ext@1.valid.json` | `examples/conveyor.station_run_lease_ext@1.invalid.missing-schema-version.json` |
| `conveyor.dependency_resolution_manifest@1` | `conveyor.dependency_resolution_manifest@1.json` | `examples/conveyor.dependency_resolution_manifest@1.valid.json` | `examples/conveyor.dependency_resolution_manifest@1.invalid.missing-schema-version.json` |

## Compatibility Policy

- Artifact schemas are append-only within a major version.
- Removing a required field, changing a field's meaning, or changing a verdict
  enum requires a new major schema version.
- Adding optional fields to an existing major version is allowed only when old
  consumers can ignore them safely.
- Unknown schema versions fail with `unsupported_schema_version`.
- Missing required fields fail with `schema_validation_failed`.
- Known future minor versions fail in Phase 1 unless compatibility is explicitly
  declared here.
- Known older major versions fail unless an explicit migration exists.

## Canonical Validation Surface

Every schema file requires a `schema_version` field with an exact `const` value.
Every golden valid example must validate against its paired schema. Every golden
invalid example must fail against its paired schema for the reason named in the
filename.
