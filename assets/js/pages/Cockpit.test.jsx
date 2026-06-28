import { fireEvent, render, screen, within } from "@testing-library/react"
import { beforeEach, describe, expect, it, vi } from "vitest"

// Shared spies/state the mocks read, set per test.
const h = vi.hoisted(() => ({ setCenter: vi.fn(), hook: null }))

// A lightweight React Flow: render each node through its registered nodeTypes
// component, so the real SliceNode → SliceCard renders and render-parity is
// assertable without the canvas (which needs a real layout engine + DOM box).
vi.mock("@xyflow/react", () => ({
  ReactFlow: ({ nodes, nodeTypes }) =>
    nodes.map((node) => {
      const Comp = nodeTypes[node.type]
      return <Comp key={node.id} id={node.id} data={node.data} />
    }),
  ReactFlowProvider: ({ children }) => children,
  Background: () => null,
  Controls: () => null,
  Handle: () => null,
  Position: { Left: "left", Right: "right" },
  useReactFlow: () => ({ setCenter: h.setCenter }),
}))

vi.mock("@/hooks/use-cockpit-channel", () => ({
  useCockpitChannel: () => h.hook,
}))

import Cockpit from "@/pages/Cockpit"

const hook = (overrides = {}) => ({
  status: "live",
  graph: { nodes: [], edges: [], epics: [] },
  runs: [],
  attention: { items: [], runs: [] },
  seeded: true,
  requestDetail: vi.fn(),
  ...overrides,
})

beforeEach(() => {
  h.setCenter = vi.fn()
  h.hook = hook()
})

describe("Cockpit", () => {
  it("shows the loading state before the first graph:init — not the empty state", () => {
    h.hook = hook({ seeded: false, status: "connecting" })
    render(<Cockpit plan_id="p1" />)
    expect(screen.getByText("Loading run…")).toBeInTheDocument()
    expect(screen.queryByText("No plan to display yet")).not.toBeInTheDocument()
  })

  it("shows the empty state only on a zero-node seed", () => {
    h.hook = hook({ seeded: true, graph: { nodes: [], edges: [], epics: [] } })
    render(<Cockpit plan_id="p1" />)
    expect(screen.getByText("No plan to display yet")).toBeInTheDocument()
  })

  it("render parity: one SliceCard per node with the expected per-state treatment", () => {
    h.hook = hook({
      graph: {
        nodes: [
          { id: "a", state: "running", title: "Slice A" },
          { id: "b", state: "failed", title: "Slice B" },
        ],
        edges: [{ from: "a", to: "b" }],
        epics: [],
      },
    })
    const { container } = render(<Cockpit plan_id="p1" />)

    const cards = container.querySelectorAll("article")
    expect(cards).toHaveLength(2)
    expect(container.querySelector('article[data-state="failed"]')).toHaveAttribute(
      "data-severity",
      "warning",
    )
    expect(container.querySelector('article[data-state="running"]')).toHaveAttribute(
      "data-severity",
      "none",
    )
  })

  it("pins the top exception in the caution strip and centers the viewport on jump (AE3)", () => {
    h.hook = hook({
      graph: {
        nodes: [
          { id: "a", state: "running", title: "Slice A" },
          { id: "b", state: "failed", title: "Slice B" },
        ],
        edges: [{ from: "a", to: "b" }],
        epics: [],
      },
    })
    render(<Cockpit plan_id="p1" />)

    // The strip pins the failed slice (rendered as both a card and the strip
    // entry); its jump centers the viewport on the node.
    expect(screen.getAllByText("Slice B").length).toBeGreaterThanOrEqual(1)
    fireEvent.click(screen.getByRole("button", { name: "Jump" }))
    expect(h.setCenter).toHaveBeenCalled()
  })

  it("toggles a node's pin through the canvas (R4)", () => {
    h.hook = hook({
      graph: {
        nodes: [{ id: "a", state: "running", title: "Slice A" }],
        edges: [],
        epics: [],
      },
    })
    render(<Cockpit plan_id="p1" />)

    const pin = screen.getByRole("button", { name: "Pin node" })
    fireEvent.click(pin)
    expect(screen.getByRole("button", { name: "Unpin node" })).toBeInTheDocument()
  })

  it("dims/stale-marks the canvas and shows the status when not live (AE7)", () => {
    h.hook = hook({ status: "reconnecting", graph: { nodes: [], edges: [], epics: [] } })
    const { container } = render(<Cockpit plan_id="p1" />)

    expect(container.querySelector('[data-stale="true"]')).toBeInTheDocument()
    expect(screen.getByText("Reconnecting…")).toBeInTheDocument()
  })

  it("surfaces a new run in the switcher when runs:update lands", () => {
    h.hook = hook({ runs: [{ run_id: "run-2", started_at: "x", slice_ids: [] }] })
    render(<Cockpit plan_id="p1" />)
    expect(screen.getByRole("option", { name: "run-2" })).toBeInTheDocument()
  })

  it("shows the needs-me rail; selecting an item centers the viewport, no mutation (R5/AE5)", () => {
    h.hook = hook({
      graph: {
        nodes: [{ id: "a", state: "failed", title: "Slice A" }],
        edges: [],
        epics: [],
      },
      attention: {
        items: [
          { slice_id: "a", title: "Slice A", label: "A", state: "failed", kind: "failed", rank: 40 },
        ],
        runs: [],
      },
    })
    render(<Cockpit plan_id="p1" />)

    // The rail lists the needs-a-human item; clicking it centers the canvas.
    const rail = screen.getByLabelText("Needs me")
    fireEvent.click(within(rail).getByRole("button"))
    expect(h.setCenter).toHaveBeenCalled()
  })

  it("orders the switcher by attention and persists the selection to the URL (R6/AE10)", () => {
    h.hook = hook({
      runs: [
        { run_id: "calm", started_at: "x", slice_ids: [] },
        { run_id: "busy", started_at: "y", slice_ids: [] },
      ],
      attention: {
        items: [],
        runs: [
          { run_id: "calm", attention: 0 },
          { run_id: "busy", attention: 3 },
        ],
      },
    })
    render(<Cockpit plan_id="p1" />)

    // The busy run (more attention) sorts above the calm one.
    const options = screen.getAllByRole("option").map((o) => o.value)
    expect(options.indexOf("busy")).toBeLessThan(options.indexOf("calm"))

    // Selecting a run writes it to the URL so a reload restores it.
    fireEvent.change(screen.getByRole("combobox"), { target: { value: "busy" } })
    expect(new URLSearchParams(window.location.search).get("run")).toBe("busy")
  })

  it("restores the selected run from the URL on mount (AE10)", () => {
    window.history.replaceState({}, "", "/?run=run-7")
    h.hook = hook({ runs: [{ run_id: "run-7", started_at: "x", slice_ids: [] }] })
    render(<Cockpit plan_id="p1" />)
    expect(screen.getByRole("combobox")).toHaveValue("run-7")
    window.history.replaceState({}, "", "/")
  })
})
