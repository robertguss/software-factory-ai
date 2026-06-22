# P2-B4 Acceptance Gate

Status: passed locally with DB-free focused tests.

Scope: prompt budget/context assembly, final prompt dry-compile, layered
authority/review/archive roots, canonical attestations, deterministic Factory
Chronicle, and the static PlanningBundle schema.

## Exit Criteria

### critical-context drop fails before the provider

Evidence:

- `Conveyor.Planning.ContextAssemblyManifest` assembles authority context first,
  records budget and shed decisions, and blocks before any provider call when
  critical content would be dropped.
- `PlanningContextAssemblyTest` proves critical PlanRevision, policy,
  interface, and obligation context cannot be shed silently, while advisory
  context is shed with reasons under budget pressure.
- `Conveyor.Planning.PromptDryCompile` keeps `provider_called?: false` and
  `implementer_launched?: false` on blocked prompt inputs.
- `PlanningPromptDryCompileTest` proves final dry-compile validates all required
  contract, policy, interface, obligation, test, RoleView, output-schema,
  budget, and shed inputs without launching an implementer.

### a review-only change does not alter authority roots

Evidence:

- `Conveyor.Planning.LayeredRoots` builds separate domain-separated
  `RootManifest`s for shared authority, Epic authority, review, and archive
  bundle roots.
- `PlanningLayeredRootsTest` proves changing only the review projection changes
  the review and archive roots while leaving shared and Epic authority roots
  stable.

### a semantic/waiver/policy change alters the correct roots

Evidence:

- `Conveyor.Planning.LayeredRoots` sorts canonical entries and hashes each root
  with its root-kind domain prefix, so authority bytes are isolated from review
  bytes.
- `PlanningLayeredRootsTest` proves changing a shared policy digest changes the
  shared authority root and archive root without changing the Epic authority or
  review roots.

### the approval record is not included in the signed root

Evidence:

- `Conveyor.Planning.LayeredRoots` rejects `approval_record` entries from root
  leaves and records the excluded approval record ref separately.
- `PlanningLayeredRootsTest` proves approval records are absent from signed root
  manifests and that `conveyor.root_manifest@1` validation still passes for the
  shared, Epic, review, and archive root manifests.

### the summary cannot hide a blocker

Evidence:

- `Conveyor.Planning.FactoryChronicle` derives approval status from structured
  canonical blockers, not from source prose.
- `PlanningFactoryChronicleTest` proves `factory_chronicle.md` includes the
  limitations banner, exposes `BLOCK-POLICY-1`, keeps
  `summary_canary: canonical_blockers_visible`, and never renders
  `Status: passed` while canonical blockers exist.

### UI/static/CLI derive the same bundle

Evidence:

- `Conveyor.Planning.RootAttestations` emits a canonical
  `conveyor.attestation_statement@1` in-toto statement over the shared,
  Epic, review, archive, and supporting evidence subjects.
- `PlanningRootAttestationsTest` proves statement subjects are sorted, schema
  valid, and digest-stable across equivalent evidence ordering.
- `conveyor.planning_bundle@1` defines the static approval bundle resource with
  `planning_run_id`, `plan_revision_id`, `constraint_set_digest`,
  `qualification_grant_id`, `manifest_ref`, `manifest_digest`,
  `shared_authority_root_digest`, `epic_authority_root_digests`,
  `review_root_digest`, `archive_bundle_root_digest`, `projection_path`,
  `status`, and `approval_signature_excluded: true`.
- `PlanningBundleSchemaTest` proves the PlanningBundle schema validates the
  golden example, rejects a bundle that omits the approval-signature exclusion,
  and is registered as current P2-B4 schema.

## Release Report

| Evidence source | Failed cases represented | Excluded cases |
| --- | --- | --- |
| `PlanningContextAssemblyTest` | critical context shed before provider, advisory shed without recorded reason | none |
| `PlanningPromptDryCompileTest` | unauthorized prompt artifacts, instruction hierarchy conflicts, autonomy over-grant | none |
| `PlanningLayeredRootsTest` | review bytes mutating authority roots, policy bytes not mutating shared authority root, approval record in signed root | none |
| `PlanningRootAttestationsTest` | unstable attestation digest, invalid in-toto statement shape, missing root/evidence subject | none |
| `PlanningFactoryChronicleTest` | canonical blocker hidden by summary prose, missing limitations banner | none |
| `PlanningBundleSchemaTest` | bundle missing root digests, manifest refs, projection status, or approval-signature exclusion | none |

## Verification Commands

- `MIX_ENV=test mix run --no-start -e 'ExUnit.start(); ...; ExUnit.run()'`
  against the focused P2-B4 test files.
- `MIX_ENV=test mix compile --warnings-as-errors`
- `mix format ... --check-formatted`
- `jq empty` for the PlanningBundle schema and examples.
- `git diff --check`

Full DB-backed `mix test` remains blocked in this local environment by the
PostgreSQL/Ecto test repo configuration.
