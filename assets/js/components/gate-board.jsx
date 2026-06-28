// The non-vacuous gate board (R8/AE6): one named-controller row per verification
// check, each reporting GO / NO-GO / STANDBY / Abstain with its evidence inline.
// There is deliberately NO single aggregate pass/fail checkmark — an opaque
// "gate passed" cannot be rendered; the board reflects the gate's own verdict
// vocabulary (including Abstain / baseline_absent) and never upgrades an
// uncomputed dimension to a pass. Display only — no approve/reject controls.
//
// Security: stage name/evidence are agent/gate-derived and render via JSX text
// interpolation only — never dangerouslySetInnerHTML.

const VERDICTS = {
  go: { label: "GO", token: "status-nominal" },
  no_go: { label: "NO-GO", token: "sev-warning" },
  abstain: { label: "Abstain", token: "sev-advisory" },
  standby: { label: "STANDBY", token: "muted" },
}

function verdictOf(raw) {
  const s = String(raw ?? "").toLowerCase()
  if (["passed", "pass", "go", "ok", "green"].includes(s)) return VERDICTS.go
  if (["failed", "fail", "no_go", "no-go", "blocked", "red", "rejected"].includes(s)) {
    return VERDICTS.no_go
  }
  if (["abstain", "abstained", "baseline_absent"].includes(s)) return VERDICTS.abstain
  // skipped / pending / parked / questions_required / unknown — not yet computed.
  return VERDICTS.standby
}

const stageStatus = (stage) => stage.status ?? stage.verdict ?? stage.result
const stageEvidence = (stage) => stage.evidence ?? stage.detail ?? stage.message ?? null
const stageName = (stage, i) =>
  stage.name ?? stage.label ?? stage.check ?? stage.id ?? `check ${i + 1}`

export default function GateBoard({ gate }) {
  if (!gate) {
    return (
      <p data-testid="gate-empty" className="text-xs text-muted">
        No gate verdict yet.
      </p>
    )
  }

  // A live gate carries per-check stages; a finished run carries one committed
  // status from its outcome payload. Either way: rows only, no aggregate check.
  const stages =
    gate.stages && gate.stages.length > 0
      ? gate.stages
      : gate.status
        ? [{ name: "committed verdict", status: gate.status }]
        : []

  return (
    <div role="table" aria-label="Gate board" className="flex flex-col gap-1 text-xs">
      {stages.length === 0 ? (
        <p className="text-muted">No checks reported.</p>
      ) : (
        stages.map((stage, i) => {
          const v = verdictOf(stageStatus(stage))
          const evidence = stageEvidence(stage)
          return (
            <div
              role="row"
              key={stageName(stage, i)}
              data-verdict={v.label}
              className="flex flex-col gap-0.5 rounded border border-border px-2 py-1"
            >
              <div className="flex items-center gap-2">
                <span className="truncate text-fg">{stageName(stage, i)}</span>
                <span
                  className="ml-auto font-semibold uppercase tracking-wide"
                  style={{ color: `var(--color-${v.token})` }}
                >
                  {v.label}
                </span>
              </div>
              {evidence && <p className="text-muted">{evidence}</p>}
            </div>
          )
        })
      )}
    </div>
  )
}
