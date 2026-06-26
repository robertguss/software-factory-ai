import { render } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import AmbientBorder from "@/components/ambient-border"

const wrapper = (nodes) => render(<AmbientBorder nodes={nodes} />).container.firstChild

describe("AmbientBorder", () => {
  it("is calm when no exceptions are present", () => {
    const el = wrapper([{ id: "a", state: "running" }, { id: "b", state: "done" }])
    expect(el).toHaveAttribute("data-severity", "none")
  })

  it("reflects degraded health as the max severity present (AE3)", () => {
    const el = wrapper([
      { id: "a", state: "running" },
      { id: "b", state: "failed" },
      { id: "c", state: "stalled" },
    ])
    expect(el).toHaveAttribute("data-severity", "warning")
  })

  it("renders its children", () => {
    const { getByTestId } = render(
      <AmbientBorder nodes={[]}>
        <span data-testid="canvas" />
      </AmbientBorder>,
    )
    expect(getByTestId("canvas")).toBeInTheDocument()
  })
})
