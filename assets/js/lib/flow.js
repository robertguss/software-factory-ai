import { layoutGraph } from "@/lib/layout"
import { downstreamWaitingCounts, weightScale } from "@/lib/edge-weight"
import { band, epicRollups, foldableEpicIds } from "@/lib/folding"

// React Flow edges from the server's {from, to} edges. `from → to` means
// "to depends on from", which is also the drawn arrow direction. Each edge
// carries the living-graph data the custom `slice` edge renders (R3):
//   - weight: [0,1] back-pressure — how much live downstream work waits behind
//     the target, from a client-side walk of `edges` + node `state` (never
//     `starved_dependents`).
//   - tension: the target lists the source in `blocked_by` (an unsatisfied
//     dependency), drawn as dim tension that releases when the block clears.
// `opts.counts` is accepted pre-computed so the canvas can memoize it across
// renders; when omitted it is derived here so the function stays usable
// standalone. With folding active (R4), an edge touching a hidden member is
// remapped to that member's epic chip; an edge wholly inside a folded epic
// collapses (source === target) and is dropped, and duplicates are deduped.
export function toFlowEdges(edges, nodes = [], opts = {}) {
  const {
    counts = downstreamWaitingCounts(nodes, edges),
    pinned = new Set(),
    expandAll = false,
  } = opts
  const blockedBy = new Map(nodes.map((n) => [n.id, n.blocked_by ?? []]))
  const chipOf = hiddenMemberChips(nodes, pinned, expandAll)
  const resolve = (id) => chipOf.get(id) ?? id

  const seen = new Set()
  const out = []
  for (const edge of edges) {
    const source = resolve(edge.from)
    const target = resolve(edge.to)
    if (source === target) continue // intra-epic edge folds into the chip
    const id = `${source}->${target}`
    if (seen.has(id)) continue
    seen.add(id)
    out.push({
      id,
      source,
      target,
      type: "slice",
      data: {
        // weight/tension keep their original-endpoint meaning even when remapped.
        weight: weightScale(counts.get(edge.to) ?? 0),
        tension: (blockedBy.get(edge.to) ?? []).includes(edge.from),
      },
    })
  }
  return out
}

// Map a hidden folded-epic member id → its `epic:<id>` chip id. Pinned members
// and the zoomed-in (expandAll) case stay visible, so they are not mapped.
function hiddenMemberChips(nodes, pinned, expandAll) {
  const folded = expandAll ? new Set() : foldableEpicIds(nodes)
  const chipOf = new Map()
  for (const n of nodes) {
    if (n.epic_id != null && folded.has(n.epic_id) && !pinned.has(n.id)) {
      chipOf.set(n.id, `epic:${n.epic_id}`)
    }
  }
  return chipOf
}

function centroid(members, positions) {
  const pts = members.map((m) => positions.get(m.id)).filter(Boolean)
  if (!pts.length) return { x: 0, y: 0 }
  const x = pts.reduce((sum, p) => sum + p.x, 0) / pts.length
  const y = pts.reduce((sum, p) => sum + p.y, 0) / pts.length
  return { x, y }
}

// React Flow nodes for the canvas, positioned from `positions` (a Map id→{x,y});
// unpositioned nodes fall back to the origin. Each visible graph node becomes a
// `slice` node carrying the graph node + its `band` (R4) as `data`; future-band
// nodes get a dimmed style. A folded epic's members are replaced by one
// `epicChip` node at the members' centroid carrying the rollup. Pins and the
// zoomed-in (expandAll) case keep members visible.
export function toFlowNodes(nodes, positions, opts = {}) {
  const { pinned = new Set(), expandAll = false, epics = [] } = opts
  const folded = expandAll ? new Set() : foldableEpicIds(nodes)
  const rollups = epicRollups(nodes)
  const epicLabel = new Map(epics.map((e) => [e.id, e.label]))

  const out = []
  for (const node of nodes) {
    const hidden = node.epic_id != null && folded.has(node.epic_id) && !pinned.has(node.id)
    if (hidden) continue
    const b = band(node.state)
    const rfNode = {
      id: node.id,
      type: "slice",
      position: positions.get(node.id) ?? { x: 0, y: 0 },
      data: { ...node, band: b },
    }
    if (b === "future") rfNode.style = { opacity: 0.45 }
    out.push(rfNode)
  }

  for (const epicId of folded) {
    const members = nodes.filter((n) => n.epic_id === epicId)
    out.push({
      id: `epic:${epicId}`,
      type: "epicChip",
      position: centroid(members, positions),
      data: { ...rollups.get(epicId), label: epicLabel.get(epicId) ?? epicId },
    })
  }

  return out
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
