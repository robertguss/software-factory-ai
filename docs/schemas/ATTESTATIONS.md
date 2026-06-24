# Attestation Envelope and Local Verification

Status: accepted

Date: 2026-06-19

## Envelope

P15-A1 wraps authoritative evidence in `conveyor.attestation_statement@1`, an
in-toto Statement shape:

```json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [
    { "name": "conveyor:subject/...", "digest": { "sha256": "..." } }
  ],
  "predicateType": "https://conveyor.dev/attestations/<kind>/v1",
  "predicate": {}
}
```

## Signature Status

| Status                | Meaning                                                                                             |
| --------------------- | --------------------------------------------------------------------------------------------------- |
| `unsigned`            | Local-development statement protected only by local CAS, approval chain, and subject digest checks. |
| `locally_signed`      | Signed by a configured local/team identity.                                                         |
| `externally_verified` | DSSE or equivalent portable verification bundle is available and policy-accepted.                   |

An in-toto-shaped envelope does not imply supply-chain assurance beyond its
`signature_status`.

## Local Verification

Local verification fails closed when:

- a subject digest does not match;
- the predicate schema version is unsupported;
- the attestation schema is invalid;
- the required `signature_status` is stronger than the envelope provides;
- a verification bundle or signer identity is required but absent.
