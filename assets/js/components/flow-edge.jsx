import { BaseEdge, getBezierPath } from "@xyflow/react"

// The living-graph dependency edge (R3). Weight (back-pressure) drives stroke
// width, brightness, and a proportional glow so the single worst bottleneck is
// identifiable from edge alone — no node selection. Tension (an unsatisfied
// `blocked_by`) renders as a dim dashed line that releases to a normal edge when
// the block clears. Flow animation is intentionally off by default: a healthy
// run is calm. Defined at module scope; registered in the `edgeTypes` map.
export default function FlowEdge({
  id,
  sourceX,
  sourceY,
  targetX,
  targetY,
  sourcePosition,
  targetPosition,
  data = {},
}) {
  const [path] = getBezierPath({
    sourceX,
    sourceY,
    targetX,
    targetY,
    sourcePosition,
    targetPosition,
  })

  const weight = data.weight ?? 0

  const style = data.tension
    ? {
        stroke: "var(--color-sev-caution)",
        strokeWidth: 1.5,
        strokeDasharray: "5 3",
        opacity: 0.55,
      }
    : {
        stroke: "var(--color-status-nominal)",
        strokeWidth: 1 + weight * 3,
        opacity: 0.3 + weight * 0.6,
        // The glow scales with weight so a heavy edge reads as bright on the
        // dark canvas; a zero-weight edge has no shadow and sits at base.
        filter: weight > 0 ? `drop-shadow(0 0 ${weight * 3}px var(--color-status-nominal))` : "none",
      }

  return <BaseEdge id={id} path={path} style={style} />
}
