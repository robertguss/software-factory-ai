import { render, screen } from "@testing-library/react"
import { describe, expect, it } from "vitest"
import ConnectionStatus, { isLive, STATUS_LABELS } from "@/components/connection-status"

describe("ConnectionStatus", () => {
  it("labels each known status", () => {
    for (const [status, label] of Object.entries(STATUS_LABELS)) {
      const { unmount } = render(<ConnectionStatus status={status} />)
      expect(screen.getByRole("status")).toHaveTextContent(label)
      unmount()
    }
  })

  it("exposes the raw status for styling hooks", () => {
    render(<ConnectionStatus status="reconnecting" />)
    expect(screen.getByRole("status")).toHaveAttribute("data-status", "reconnecting")
  })

  it("treats only `live` as the calm state", () => {
    expect(isLive("live")).toBe(true)
    expect(isLive("reconnecting")).toBe(false)
    expect(isLive("disconnected")).toBe(false)
  })
})
