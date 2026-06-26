import { Ban, Circle, CircleCheck, Clock, OctagonAlert, Pause, Play, SkipForward } from "lucide-react"

// The dark-cockpit color law (R8/R10): map a slice's projection state to a
// severity, a semantic token, and a colorblind-safe icon. Pure and total over
// the 8-state GraphProjection taxonomy. Token values are role names matching the
// CSS variables in app.css (`--color-<token>`), so a consumer resolves a token
// as `var(--color-${token})`.

// Single named escalation point: a blocked slice only becomes a colored caution
// once it starves at least this many dependents. Below it, blocking is routine
// graph scheduling and stays monochrome. Tunable knob, not a magic number.
export const HIGH_STARVATION_THRESHOLD = 1

// The monochrome token shared by every nominal state — a calm run reads as one
// flat color (AE2).
export const NOMINAL_TOKEN = "status-nominal"

// Exception severities, ranked so the single top exception can be selected for
// the master-caution strip (R9/AE3). Higher rank wins.
export const SEVERITY = {
  warning: { rank: 3, token: "sev-warning" },
  caution: { rank: 2, token: "sev-caution" },
  advisory: { rank: 1, token: "sev-advisory" },
}

// One distinct icon per state so state is legible without color (R10/AE5). The
// icon is keyed on state alone — a blocked slice keeps its icon whether or not
// it has escalated to caution; only the token/severity shift.
const ICONS = {
  running: Play,
  ready_idle: Circle,
  done: CircleCheck,
  skipped: SkipForward,
  parked: Pause,
  failed: OctagonAlert,
  blocked: Ban,
  stalled: Clock,
}

// Resolve the severity for a state. Nominal states return null. `blocked` only
// escalates when it starves enough dependents.
function severityFor(state, starved_dependents) {
  switch (state) {
    case "failed":
      return "warning"
    case "stalled":
      return "advisory"
    case "blocked":
      return starved_dependents >= HIGH_STARVATION_THRESHOLD ? "caution" : null
    default:
      return null
  }
}

/**
 * @param {string} state - one of the 8 GraphProjection states.
 * @param {{ starved_dependents?: number }} [node] - the slice's projection
 *   fields; `starved_dependents` is the non-negative count from the projection.
 * @returns {{ state: string, severity: ?string, token: string, rank: number, icon: Function }}
 */
export function colorLaw(state, { starved_dependents = 0 } = {}) {
  const icon = ICONS[state]
  if (!icon) {
    throw new Error(`color-law: unknown state "${state}"`)
  }

  const severity = severityFor(state, starved_dependents)
  const token = severity ? SEVERITY[severity].token : NOMINAL_TOKEN
  const rank = severity ? SEVERITY[severity].rank : 0

  return { state, severity, token, rank, icon }
}

/**
 * The single highest-ranked exception across a node list, or null if the run is
 * calm. Powers the master-caution strip (R9). On a rank tie the first node wins
 * (stable input order).
 * @returns {?{ node: object, severity: string, token: string, rank: number, icon: Function }}
 */
export function topException(nodes) {
  return nodes.reduce((top, node) => {
    const law = colorLaw(node.state, node)
    if (law.rank === 0) return top
    if (!top || law.rank > top.rank) return { node, ...law }
    return top
  }, null)
}

/**
 * Overall run health: the max severity present across all nodes (null → calm).
 * Drives the ambient viewport border (R9), sharing the color-law ranking.
 * @returns {?string}
 */
export function overallSeverity(nodes) {
  const top = topException(nodes)
  return top ? top.severity : null
}
