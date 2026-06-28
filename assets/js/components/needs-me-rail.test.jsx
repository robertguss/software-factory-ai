import { fireEvent, render, screen, within } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import NeedsMeRail from "@/components/needs-me-rail"

const item = (overrides = {}) => ({
  slice_id: "s1",
  title: "Slice One",
  label: "SLICE-001",
  state: "failed",
  kind: "failed",
  outcome: null,
  rank: 40,
  ...overrides,
})

describe("NeedsMeRail", () => {
  it("shows a visible 'all clear' marker when there is nothing to do (never hidden)", () => {
    render(<NeedsMeRail items={[]} />)
    expect(screen.getByTestId("all-clear")).toBeInTheDocument()
    expect(screen.getByLabelText("Needs me")).toBeInTheDocument()
  })

  it("lists items highest-attention first (server rank, byAttention tie-break)", () => {
    render(
      <NeedsMeRail
        items={[
          item({ slice_id: "low", title: "Low", state: "running", kind: "gate_waiting", outcome: "abstained", rank: 10 }),
          item({ slice_id: "high", title: "High", state: "failed", kind: "failed", rank: 40 }),
        ]}
      />,
    )
    const labels = screen.getAllByText(/High|Low/).map((n) => n.textContent)
    expect(labels[0]).toBe("High")
  })

  it("renders a gate-waiting verdict as its reason label", () => {
    render(
      <NeedsMeRail
        items={[item({ kind: "gate_waiting", outcome: "needs_rework", state: "running" })]}
      />,
    )
    expect(screen.getByText("needs rework")).toBeInTheDocument()
  })

  it("navigates on select and pushes no mutation (AE5)", () => {
    const onSelect = vi.fn()
    render(<NeedsMeRail items={[item()]} onSelect={onSelect} />)

    fireEvent.click(screen.getByRole("button"))
    expect(onSelect).toHaveBeenCalledWith(expect.objectContaining({ slice_id: "s1" }))
  })

  it("renders each item as a SliceCard carrying the slice's color-law treatment", () => {
    const { container } = render(<NeedsMeRail items={[item({ state: "failed" })]} />)
    const card = within(container).getByRole("listitem").querySelector("article")
    expect(card).toHaveAttribute("data-state", "failed")
    expect(card).toHaveAttribute("data-severity", "warning")
    expect(card).toHaveAttribute("data-scale", "compact")
  })
})
