# Phase 1 Threat-Matrix Audit

Source: §12.0 of `PHASE-0-1-IMPLEMENTATION-PLAN.md`.

Executable audit: `Conveyor.ThreatMatrixAudit.audit/0`.

Test: `test/conveyor/threat_matrix_audit_test.exs`.

The audit maps all 11 threat classes to at least one Phase-1 test, canary, or doctor check:

- Malicious repository content
- Malicious tool output
- Agent policy evasion
- Test weakening
- Secret exposure
- Supply-chain drift
- Artifact tampering
- Reviewer rubber stamp
- Gate false negative
- Internal state corruption
- Host escape or overreach

The test fails if a threat has no coverage or if a referenced check file is missing.
