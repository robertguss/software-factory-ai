import { render, screen } from "@testing-library/react"
import { describe, it, expect } from "vitest"

// Smoke test for the React/JSX toolchain (U1). Proves Vitest + jsdom +
// @testing-library render a component before any real cockpit code exists.
function Hello() {
  return <p>cockpit toolchain online</p>
}

describe("react toolchain", () => {
  it("mounts a JSX component into the DOM", () => {
    render(<Hello />)
    expect(screen.getByText("cockpit toolchain online")).toBeInTheDocument()
  })
})
