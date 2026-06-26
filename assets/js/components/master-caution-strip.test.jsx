import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import MasterCautionStrip from "@/components/master-caution-strip"

describe("MasterCautionStrip", () => {
  it("renders nothing when the run is calm", () => {
    const { container } = render(
      <MasterCautionStrip nodes={[{ id: "a", state: "running" }]} />,
    )
    expect(container).toBeEmptyDOMElement()
  })

  it("pins the failed slice over a high-starvation blocked slice (AE3)", () => {
    render(
      <MasterCautionStrip
        nodes={[
          { id: "b", state: "blocked", starved_dependents: 5, title: "Blocked one" },
          { id: "c", state: "failed", title: "Failed one" },
        ]}
      />,
    )
    const strip = screen.getByRole("status")
    expect(strip).toHaveAttribute("data-severity", "warning")
    expect(strip).toHaveTextContent("Failed one")
  })

  it("calls onJump with the pinned node id", () => {
    const onJump = vi.fn()
    render(
      <MasterCautionStrip nodes={[{ id: "c", state: "failed", title: "Failed one" }]} onJump={onJump} />,
    )
    fireEvent.click(screen.getByRole("button", { name: "Jump" }))
    expect(onJump).toHaveBeenCalledWith("c")
  })
})
