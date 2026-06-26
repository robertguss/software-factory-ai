import dagre from "@dagrejs/dagre"

// Card footprint used for layout spacing; the visual SliceCard is nano-scale.
const NODE_WIDTH = 180
const NODE_HEIGHT = 44

/**
 * Position graph nodes with dagre. `rankdir: "LR"` mirrors the look of the
 * retired elk `layered`/`RIGHT` layout. Pure — returns new node objects with a
 * React-Flow `position` (top-left origin; dagre centers, so we offset by half).
 *
 * @param {Array<{id: string}>} nodes
 * @param {Array<{from: string, to: string}>} edges
 * @param {{ rankdir?: string }} [opts]
 * @returns {Array<object>} nodes with `position: {x, y}`
 */
export function layoutGraph(nodes, edges, { rankdir = "LR" } = {}) {
  const g = new dagre.graphlib.Graph()
  g.setGraph({ rankdir, nodesep: 24, ranksep: 72 })
  g.setDefaultEdgeLabel(() => ({}))

  nodes.forEach((node) => g.setNode(node.id, { width: NODE_WIDTH, height: NODE_HEIGHT }))
  edges.forEach((edge) => g.setEdge(edge.from, edge.to))

  dagre.layout(g)

  return nodes.map((node) => {
    const { x, y } = g.node(node.id)
    return { ...node, position: { x: x - NODE_WIDTH / 2, y: y - NODE_HEIGHT / 2 } }
  })
}
