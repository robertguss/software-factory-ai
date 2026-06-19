# Artifact projection

The artifact system in `lib/conveyor/artifacts/` handles how Conveyor stores, projects, and verifies run artifacts. Postgres remains the source of truth; disk is a read-only projection. Every run writes durable evidence under `.conveyor/runs/<run_attempt_id>/`, and the blob store provides content-addressed storage so artifact identity rests on SHA-256 digests, not file paths.

## ArtifactStore

`lib/conveyor/artifacts/artifact_store.ex` defines the artifact store backend contract. Backends implement seven callbacks: `new/1`, `put!/2`, `get!/2`, `head!/2`, `copy!/3`, `secure_delete!/2`, and `list_segments!/1`. The `assert_backend!/1` function validates that a module exports all required callbacks before it is used.

`lib/conveyor/artifacts/artifact_store/address.ex` defines the `Address` struct, which is trust-domain scoped. An address carries a trust domain id, content digest, optional ciphertext digest, opaque storage key, optional encryption key ref, and storage backend name. Trust domain isolation is enforced at the backend level: a backend for one trust domain refuses to resolve another domain's address.

### LocalCAS backend

`lib/conveyor/artifacts/artifact_store/local_cas.ex` is the local content-addressed `ArtifactStore` backend. It stores blobs under `<root>/<trust_domain_id>/sha256/<prefix>/<digest>` and verifies content digests on every read. The `copy!/3` operation re-addresses content under a new trust domain. `list_segments!/1` enumerates all stored addresses for the backend's trust domain.

## BlobStore

`lib/conveyor/artifacts/blob_store.ex` is the local content-addressed blob storage for artifact bytes. The canonical on-disk layout is `.conveyor/blobs/sha256/<prefix>/<digest>`, where the prefix is the first two hex characters of the digest. Blob refs are relative paths under the blob root, so they can be persisted in database rows without trusting projection paths as identity.

Key operations:

- **`write!/2`** — computes the SHA-256, derives the ref, creates the directory, and writes the content. Returns a `Blob` struct with ref, sha256, and size.
- **`read!/2`** — reads the blob and verifies the content hash matches the digest encoded in the ref. Raises on mismatch.
- **`verify!/4`** — reads, verifies both digest and size against expected values, and returns a `Blob` with content.
- **`path_for!/2`** — resolves a blob ref to an absolute path under the blob root, with escape prevention.
- **`sha256/1`** — computes the lowercase hex SHA-256 of content, used throughout Conveyor for content addressing.

Refs are normalized to `sha256/<2-char-prefix>/<64-hex-digest>` form. The module validates that the prefix matches the first two characters of the digest, preventing ref forgery.

## Projector

`lib/conveyor/artifacts/projector.ex` is the behaviour and facade for regenerating run artifact projections. It is a supervised conductor child that delegates to a configurable backend (defaulting to `LocalDisk`). The `project_run!/2` function takes a `RunAttempt` and opts, resolves the backend, and delegates.

The `Result` struct carries the run attempt id, projection path, artifact count, manifest SHA-256, and bundle root SHA-256.

### LocalDisk projector

`lib/conveyor/artifacts/projector/local_disk.ex` is the local-disk projector backend. For a given run attempt it:

1. Loads all `Artifact` records for the run attempt, sorted by projection path.
2. Filters out restricted-sensitivity artifacts (sensitive, quarantined).
3. Verifies each artifact's blob against its recorded SHA-256 and size using `BlobStore.verify!/4`.
4. Builds projection items from verified artifacts plus synthesized items (manifest, PR body, retrospective).
5. Computes manifest entries and a bundle root SHA-256 over the entry set.
6. Builds a `conveyor.run_bundle@1` manifest with schema version, entries, and bundle root digest.
7. Writes the projection tree to `.conveyor/runs/<run_attempt_id>/`.
8. Upserts a `RunBundle` record with the manifest and bundle root digests.

The manifest entry kinds include evidence, review, gate, manifest, PR body, provenance, log, diff, and retrospective. The bundle root SHA-256 is computed over canonical JSON of the entry set (path, kind, sha256, size, sensitivity, schema_version), providing a tamper-evident digest of the entire projection.

## Key source files

| File | Purpose |
| ---- | ---- |
| `lib/conveyor/artifacts/artifact_store.ex` | Artifact store backend contract with `assert_backend!/1`. |
| `lib/conveyor/artifacts/artifact_store/address.ex` | Trust-domain scoped artifact address struct. |
| `lib/conveyor/artifacts/artifact_store/local_cas.ex` | Local content-addressed ArtifactStore backend. |
| `lib/conveyor/artifacts/blob_store.ex` | Local content-addressed blob storage with SHA-256 verification. |
| `lib/conveyor/artifacts/projector.ex` | Projector behaviour and facade with configurable backend. |
| `lib/conveyor/artifacts/projector/local_disk.ex` | Local-disk projector backend for read-only run artifact trees. |

## Related pages

- [Evidence recording](evidence-recording.md) — how evidence is captured and written as artifacts
- [Gate](gate.md) — `run_check` stage validates artifact schemas and digests
- [Architecture](../overview/architecture.md) — artifact surface and projection topology
- [Evidence](../primitives/evidence.md) — evidence resource model
