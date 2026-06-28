import { describe, expect, it } from "vitest"
import { downstreamWaitingCounts, weightScale, WAITING_STATES } from "@/lib/edge-weight"

// A chain a → b → c → d, with the waiting set tunable per test.
const chain = {
  nodes: [
    { id: "a", state: "done" },
    { id: "b", state: "running" },
    { id: "c", state: "blocked" },
    { id: "d", state: "ready_idle" },
  ],
  edges: [
    { from: "a", to: "b" },
    { from: "b", to: "c" },
    { from: "c", to: "d" },
  ],
}

describe("downstreamWaitingCounts", () => {
  // AE1: a source with more downstream waiting work outranks one with less.
  it("counts the inclusive downstream waiting closure per node", () => {
    const counts = downstreamWaitingCounts(chain.nodes, chain.edges)
    // a: {c,d} wait downstream → 2; b: {c,d} → 2; c: {c,d} (self blocked) → 2; d: {d} → 1
    expect(counts.get("a")).toBe(2)
    expect(counts.get("b")).toBe(2)
    expect(counts.get("c")).toBe(2)
    expect(counts.get("d")).toBe(1)
  })

  it("ranks a high-fanout waiting source above a low-fanout one", () => {
    const nodes = [
      { id: "hub", state: "running" },
      { id: "w1", state: "blocked" },
      { id: "w2", state: "blocked" },
      { id: "w3", state: "stalled" },
      { id: "lone", state: "running" },
      { id: "l1", state: "blocked" },
    ]
    const edges = [
      { from: "hub", to: "w1" },
      { from: "hub", to: "w2" },
      { from: "hub", to: "w3" },
      { from: "lone", to: "l1" },
    ]
    const counts = downstreamWaitingCounts(nodes, edges)
    expect(counts.get("hub")).toBeGreaterThan(counts.get("lone"))
    expect(counts.get("hub")).toBe(3)
    expect(counts.get("lone")).toBe(1)
  })

  it("does not double-count a waiter reachable by two paths (diamond)", () => {
    const nodes = [
      { id: "s", state: "running" },
      { id: "m1", state: "running" },
      { id: "m2", state: "running" },
      { id: "sink", state: "blocked" },
    ]
    const edges = [
      { from: "s", to: "m1" },
      { from: "s", to: "m2" },
      { from: "m1", to: "sink" },
      { from: "m2", to: "sink" },
    ]
    expect(downstreamWaitingCounts(nodes, edges).get("s")).toBe(1)
  })

  it("ignores non-waiting (done/failed/running/skipped/parked) states", () => {
    const nodes = [
      { id: "a", state: "running" },
      { id: "b", state: "done" },
      { id: "c", state: "failed" },
    ]
    const edges = [
      { from: "a", to: "b" },
      { from: "a", to: "c" },
    ]
    expect(downstreamWaitingCounts(nodes, edges).get("a")).toBe(0)
  })

  it("ignores starved_dependents entirely (weight is a graph walk, not the field)", () => {
    const nodes = [
      { id: "a", state: "running", starved_dependents: 99 },
      { id: "b", state: "done", starved_dependents: 99 },
    ]
    expect(downstreamWaitingCounts(nodes, edges_of(["a->b"])).get("a")).toBe(0)
  })

  it("terminates on a cycle rather than recursing forever", () => {
    const nodes = [
      { id: "a", state: "blocked" },
      { id: "b", state: "blocked" },
    ]
    const edges = [
      { from: "a", to: "b" },
      { from: "b", to: "a" },
    ]
    expect(() => downstreamWaitingCounts(nodes, edges)).not.toThrow()
  })

  it("exposes the waiting set as blocked/ready_idle/stalled", () => {
    expect([...WAITING_STATES].sort()).toEqual(["blocked", "ready_idle", "stalled"])
  })
})

describe("weightScale", () => {
  it("renders a zero-waiter edge at base (0)", () => {
    expect(weightScale(0)).toBe(0)
  })

  it("is proportional below the saturation cap", () => {
    expect(weightScale(2, 8)).toBeCloseTo(0.25)
    expect(weightScale(4, 8)).toBeCloseTo(0.5)
  })

  it("caps a very-high-waiter so it cannot dominate the canvas", () => {
    expect(weightScale(100, 8)).toBe(1)
    expect(weightScale(8, 8)).toBe(1)
  })
})

function edges_of(specs) {
  return specs.map((s) => {
    const [from, to] = s.split("->")
    return { from, to }
  })
}
