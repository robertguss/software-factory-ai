import { describe, expect, it } from "vitest"
import { layoutPositions, toFlowEdges, toFlowNodes, topologyKey } from "@/lib/flow"

describe("toFlowEdges", () => {
  it("maps {from,to} to a slice edge with a stable id and living-graph data", () => {
    expect(toFlowEdges([{ from: "a", to: "b" }])).toEqual([
      { id: "a->b", source: "a", target: "b", type: "slice", data: { weight: 0, tension: false } },
    ])
  })

  it("weights an edge by the target's downstream waiting closure", () => {
    const nodes = [
      { id: "a", state: "running" },
      { id: "b", state: "blocked" },
    ]
    const [edge] = toFlowEdges([{ from: "a", to: "b" }], nodes)
    expect(edge.data.weight).toBeGreaterThan(0)
  })

  it("marks tension when the target's blocked_by includes the source", () => {
    const nodes = [
      { id: "a", state: "running" },
      { id: "b", state: "blocked", blocked_by: ["a"] },
    ]
    const [edge] = toFlowEdges([{ from: "a", to: "b" }], nodes)
    expect(edge.data.tension).toBe(true)
  })

  it("releases tension once the dependency is no longer in blocked_by", () => {
    const nodes = [
      { id: "a", state: "done" },
      { id: "b", state: "ready_idle", blocked_by: [] },
    ]
    const [edge] = toFlowEdges([{ from: "a", to: "b" }], nodes)
    expect(edge.data.tension).toBe(false)
  })

  it("remaps an edge into a folded member onto its epic chip", () => {
    const nodes = [
      { id: "ext", state: "running" },
      { id: "m", state: "done", epic_id: "E1" },
    ]
    const out = toFlowEdges([{ from: "ext", to: "m" }], nodes)
    expect(out).toHaveLength(1)
    expect(out[0]).toMatchObject({ source: "ext", target: "epic:E1", id: "ext->epic:E1" })
  })

  it("drops an edge wholly inside a folded epic", () => {
    const nodes = [
      { id: "a", state: "done", epic_id: "E1" },
      { id: "b", state: "done", epic_id: "E1" },
    ]
    expect(toFlowEdges([{ from: "a", to: "b" }], nodes)).toHaveLength(0)
  })

  it("dedupes edges that collapse onto the same chip endpoints", () => {
    const nodes = [
      { id: "ext", state: "running" },
      { id: "m1", state: "done", epic_id: "E1" },
      { id: "m2", state: "done", epic_id: "E1" },
    ]
    const out = toFlowEdges(
      [
        { from: "ext", to: "m1" },
        { from: "ext", to: "m2" },
      ],
      nodes,
    )
    expect(out).toHaveLength(1)
    expect(out[0].target).toBe("epic:E1")
  })
})

describe("toFlowNodes", () => {
  it("builds one slice node per graph node carrying the node as data", () => {
    const positions = new Map([["a", { x: 10, y: 20 }]])
    const out = toFlowNodes([{ id: "a", state: "running" }], positions)
    expect(out).toHaveLength(1)
    expect(out[0]).toMatchObject({ id: "a", type: "slice", position: { x: 10, y: 20 } })
    expect(out[0].data.state).toBe("running")
  })

  it("falls back to the origin for an unpositioned node", () => {
    const out = toFlowNodes([{ id: "a", state: "running" }], new Map())
    expect(out[0].position).toEqual({ x: 0, y: 0 })
  })

  it("dims a future-band node", () => {
    const out = toFlowNodes([{ id: "a", state: "blocked" }], new Map())
    expect(out[0].style).toEqual({ opacity: 0.45 })
    expect(out[0].data.band).toBe("future")
  })

  it("replaces a folded epic's members with one chip carrying the rollup", () => {
    const nodes = [
      { id: "a", state: "done", epic_id: "E1" },
      { id: "b", state: "failed", epic_id: "E1" },
    ]
    const out = toFlowNodes(nodes, new Map(), { epics: [{ id: "E1", label: "Build" }] })
    expect(out).toHaveLength(1)
    expect(out[0]).toMatchObject({ id: "epic:E1", type: "epicChip" })
    expect(out[0].data).toMatchObject({ label: "Build", total: 2, done: 1, failed: 1 })
  })

  it("keeps a pinned member visible alongside its epic chip (AE4)", () => {
    const nodes = [
      { id: "a", state: "done", epic_id: "E1" },
      { id: "b", state: "done", epic_id: "E1" },
    ]
    const out = toFlowNodes(nodes, new Map(), { pinned: new Set(["a"]) })
    const ids = out.map((n) => n.id).sort()
    expect(ids).toEqual(["a", "epic:E1"])
  })

  it("expands every epic (no chips) when zoomed in", () => {
    const nodes = [
      { id: "a", state: "done", epic_id: "E1" },
      { id: "b", state: "done", epic_id: "E1" },
    ]
    const out = toFlowNodes(nodes, new Map(), { expandAll: true })
    expect(out.map((n) => n.id).sort()).toEqual(["a", "b"])
  })
})

describe("layoutPositions", () => {
  it("returns a Map of id → numeric position", () => {
    const positions = layoutPositions([{ id: "a" }, { id: "b" }], [{ from: "a", to: "b" }])
    expect(positions.get("a")).toHaveProperty("x")
    expect(typeof positions.get("b").x).toBe("number")
  })
})

describe("topologyKey", () => {
  it("is stable across a data-only change but differs on a structural change", () => {
    const a = topologyKey([{ id: "a" }, { id: "b" }], [{ from: "a", to: "b" }])
    const sameTopo = topologyKey([{ id: "b" }, { id: "a" }], [{ from: "a", to: "b" }])
    const newNode = topologyKey([{ id: "a" }, { id: "b" }, { id: "c" }], [{ from: "a", to: "b" }])
    expect(a).toBe(sameTopo)
    expect(a).not.toBe(newNode)
  })
})
