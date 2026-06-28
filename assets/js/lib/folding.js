// Frontier + epic folding (R4). A large run stays legible because the execution
// frontier renders at full fidelity, the completed past folds into collapsed
// epic chips, and the foreshadowed future is dimmed. All pure — the canvas wires
// these classifications into React Flow nodes/edges.

// The execution frontier: where work is actively at the edge.
export const FRONTIER_STATES = new Set(["running", "ready_idle"])

// Terminal / completed states — the foldable past.
const PAST_STATES = new Set(["done", "skipped", "failed"])

/**
 * The visual band for a slice (R4 dimming): frontier (full fidelity), past
 * (foldable), or future (dimmed — blocked/parked/stalled, foreshadowed work not
 * yet at the edge).
 * @param {string} state
 * @returns {"frontier" | "past" | "future"}
 */
export function band(state) {
  if (FRONTIER_STATES.has(state)) return "frontier"
  if (PAST_STATES.has(state)) return "past"
  return "future"
}

/**
 * Per-epic rollup keyed by epic id. `done` counts done+skipped; `failed` is
 * counted separately for the "done / total · failed" chip. An epic is `foldable`
 * when it has at least one member and none of them are on the frontier.
 * @param {Array<{id: string, state: string, epic_id?: ?string}>} nodes
 * @returns {Map<string, {id: string, total: number, done: number, failed: number, hasFrontier: boolean, foldable: boolean}>}
 */
export function epicRollups(nodes) {
  const byEpic = new Map()
  for (const n of nodes) {
    if (n.epic_id == null) continue
    let r = byEpic.get(n.epic_id)
    if (!r) {
      r = { id: n.epic_id, total: 0, done: 0, failed: 0, hasFrontier: false }
      byEpic.set(n.epic_id, r)
    }
    r.total += 1
    if (n.state === "done" || n.state === "skipped") r.done += 1
    if (n.state === "failed") r.failed += 1
    if (FRONTIER_STATES.has(n.state)) r.hasFrontier = true
  }
  for (const r of byEpic.values()) r.foldable = r.total > 0 && !r.hasFrontier
  return byEpic
}

/**
 * The set of epic ids that fold to a chip — foldable epics. Pins do NOT keep an
 * epic expanded; they keep the individual node visible (see visibleNodeIds).
 * @returns {Set<string>}
 */
export function foldableEpicIds(nodes) {
  return new Set(
    [...epicRollups(nodes).values()].filter((r) => r.foldable).map((r) => r.id),
  )
}

/**
 * Node ids that render as individual slice nodes. A member of a folded epic is
 * hidden (represented by its chip) unless it is pinned (AE4) or the canvas is
 * zoomed in (`expandAll` → semantic zoom expands every epic, no mode switch).
 * @param {Array} nodes
 * @param {{ pinned?: Set<string>, expandAll?: boolean }} [opts]
 * @returns {Set<string>}
 */
export function visibleNodeIds(nodes, { pinned = new Set(), expandAll = false } = {}) {
  const folded = expandAll ? new Set() : foldableEpicIds(nodes)
  return new Set(
    nodes
      .filter((n) => n.epic_id == null || !folded.has(n.epic_id) || pinned.has(n.id))
      .map((n) => n.id),
  )
}
