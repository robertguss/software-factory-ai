import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import AppShell from "@/components/app-shell"

describe("AppShell", () => {
  it("renders nav affordances, with Runs as the current page", () => {
    render(
      <AppShell>
        <div>content</div>
      </AppShell>,
    )
    const runs = screen.getByRole("link", { name: "Runs" })
    expect(runs).toHaveAttribute("href", "/runs")
    expect(runs).toHaveAttribute("aria-current", "page")
    // Future entity screens are present as affordances but not built.
    expect(screen.getByRole("link", { name: "Plans" })).toBeInTheDocument()
  })

  it("renders its content slot", () => {
    render(
      <AppShell>
        <div data-testid="slot">hello</div>
      </AppShell>,
    )
    expect(screen.getByTestId("slot")).toHaveTextContent("hello")
  })
})
