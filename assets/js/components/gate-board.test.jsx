import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import GateBoard from "@/components/gate-board"

describe("GateBoard", () => {
  // AE6: a failing check + an abstaining check render as NO-GO and Abstain, with
  // evidence, and no single aggregate pass checkmark can render the gate passed.
  it("renders a non-vacuous board: NO-GO + Abstain, never an aggregate pass", () => {
    render(
      <GateBoard
        gate={{
          passed: false,
          stages: [
            { name: "tests", status: "failed", evidence: "3 failing specs" },
            { name: "coverage", status: "baseline_absent" },
          ],
        }}
      />,
    )

    expect(screen.getByText("NO-GO")).toBeInTheDocument()
    expect(screen.getByText("Abstain")).toBeInTheDocument()
    expect(screen.getByText("3 failing specs")).toBeInTheDocument()
    // No aggregate GO is synthesized from a board of non-passing checks.
    expect(screen.queryByText("GO")).not.toBeInTheDocument()
    expect(screen.getAllByRole("row")).toHaveLength(2)
  })

  it("reflects a finished run's committed status as a single row, not a pass", () => {
    render(<GateBoard gate={{ status: "parked", findings: [] }} />)
    expect(screen.getByText("STANDBY")).toBeInTheDocument()
    expect(screen.queryByText("GO")).not.toBeInTheDocument()
  })

  it("shows an empty marker when there is no gate verdict", () => {
    render(<GateBoard gate={null} />)
    expect(screen.getByTestId("gate-empty")).toBeInTheDocument()
  })

  it("maps a passing stage to GO", () => {
    render(<GateBoard gate={{ stages: [{ name: "lint", status: "passed" }] }} />)
    expect(screen.getByText("GO")).toBeInTheDocument()
  })

  it("renders gate-derived text as text, never as HTML (XSS-safe)", () => {
    render(
      <GateBoard
        gate={{ stages: [{ name: "<img src=x onerror=alert(1)>", status: "failed" }] }}
      />,
    )
    // The payload is shown verbatim as text, not parsed into an element.
    expect(screen.getByText("<img src=x onerror=alert(1)>")).toBeInTheDocument()
    expect(document.querySelector("img")).toBeNull()
  })
})
