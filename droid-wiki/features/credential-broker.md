# Credential broker

Credentials are the most dangerous input an agent can touch. Conveyor issues
short-lived, scoped credential leases through a broker that never persists
secret values. Raw provider secrets are not injected into worker containers
unless no safer adapter mode exists, and even then only as named environment
keys allowed by policy.

## CredentialBroker

`Conveyor.CredentialBroker` (`lib/conveyor/credential_broker.ex`) issues and
revokes credential leases. It is deliberately small: four public functions and
one result struct.

`issue!/3` creates a `CredentialLease` for a given `RunSpec` and provider. It
takes an `env` map of string keys and values, a sorted `env_keys` list, and an
optional `allowed_env_keys` list. It validates that every requested key is in
the allowed set, raising on any denied key. The lease gets an `issued_at`, a
`expires_at` (default TTL 900 seconds), a `scope` defaulting to `run_spec:<id>`,
and `status: :active`. It returns an `IssuedLease` struct carrying the lease
record and the env map restricted to the requested keys.

The broker never writes secret values to the database. The `CredentialLease` row
records which env keys were exposed, to which run spec and station run, when
they expire, and their status. The actual secret values live only in the
in-memory `IssuedLease.env` map passed to the runner.

## CredentialLease resource

`Conveyor.Factory.CredentialLease` (`lib/conveyor/factory/credential_lease.ex`)
is the Ash resource tracking each exposure. Its attributes:

- `provider` — the credential provider name
- `env_keys` — the environment keys exposed by this lease
- `scope` — the scope string, typically `run_spec:<id>`
- `issued_at`, `expires_at`, `revoked_at` — timestamps
- `status` — `:issued`, `:active`, `:revoked`, `:expired`, or `:invalidated`

It belongs to a `RunSpec` (required) and optionally to a `StationRun`. The
optional station run link lets the broker revoke leases for a single station
without revoking the whole run spec's leases.

## Scoped leases

Leases are scoped to a run spec by default and optionally narrowed to a station
run. The scope string makes it easy to audit which execution context a
credential was exposed to. The `env_keys` list makes it possible to prove that
only the allowlisted keys were exposed, even though the secret values themselves
are not persisted.

The broker validates env keys against a policy allowlist before creating the
lease. `validate_env_keys!/2` raises with the denied key names if any requested
key is not in the allowed set. This is defense in depth on top of the policy
profile's environment variable rules.

## Revocation

The broker offers three revocation paths:

- `revoke!/2` — revokes a single lease, setting `revoked_at` and
  `status: :revoked` (or a caller-specified status).
- `revoke_for_run_spec!/2` — revokes all `:issued` or `:active` leases for a run
  spec. Used on cancellation or run completion.
- `revoke_for_station_run!/2` — revokes all `:issued` or `:active` leases for a
  station run. Used when a station fails or is retried.

`expire_stale!/1` revokes any `:issued` or `:active` lease whose `expires_at`
has passed, marking them `:expired`. This is the safety net for leases that were
never explicitly revoked, such as when a worker crashed without running cleanup.

Revocation is idempotent in effect: already-revoked leases are filtered out by
the status check before `revoke!/2` is called, so repeated revocation calls do
not produce duplicate state changes.

## Key source files

| File                                       | Purpose                                                                |
| ------------------------------------------ | ---------------------------------------------------------------------- |
| `lib/conveyor/credential_broker.ex`        | Issues and revokes scoped credential leases without persisting secrets |
| `lib/conveyor/factory/credential_lease.ex` | Short-lived scoped provider credential exposure record                 |
| `SAFETY_POLICY.md`                         | Credential and image policy, broker requirements                       |

## Related pages

- [Sandbox isolation](sandbox-isolation.md) — where credential env keys are
  injected into containers
- [Policy engine and command normalization](../systems/policy-engine.md) —
  environment variable policy
- [Agent runner and Pi adapter](../systems/agent-runner.md) — where provider
  credentials are consumed
- [Architecture](../overview/architecture.md) — credential broker in the safety
  boundary
