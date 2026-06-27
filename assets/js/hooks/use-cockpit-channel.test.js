import { act, renderHook } from "@testing-library/react"
import { StrictMode } from "react"
import { beforeEach, describe, expect, it, vi } from "vitest"

// Registry of fake sockets created during a test, populated by the phoenix mock.
const h = vi.hoisted(() => ({ sockets: [] }))

vi.mock("phoenix", () => {
  class FakeChannel {
    constructor(topic, params) {
      this.topic = topic
      this.params = params
      this.handlers = {}
      this.joinCbs = {}
      this.left = false
    }
    on(event, cb) {
      this.handlers[event] = cb
      return this
    }
    join() {
      const recv = {
        receive: (status, cb) => {
          this.joinCbs[status] = cb
          return recv
        },
      }
      return recv
    }
    push() {
      const recv = { receive: () => recv }
      return recv
    }
    leave() {
      this.left = true
    }
    emit(event, payload) {
      this.handlers[event]?.(payload)
    }
  }

  class FakeSocket {
    constructor(path) {
      this.path = path
      this.connected = false
      this.disconnected = false
      this.channels = []
      h.sockets.push(this)
    }
    connect() {
      this.connected = true
    }
    disconnect() {
      this.disconnected = true
    }
    channel(topic, params) {
      const channel = new FakeChannel(topic, params)
      this.channels.push(channel)
      return channel
    }
    onError(cb) {
      this.errorCb = cb
    }
    onClose(cb) {
      this.closeCb = cb
    }
  }

  return { Socket: FakeSocket }
})

import { foldPatch, useCockpitChannel } from "@/hooks/use-cockpit-channel"

const latest = () => {
  const socket = h.sockets[h.sockets.length - 1]
  return { socket, channel: socket.channels[socket.channels.length - 1] }
}

beforeEach(() => {
  h.sockets = []
})

describe("foldPatch", () => {
  it("replaces only the patched nodes, preserving others and their positions", () => {
    const nodes = [
      { id: "a", state: "running", position: { x: 1, y: 2 } },
      { id: "b", state: "ready_idle", position: { x: 3, y: 4 } },
    ]
    const out = foldPatch(nodes, [{ id: "a", state: "failed" }])

    expect(out.find((n) => n.id === "a").state).toBe("failed")
    expect(out.find((n) => n.id === "a").position).toEqual({ x: 1, y: 2 })
    // the untouched node keeps its exact reference (no needless re-render churn)
    expect(out.find((n) => n.id === "b")).toBe(nodes[1])
  })
})

describe("useCockpitChannel", () => {
  it("starts pre-seed and flips seeded/live on the first graph:init", () => {
    const { result } = renderHook(() => useCockpitChannel({ planId: "p1" }))
    expect(result.current.seeded).toBe(false)

    const { channel } = latest()
    act(() =>
      channel.emit("graph:init", {
        nodes: [{ id: "a", state: "running" }],
        edges: [],
        epics: [],
      }),
    )

    expect(result.current.seeded).toBe(true)
    expect(result.current.status).toBe("live")
    expect(result.current.graph.nodes).toHaveLength(1)
  })

  it("folds a node:patch into only the targeted node, leaving positions intact (AE1)", () => {
    const { result } = renderHook(() => useCockpitChannel({ planId: "p1" }))
    const { channel } = latest()

    act(() =>
      channel.emit("graph:init", {
        nodes: [
          { id: "a", state: "running", position: { x: 0, y: 0 } },
          { id: "b", state: "ready_idle", position: { x: 5, y: 5 } },
        ],
        edges: [],
        epics: [],
      }),
    )
    act(() => channel.emit("node:patch", { nodes: [{ id: "a", state: "failed" }] }))

    const a = result.current.graph.nodes.find((n) => n.id === "a")
    const b = result.current.graph.nodes.find((n) => n.id === "b")
    expect(a.state).toBe("failed")
    expect(a.position).toEqual({ x: 0, y: 0 })
    expect(b.state).toBe("ready_idle")
  })

  it("gains a new run live on runs:update", () => {
    const { result } = renderHook(() => useCockpitChannel({ planId: "p1" }))
    const { channel } = latest()
    act(() => channel.emit("runs:update", { runs: [{ run_id: "run-2" }] }))
    expect(result.current.runs).toEqual([{ run_id: "run-2" }])
  })

  it("marks the canvas stale on a socket drop (AE7)", () => {
    const { result } = renderHook(() => useCockpitChannel({ planId: "p1" }))
    const { socket, channel } = latest()
    act(() => channel.emit("graph:init", { nodes: [], edges: [], epics: [] }))
    expect(result.current.status).toBe("live")

    act(() => socket.errorCb?.())
    expect(result.current.status).toBe("reconnecting")
  })

  it("marks status rejected when the join is refused", () => {
    const { result } = renderHook(() => useCockpitChannel({ planId: "p1" }))
    const { channel } = latest()
    act(() => channel.joinCbs.error?.({ reason: "nope" }))
    expect(result.current.status).toBe("rejected")
  })

  it("leaves the channel and disconnects the socket on unmount", () => {
    const { unmount } = renderHook(() => useCockpitChannel({ planId: "p1" }))
    const { socket, channel } = latest()
    unmount()
    expect(channel.left).toBe(true)
    expect(socket.disconnected).toBe(true)
  })

  it("survives a StrictMode double-mount without leaking subscriptions", () => {
    const { unmount } = renderHook(() => useCockpitChannel({ planId: "p1" }), {
      wrapper: StrictMode,
    })
    unmount()
    // Every socket created across the double-mount is torn down: disconnected,
    // with its channel left. No dangling subscription.
    expect(h.sockets.length).toBeGreaterThanOrEqual(1)
    expect(h.sockets.every((s) => s.disconnected)).toBe(true)
    expect(h.sockets.every((s) => s.channels.every((c) => c.left))).toBe(true)
  })
})
