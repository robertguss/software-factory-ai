# Canonical JSON and DigestRef Profile

Status: accepted

Date: 2026-06-19

## Canonicalization Profile

Conveyor P15-A1 uses `rfc8785-jcs` as the canonical JSON profile unless a later
ADR supersedes it. Authority-bearing artifacts must be valid I-JSON and avoid
ambiguous primitive encodings.

## Safe Encodings

| Concept | Encoding |
| --- | --- |
| Money | Integer minor units plus currency code. |
| Large integers outside safe I-JSON range | Decimal strings. |
| Timestamps | Normalized RFC3339 strings. |
| Durations | Integer milliseconds or nanoseconds with an explicit unit. |
| Unordered sets | Deterministically sorted arrays. |
| Content digests | `DigestRef{algorithm,value}` instead of bare `*_sha256`. |

Legacy `*_sha256` fields are migration aliases only. New schemas use `*_digest`
and reference `conveyor.digest_ref@1`.

## Domain-Separated Roots

Authority-root manifests hash a domain-separated prefix plus canonical manifest
bytes:

```text
hash("conveyor:<root-kind>:v<version>\\0" || canonical_root_manifest_bytes)
```

The prefix prevents shared-authority, review, archive, and evidence roots from
being confused even when they contain similar entries.
