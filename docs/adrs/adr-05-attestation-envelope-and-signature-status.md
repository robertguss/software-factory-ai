# ADR-05: Attestation envelope and signature status

Status: Accepted

Date: 2026-06-19

Bead: `software-factory-ai-aamg.1.5`

Gated milestone: P15-A1

## Context

Conveyor needs portable, verifiable evidence statements for artifacts, gates, policies, grants, roots, and release bundles. A standard in-toto-shaped statement is useful even in local development, but using that shape must not imply stronger producer authentication or supply-chain assurance than the deployment profile actually provides.

The system needs a common attestation envelope and an explicit signature status ladder.

## Decision

Use an in-toto Statement envelope for authoritative evidence statements:

```json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{"name": "conveyor:subject/...", "digest": {"sha256": "..."}}],
  "predicateType": "https://conveyor.dev/attestations/<kind>/v1",
  "predicate": {}
}
```

Local-development operation may use unsigned in-toto Statements protected by local CAS, canonical digests, and the approval chain. Team-server, cross-host, release-grant, and portable-bundle profiles require a DSSE-wrapped in-toto Statement or an explicitly equivalent authenticated envelope.

Signature support is additive and represented by:

```text
signature_status in unsigned | locally_signed | externally_verified
verification_bundle_ref?
signer_identity?
```

Emitting an in-toto-shaped envelope does not imply supply-chain assurance beyond the recorded `signature_status`, verification bundle, signer identity, deployment profile, and policy decision.

## Consequences

Attestation subject digest mismatch is a hard failure. Consumers must evaluate both the statement shape and the signature status before granting authority. Unsigned statements can carry structured local claims, but portable or cross-host trust requires authenticated wrapping or an explicitly equivalent profile.

The signature ladder lets local development start without blocking on external signing infrastructure while preserving an upgrade path to stronger release and bundle profiles.

## Implementation Notes

P15-A1 implements the attestation envelope, local verification, subject digest checks, and signature-status fields alongside the schema registry and `DigestRef`.

Gates and offline verifiers must fail closed when an attestation predicate, subject digest, schema digest, canonicalization profile, or required signature status does not match the policy for the deployment profile.

`externally_verified` should be treated as a verification result backed by a bundle, not merely as the presence of a signature blob. `locally_signed` improves local attribution but does not automatically satisfy portable release policy.

## References

- docs/2_implementation_plans/PHASE-1.5-2-TRUST-QUALIFICATION-PLAN-COMPILER-CONTRACT-FOUNDRY-ULTIMATE-HYBRID.md, sections 1.3, 5.1 "Canonicalization and attestation", 18.1 P15-A1, 19, 24.11, and 28.2 item 5.
