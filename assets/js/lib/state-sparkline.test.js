import { describe, expect, it } from "vitest"
import { accumulateHistory, appendState, seedHistory } from "@/lib/state-sparkline"

describe("appendState", () => {
  it("appends a changed state", () => {
    expect(appendState(["ready_idle"], "running")).toEqual(["ready_idle", "running"])
  })

  it("collapses a consecutive repeat (records transitions, not ticks)", () => {
    const history = ["running"]
    expect(appendState(history, "running")).toBe(history)
  })
})

describe("seedHistory", () => {
  it("builds one baseline entry per node", () => {
    expect(seedHistory([{ id: "a", state: "running" }, { id: "b", state: "blocked" }])).toEqual({
      a: ["running"],
      b: ["blocked"],
    })
  })
})

describe("accumulateHistory", () => {
  it("folds a node:patch batch onto the existing history", () => {
    const seeded = seedHistory([{ id: "a", state: "ready_idle" }])
    const next = accumulateHistory(seeded, [{ id: "a", state: "running" }])
    expect(next.a).toEqual(["ready_idle", "running"])
  })

  it("starts a fresh history for a node not seen at seed time", () => {
    expect(accumulateHistory({}, [{ id: "z", state: "failed" }])).toEqual({ z: ["failed"] })
  })

  it("a reconnect (reseed) clears prior accumulation", () => {
    let history = seedHistory([{ id: "a", state: "ready_idle" }])
    history = accumulateHistory(history, [{ id: "a", state: "running" }])
    expect(history.a).toHaveLength(2)

    // A fresh graph:init reseeds the baseline — old transitions are gone.
    history = seedHistory([{ id: "a", state: "running" }])
    expect(history.a).toEqual(["running"])
  })
})
