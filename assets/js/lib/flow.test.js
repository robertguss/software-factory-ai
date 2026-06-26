import { describe, expect, it } from "vitest"
import { layoutPositions, toFlowEdges, toFlowNodes, topologyKey } from "@/lib/flow"

describe("toFlowEdges", () => {
  it("maps {from,to} to React Flow source/target with a stable id", () => {
    expect(toFlowEdges([{ from: "a", to: "b" }])).toEqual([
      { id: "a->b", source: "a", target: "b" },
    ])
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
