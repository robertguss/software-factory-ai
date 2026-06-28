import { describe, expect, it } from "vitest"
import { VARIANTS, variantFor } from "@/lib/motion-grammar"

describe("variantFor", () => {
  // AE9: a state change selects its signature variant.
  it("settles on completion", () => {
    expect(variantFor("running", "done")).toBe("settle")
    expect(variantFor("running", "integrated")).toBe("settle")
  })

  it("fractures on failure", () => {
    expect(variantFor("running", "failed")).toBe("fracture")
  })

  it("fires when a waiting slice wakes into running", () => {
    expect(variantFor("blocked", "running")).toBe("fire")
    expect(variantFor("ready_idle", "running")).toBe("fire")
  })

  it("cools on stall", () => {
    expect(variantFor("running", "stalled")).toBe("cool")
  })

  it("pulses on any other state change", () => {
    expect(variantFor("ready_idle", "blocked")).toBe("pulse")
  })

  // AE9: unchanged state and reduced-motion both yield the no-op variant.
  it("is idle when the state did not change", () => {
    expect(variantFor("running", "running")).toBe("idle")
  })

  it("is idle under prefers-reduced-motion regardless of the change", () => {
    expect(variantFor("running", "failed", { reducedMotion: true })).toBe("idle")
  })

  it("handles the first-mount case (null prev) without throwing", () => {
    expect(variantFor(null, "running")).toBe("pulse")
  })

  it("only ever returns a defined variant key", () => {
    const pairs = [
      ["running", "done"],
      ["running", "failed"],
      ["blocked", "running"],
      ["running", "stalled"],
      ["ready_idle", "blocked"],
      [null, "running"],
    ]
    for (const [a, b] of pairs) {
      expect(VARIANTS).toHaveProperty(variantFor(a, b))
    }
  })
})
