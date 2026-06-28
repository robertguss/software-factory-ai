// The motion grammar (R2): one variants object keyed by the state change a
// node:patch produced, plus a pure selector. Sub-300ms ease-out; only the
// element that changed animates (the caller animates on a real state change,
// never on every render). The grammar is plain data — no `motion` import — so
// it is consumable by any surface: graph nodes, list rows, badges, toasts.

export const TRANSITION = { duration: 0.18, ease: "easeOut" }

// Variant name → animation keyframes. `idle` is the no-op, used for unchanged
// state and for prefers-reduced-motion. Each signature is deliberately small so
// the grammar stays calm rather than noisy.
export const VARIANTS = {
  idle: {},
  settle: { scale: [1, 0.96, 1] }, // a completing slice settles
  fire: { opacity: [0.4, 1], scale: [0.96, 1] }, // an unblocked slice wakes
  fracture: { x: [0, -3, 3, -2, 2, 0] }, // a failure fractures
  cool: { opacity: [1, 0.6] }, // a stalled slice cools / desaturates
  pulse: { scale: [1, 1.03, 1] }, // any other state change
}

// States a slice "wakes" from when it starts running.
const WAKE_FROM = new Set(["blocked", "ready_idle", "stalled"])

/**
 * Select the motion variant for a state transition. Pure and total.
 * @param {?string} prev - the prior state (null on first mount).
 * @param {string} next - the new state.
 * @param {{ reducedMotion?: boolean }} [opts]
 * @returns {keyof typeof VARIANTS}
 */
export function variantFor(prev, next, { reducedMotion = false } = {}) {
  if (reducedMotion) return "idle"
  if (prev === next) return "idle"
  if (next === "failed") return "fracture"
  if (next === "done" || next === "integrated") return "settle"
  if (next === "running" && WAKE_FROM.has(prev)) return "fire"
  if (next === "stalled") return "cool"
  return "pulse"
}
