import { layoutGraph } from "@/lib/layout"
import { downstreamWaitingCounts, weightScale } from "@/lib/edge-weight"

// React Flow edges from the server's {from, to} edges. `from → to` means
// "to depends on from", which is also the drawn arrow direction. Each edge
// carries the living-graph data the custom `slice` edge renders (R3):
//   - weight: [0,1] back-pressure — how much live downstream work waits behind
//     the target, from a client-side walk of `edges` + node `state` (never
//     `starved_dependents`).
//   - tension: the target lists the source in `blocked_by` (an unsatisfied
//     dependency), drawn as dim tension that releases when the block clears.
// `counts` is accepted pre-computed so the canvas can memoize it across renders;
// when omitted it is derived here so the function stays usable standalone.
export function toFlowEdges(edges, nodes = [], counts = downstreamWaitingCounts(nodes, edges)) {
  const blockedBy = new Map(nodes.map((n) => [n.id, n.blocked_by ?? []]))
  return edges.map((edge) => ({
    id: `${edge.from}->${edge.to}`,
    source: edge.from,
    target: edge.to,
    type: "slice",
    data: {
      weight: weightScale(counts.get(edge.to) ?? 0),
      tension: (blockedBy.get(edge.to) ?? []).includes(edge.from),
    },
  }))
}

// One "slice" React Flow node per graph node, positioned from `positions` (a Map
// id→{x,y}); unpositioned nodes fall back to the origin. The whole graph node is
// carried as `data` so the SliceNode renders it through the color law.
export function toFlowNodes(nodes, positions) {
  return nodes.map((node) => ({
    id: node.id,
    type: "slice",
    position: positions.get(node.id) ?? { x: 0, y: 0 },
    data: node,
  }))
}

// Lay a topology out with dagre into a Map id→{x,y}. Recomputed only when the
// topology changes (seed / structural change), never on a data-only patch.
export function layoutPositions(nodes, edges) {
  return new Map(layoutGraph(nodes, edges).map((node) => [node.id, node.position]))
}

// A stable key over the graph's *shape* (node ids + edges), so the page can tell
// a topology change (relayout) from a data-only patch (keep positions).
export function topologyKey(nodes, edges) {
  const ids = nodes.map((n) => n.id).sort().join(",")
  const links = edges.map((e) => `${e.from}->${e.to}`).sort().join(",")
  return `${ids}|${links}`
}
