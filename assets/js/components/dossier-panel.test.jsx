import { fireEvent, render, screen } from "@testing-library/react"
import { describe, expect, it, vi } from "vitest"
import DossierPanel from "@/components/dossier-panel"

const node = { id: "a", title: "Slice A", label: "SLICE-001", state: "failed", blocked_by: [] }

describe("DossierPanel", () => {
  it("stays in the DOM with a placeholder when nothing is selected (no reflow on open)", () => {
    render(<DossierPanel node={null} />)
    expect(screen.getByTestId("dossier-empty")).toBeInTheDocument()
    expect(screen.getByLabelText("Slice dossier")).toBeInTheDocument()
  })

  it("shows a loading skeleton while the detail is in flight", () => {
    render(<DossierPanel node={node} state="loading" />)
    expect(screen.getByTestId("dossier-skeleton")).toBeInTheDocument()
  })

  it("shows an inline retry on error and fires onRetry", () => {
    const onRetry = vi.fn()
    render(<DossierPanel node={node} state="error" onRetry={onRetry} />)
    fireEvent.click(screen.getByRole("button", { name: "Retry" }))
    expect(onRetry).toHaveBeenCalled()
  })

  it("renders the full-scale SliceCard header and the gate board when ready (AE6/AE8)", () => {
    render(
      <DossierPanel
        node={node}
        state="ready"
        history={["ready_idle", "running", "failed"]}
        detail={{
          blocked_by: ["SLICE-000"],
          gate: { stages: [{ name: "tests", status: "failed" }] },
          reviews: [],
          evidence: [],
        }}
      />,
    )

    expect(screen.getByRole("article")).toHaveAttribute("data-scale", "full")
    expect(screen.getByText("NO-GO")).toBeInTheDocument()
    expect(screen.getByTestId("sparkline")).toBeInTheDocument()
    expect(screen.getByText(/blocked by SLICE-000/)).toBeInTheDocument()
  })

  it("dismisses via the close button", () => {
    const onClose = vi.fn()
    render(<DossierPanel node={node} state="ready" detail={{ gate: null }} onClose={onClose} />)
    fireEvent.click(screen.getByRole("button", { name: "Close dossier" }))
    expect(onClose).toHaveBeenCalled()
  })

  it("renders agent-derived findings as text, never executing injected HTML (XSS-safe)", () => {
    render(
      <DossierPanel
        node={node}
        state="ready"
        detail={{
          gate: null,
          reviews: [
            { decision: "rejected", recommendation: "ask_human", findings: [{ message: "<script>alert(1)</script>" }] },
          ],
          evidence: [],
        }}
      />,
    )
    expect(screen.getByText("<script>alert(1)</script>")).toBeInTheDocument()
    expect(document.querySelector("script")).toBeNull()
  })
})
