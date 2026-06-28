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

  it("defaults to the nano scale", () => {
    const { container } = render(<SliceCard node={node()} />)
    expect(container.querySelector("article")).toHaveAttribute("data-scale", "nano")
  })

  // AE8: one primitive, three scales — the same node applies the same color-law
  // treatment (severity + icon) at every scale; only the fields shown differ.
  it("applies the same severity and icon across nano, compact, and full scales", () => {
    const n = node({ state: "failed", starved_dependents: 2 })
    const scales = ["nano", "compact", "full"]
    const results = scales.map((scale) => {
      const { container } = render(<SliceCard node={n} scale={scale} />)
      const article = container.querySelector("article")
      return {
        scale: article.getAttribute("data-scale"),
        severity: article.getAttribute("data-severity"),
        hasFailedIcon: !!container.querySelector(".lucide-octagon-alert"),
      }
    })
    expect(results.map((r) => r.scale)).toEqual(scales)
    expect(results.every((r) => r.severity === "warning")).toBe(true)
    expect(results.every((r) => r.hasFailedIcon)).toBe(true)
  })

  it("shows the state and epic on the compact scale", () => {
    render(<SliceCard node={node({ state: "running", epic_id: "build" })} scale="compact" />)
    const meta = screen.getByTestId("compact-meta")
    expect(meta).toHaveTextContent("running")
    expect(meta).toHaveTextContent("build")
  })

  it("shows the blocked-by and starved field block on the full scale", () => {
    render(<SliceCard node={node({ state: "blocked", blocked_by: ["a", "b"], starved_dependents: 4 })} scale="full" />)
    expect(screen.getByText("blocked by")).toBeInTheDocument()
    expect(screen.getByText("2")).toBeInTheDocument()
    expect(screen.getByText("starved")).toBeInTheDocument()
  })
})
