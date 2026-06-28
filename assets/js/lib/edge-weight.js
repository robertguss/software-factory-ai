// Edge weight (R3): how much *live downstream work* waits behind a node, derived
// client-side by walking the wired `edges` + per-node `state`. This is an
// aggregation of server-emitted states, not client re-derivation of state — the
// server-computed-state invariant holds. It deliberately does NOT read
// `starved_dependents`, which the server populates only on `:skipped` nodes as a
// skip blast-radius, not live back-pressure.

// The states that count as a live downstream waiter. `running` is active (not
// waiting); `done`/`failed`/`skipped`/`parked` are terminal or out of play.
export const WAITING_STATES = new Set(["blocked", "ready_idle", "stalled"])

/**
 * For every node, the count of distinct waiting nodes in its inclusive downstream
 * closure (itself, if waiting, plus all transitive descendants in a waiting
 * state). The edge `from → to` carries the pressure of `to`'s closure.
 *
 * @param {Array<{id: string, state: string}>} nodes
 * @param {Array<{from: string, to: string}>} edges
 * @param {Set<string>} [waiting] - the waiting-state set (override for testing).
 * @returns {Map<string, number>} nodeId → distinct downstream waiter count.
 */
export function downstreamWaitingCounts(nodes, edges, waiting = WAITING_STATES) {
  const stateById = new Map(nodes.map((n) => [n.id, n.state]))
  const children = new Map(nodes.map((n) => [n.id, []]))
  for (const e of edges) {
    if (children.has(e.from)) children.get(e.from).push(e.to)
  }

  const memo = new Map() // id → Set<waiting node ids in inclusive closure>
  const onStack = new Set() // cycle guard (work graphs are DAGs, but be safe)

  function closure(id) {
    const cached = memo.get(id)
    if (cached) return cached
    if (onStack.has(id)) return new Set() // ponytail: cycle → stop, DAG so won't matter
    onStack.add(id)
    const set = new Set()
    if (waiting.has(stateById.get(id))) set.add(id)
    for (const child of children.get(id) ?? []) {
      for (const w of closure(child)) set.add(w)
    }
    onStack.delete(id)
    memo.set(id, set)
    return set
  }

  return new Map(nodes.map((n) => [n.id, closure(n.id).size]))
}

// Saturation point for the stroke scale: a node with this many downstream waiters
// already renders at full weight, so a single huge-fanout bottleneck cannot dwarf
// every other edge. Tunable knob, not a magic number.
export const WEIGHT_SATURATION = 8

/**
 * Map a raw waiter count to a [0, 1] stroke scale. Zero waiters → 0 (base
 * weight); proportional up to the saturation cap; clamped to 1 beyond it.
 * @param {number} raw
 * @param {number} [saturation]
 * @returns {number}
 */
export function weightScale(raw, saturation = WEIGHT_SATURATION) {
  if (raw <= 0) return 0
  return Math.min(1, raw / saturation)
}
