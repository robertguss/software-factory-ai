// The dossier failure-fingerprint sparkline (R7/KTD7): a node's state-transition
// history, accumulated client-side from `node:patch` deltas and cleared on
// reconnect (a fresh `graph:init` reseeds the baseline). Session-scoped — it does
// NOT reach for the deferred event-history seek (#10). All pure.

/**
 * Append a state to a node's history, collapsing a consecutive repeat so the
 * fingerprint records transitions, not every tick. Returns the same array when
 * nothing changed (stable identity for memoization).
 * @param {string[]} history - oldest → newest.
 * @param {string} state
 * @returns {string[]}
 */
export function appendState(history, state) {
  if (history.length > 0 && history[history.length - 1] === state) return history
  return [...history, state]
}

/**
 * Seed one history entry per node from a `graph:init` snapshot — the session
 * baseline. Called on every (re)seed, so a reconnect clears prior accumulation.
 * @param {Array<{id: string, state: string}>} nodes
 * @returns {Object<string, string[]>}
 */
export function seedHistory(nodes) {
  return Object.fromEntries(nodes.map((n) => [n.id, [n.state]]))
}

/**
 * Fold a `node:patch` batch into the accumulated per-node history.
 * @param {Object<string, string[]>} history
 * @param {Array<{id: string, state: string}>} patched
 * @returns {Object<string, string[]>}
 */
export function accumulateHistory(history, patched) {
  const next = { ...history }
  for (const node of patched) {
    next[node.id] = appendState(next[node.id] ?? [], node.state)
  }
  return next
}
