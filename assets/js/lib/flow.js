import { layoutGraph } from "@/lib/layout"

// React Flow edges from the server's {from, to} edges. `from → to` means
// "to depends on from", which is also the drawn arrow direction.
export function toFlowEdges(edges) {
  return edges.map((edge) => ({
    id: `${edge.from}->${edge.to}`,
    source: edge.from,
    target: edge.to,
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
