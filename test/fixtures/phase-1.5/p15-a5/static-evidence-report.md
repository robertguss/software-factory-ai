# P15-A5 Static Evidence Report

Beads:

- software-factory-ai-aamg.2.6.1
- software-factory-ai-aamg.2.6.2
- software-factory-ai-aamg.2.6.3

## Kernel Adoption

The Phase-1 tracer is routed through the evidence-kernel contracts without
changing Phase-1 behavior. The dogfood route records adoption for policy
decisions, tool contracts, role views, station fencing, effect receipts,
authority events, artifact stores, emergency stop, budget reservations, and
retention.

## Surfaced Gaps

- Full database-backed verification still depends on local PostgreSQL test
  credentials.
- Several Phase-1 flows keep their existing persistence shape; P15-A5 records
  kernel-compatible envelopes and helpers without rewriting historical rows.

## Migration Notes

- Schema registry entries now cover the evidence-kernel resources used by the
  tracer.
- Runtime helpers expose no-DB contracts for fencing, receipts, event segments,
  artifact backends, control-plane stop/budget/health decisions, and canaries.
- Future DB migrations can backfill historical tracer artifacts by mapping
  existing station, artifact, and ledger rows to the route in
  `tracer-kernel-route.json`.
