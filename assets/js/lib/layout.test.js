import { describe, expect, it } from "vitest"
import { layoutGraph } from "@/lib/layout"

describe("layoutGraph", () => {
  it("assigns every node a numeric position", () => {
    const out = layoutGraph([{ id: "a" }, { id: "b" }], [{ from: "a", to: "b" }])
    for (const node of out) {
      expect(typeof node.position.x).toBe("number")
      expect(typeof node.position.y).toBe("number")
    }
  })

  it("lays a dependent to the right of its prerequisite (rankdir LR)", () => {
    // from → to means `b` depends on `a`, so `b` ranks after `a`.
    const [a, b] = layoutGraph([{ id: "a" }, { id: "b" }], [{ from: "a", to: "b" }])
    expect(b.position.x).toBeGreaterThan(a.position.x)
  })

  it("preserves node fields and does not mutate the inputs", () => {
    const nodes = [{ id: "a", state: "running", title: "A" }]
    const out = layoutGraph(nodes, [])
    expect(out[0].state).toBe("running")
    expect(out[0].title).toBe("A")
    expect(nodes[0].position).toBeUndefined()
  })
})
