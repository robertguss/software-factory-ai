import { describe, expect, it } from "vitest"
import {
  colorLaw,
  HIGH_STARVATION_THRESHOLD,
  NOMINAL_TOKEN,
  SEVERITY,
} from "@/lib/color-law"

const NOMINAL_STATES = ["running", "ready_idle", "done", "skipped", "parked"]
const ALL_STATES = [...NOMINAL_STATES, "failed", "blocked", "stalled"]

describe("colorLaw", () => {
  // AE2 — a nominal run is calm: every nominal state is monochrome with no
  // exception severity.
  describe("nominal states (AE2)", () => {
    it.each(NOMINAL_STATES)("%s maps to the monochrome token and no severity", (state) => {
      const law = colorLaw(state)
      expect(law.token).toBe(NOMINAL_TOKEN)
      expect(law.severity).toBeNull()
      expect(law.rank).toBe(0)
    })
  })

  // AE3 — severity ranking surfaces the top exception:
  // failed (warning) > blocked-caution > stalled (advisory).
  describe("exception severity ranking (AE3)", () => {
    it("ranks failed > blocked(high-starvation) > stalled", () => {
      const failed = colorLaw("failed")
      const blocked = colorLaw("blocked", { starved_dependents: HIGH_STARVATION_THRESHOLD })
      const stalled = colorLaw("stalled")

      expect(failed.severity).toBe("warning")
      expect(blocked.severity).toBe("caution")
      expect(stalled.severity).toBe("advisory")

      expect(failed.rank).toBeGreaterThan(blocked.rank)
      expect(blocked.rank).toBeGreaterThan(stalled.rank)
      expect(stalled.rank).toBeGreaterThan(0)
    })

    it("each exception severity carries its own token", () => {
      expect(colorLaw("failed").token).toBe(SEVERITY.warning.token)
      expect(colorLaw("blocked", { starved_dependents: HIGH_STARVATION_THRESHOLD }).token).toBe(
        SEVERITY.caution.token,
      )
      expect(colorLaw("stalled").token).toBe(SEVERITY.advisory.token)
    })
  })

  // The blocked-starvation threshold: only a blocked slice that starves enough
  // dependents escalates to a colored caution; below it, blocking is routine.
  describe("blocked starvation threshold", () => {
    it("escalates to caution at/above the threshold", () => {
      const law = colorLaw("blocked", { starved_dependents: HIGH_STARVATION_THRESHOLD })
      expect(law.severity).toBe("caution")
      expect(law.token).toBe(SEVERITY.caution.token)
    })

    it("stays non-exception below the threshold", () => {
      const law = colorLaw("blocked", { starved_dependents: HIGH_STARVATION_THRESHOLD - 1 })
      expect(law.severity).toBeNull()
      expect(law.token).toBe(NOMINAL_TOKEN)
      expect(law.rank).toBe(0)
    })

    it("treats a missing starvation count as zero (non-exception)", () => {
      expect(colorLaw("blocked").severity).toBeNull()
    })
  })

  // AE5 — state survives color blindness: every state resolves to a distinct
  // icon so encoding never relies on color alone.
  describe("colorblind-safe icons (AE5)", () => {
    it("gives every state a truthy icon", () => {
      for (const state of ALL_STATES) {
        expect(colorLaw(state).icon).toBeTruthy()
      }
    })

    it("gives every state a distinct icon", () => {
      const icons = ALL_STATES.map((s) => colorLaw(s).icon)
      expect(new Set(icons).size).toBe(ALL_STATES.length)
    })
  })

  // Coverage: the mapping is total over the 8-state taxonomy and rejects the
  // unknown rather than silently mis-rendering.
  describe("totality", () => {
    it("covers all 8 states without throwing", () => {
      for (const state of ALL_STATES) {
        expect(() => colorLaw(state)).not.toThrow()
      }
    })

    it("throws on an unknown state", () => {
      expect(() => colorLaw("nope")).toThrow()
    })
  })
})
