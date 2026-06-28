import { render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"

// EpicChip is a React Flow custom node; stub the handles so it renders without a
// React Flow provider (mirrors how SliceNode's handles are exercised).
vi.mock("@xyflow/react", () => ({
  Handle: () => null,
  Position: { Left: "left", Right: "right" },
}))

import EpicChip from "@/components/epic-chip"

describe("EpicChip", () => {
  it("shows the epic label and the done/total rollup", () => {
    render(<EpicChip data={{ label: "Build", total: 5, done: 4, failed: 0 }} />)
    expect(screen.getByText("Build")).toBeInTheDocument()
    expect(screen.getByText("4/5")).toBeInTheDocument()
  })

  it("surfaces a failure count in the rollup and tints the chip", () => {
    render(<EpicChip data={{ label: "Build", total: 5, done: 3, failed: 2 }} />)
    expect(screen.getByText("3/5 · 2 failed")).toBeInTheDocument()
    expect(screen.getByTestId("epic-chip")).toHaveAttribute("data-failed", "2")
  })
})
