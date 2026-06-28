import { describe, expect, it } from "vitest"
import {
  band,
  epicRollups,
  foldableEpicIds,
  visibleNodeIds,
  FRONTIER_STATES,
} from "@/lib/folding"

describe("band", () => {
  it("classifies the frontier, the past, and the future", () => {
    expect(band("running")).toBe("frontier")
    expect(band("ready_idle")).toBe("frontier")
    expect(band("done")).toBe("past")
    expect(band("skipped")).toBe("past")
    expect(band("failed")).toBe("past")
    expect(band("blocked")).toBe("future")
    expect(band("parked")).toBe("future")
    expect(band("stalled")).toBe("future")
  })

  it("treats running and ready_idle as the frontier set", () => {
    expect([...FRONTIER_STATES].sort()).toEqual(["ready_idle", "running"])
  })
})

describe("epicRollups", () => {
  it("rolls up done/total and failed per epic", () => {
    const nodes = [
      { id: "1", state: "done", epic_id: "E1" },
      { id: "2", state: "skipped", epic_id: "E1" },
      { id: "3", state: "failed", epic_id: "E1" },
      { id: "4", state: "blocked", epic_id: "E1" },
    ]
    const r = epicRollups(nodes).get("E1")
    expect(r).toMatchObject({ id: "E1", total: 4, done: 2, failed: 1 })
  })

  it("marks an epic foldable only when it has no frontier member", () => {
    const past = epicRollups([
      { id: "1", state: "done", epic_id: "E1" },
      { id: "2", state: "blocked", epic_id: "E1" },
    ]).get("E1")
    expect(past.foldable).toBe(true)

    const active = epicRollups([
      { id: "1", state: "done", epic_id: "E2" },
      { id: "2", state: "running", epic_id: "E2" },
    ]).get("E2")
    expect(active.foldable).toBe(false)
  })

  it("ignores nodes with no epic_id", () => {
    expect(epicRollups([{ id: "1", state: "done" }]).size).toBe(0)
  })
})

describe("foldableEpicIds", () => {
  it("is empty for an all-frontier run", () => {
    const nodes = [
      { id: "1", state: "running", epic_id: "E1" },
      { id: "2", state: "ready_idle", epic_id: "E1" },
    ]
    expect(foldableEpicIds(nodes).size).toBe(0)
  })

  it("folds every epic in an all-done run", () => {
    const nodes = [
      { id: "1", state: "done", epic_id: "E1" },
      { id: "2", state: "done", epic_id: "E2" },
    ]
    expect([...foldableEpicIds(nodes)].sort()).toEqual(["E1", "E2"])
  })

  it("folds only the completed epics in a mixed run", () => {
    const nodes = [
      { id: "1", state: "done", epic_id: "E1" },
      { id: "2", state: "running", epic_id: "E2" },
      { id: "3", state: "blocked", epic_id: "E2" },
    ]
    expect([...foldableEpicIds(nodes)]).toEqual(["E1"])
  })
})

describe("visibleNodeIds", () => {
  const nodes = [
    { id: "a", state: "done", epic_id: "E1" },
    { id: "b", state: "done", epic_id: "E1" },
    { id: "c", state: "running", epic_id: "E2" },
    { id: "loose", state: "blocked" },
  ]

  it("hides the members of a folded epic but keeps active + loose nodes", () => {
    const visible = visibleNodeIds(nodes)
    expect(visible.has("a")).toBe(false)
    expect(visible.has("b")).toBe(false)
    expect(visible.has("c")).toBe(true)
    expect(visible.has("loose")).toBe(true)
  })

  it("keeps a pinned node visible even inside a folded epic (AE4)", () => {
    const visible = visibleNodeIds(nodes, { pinned: new Set(["a"]) })
    expect(visible.has("a")).toBe(true)
    expect(visible.has("b")).toBe(false)
  })

  it("shows everything when zoomed in (expandAll → semantic zoom)", () => {
    const visible = visibleNodeIds(nodes, { expandAll: true })
    expect(visible.has("a")).toBe(true)
    expect(visible.has("b")).toBe(true)
  })
})
