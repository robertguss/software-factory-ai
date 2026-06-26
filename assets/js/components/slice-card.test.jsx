import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import SliceCard from "@/components/slice-card"

// The U7 wire shape (node_payload): the fields cockpit_live.ex already projects.
const node = (overrides = {}) => ({
  id: "n1",
  label: "n1",
  title: "Implement parser",
  state: "running",
  epic_id: null,
  blocked_by: [],
  starved_dependents: 0,
  ...overrides,
})

describe("SliceCard", () => {
  it("renders a failed node with the warning treatment and failed icon", () => {
    const { container } = render(<SliceCard node={node({ state: "failed" })} />)
    const card = container.querySelector("article")
    expect(card).toHaveAttribute("data-state", "failed")
    expect(card).toHaveAttribute("data-severity", "warning")
    expect(container.querySelector(".lucide-octagon-alert")).toBeInTheDocument()
  })

  it("renders a running node monochrome with no exception treatment", () => {
    const { container } = render(<SliceCard node={node({ state: "running" })} />)
    expect(container.querySelector("article")).toHaveAttribute("data-severity", "none")
  })

  it("shows the slice title", () => {
    render(<SliceCard node={node({ title: "Implement parser" })} />)
    expect(screen.getByText("Implement parser")).toBeInTheDocument()
  })

  it("shows starved_dependents when present", () => {
    render(<SliceCard node={node({ state: "blocked", starved_dependents: 3 })} />)
    expect(screen.getByTestId("starved-count")).toHaveTextContent("3")
  })

  it("omits the starvation count when zero", () => {
    render(<SliceCard node={node({ starved_dependents: 0 })} />)
    expect(screen.queryByTestId("starved-count")).not.toBeInTheDocument()
  })

  // Security: title/label are agent/repo-derived and must never reach the DOM as
  // raw HTML. A markup payload renders as escaped text, not an element.
  it("renders the title as text, never as raw HTML (XSS-safe)", () => {
    const { container } = render(
      <SliceCard node={node({ title: "<img src=x onerror=alert(1)>" })} />,
    )
    expect(container.querySelector("img")).toBeNull()
    expect(container.textContent).toContain("<img src=x onerror=alert(1)>")
  })
})
