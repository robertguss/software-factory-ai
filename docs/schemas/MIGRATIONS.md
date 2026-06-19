# Artifact Schema Migration Framework

Status: accepted

Date: 2026-06-19

## Compatibility Classes

| Class | Meaning |
| --- | --- |
| `additive` | Adds optional fields or enum values that old consumers can ignore safely. |
| `backward_compatible` | Changes reader behavior without changing existing field meanings. |
| `breaking` | Removes required fields, changes field meaning, tightens authority, or changes required evidence semantics. |

Unknown enum values fail closed for authority-bearing decisions unless the
reader explicitly declares forward-compatible handling for that vocabulary.

## Migration Shape

Every migration keeps original artifact bytes and emits new lineage:

1. Validate old artifact against its registered schema or fail explicitly.
2. Produce a migrated artifact with a new schema version.
3. Emit a deterministic semantic-equivalence report.
4. Record `migration_from` in the target `SchemaRegistryEntry`.
5. Preserve both old and new artifact `DigestRef` values.

Migrations never rewrite originals in place. A migrated artifact can become
authoritative only through the same policy, evidence, and root checks as a new
artifact.
