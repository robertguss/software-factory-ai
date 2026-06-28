import { useEffect, useRef, useState } from "react"
import { Socket } from "phoenix"
import { accumulateHistory, seedHistory } from "@/lib/state-sparkline"

const SOCKET_PATH = "/socket"

/**
 * Fold a `node:patch` into the current node list: replace only the patched
 * nodes, merging their new fields while preserving every other node and — since
 * only data fields ship in a patch — every node's React-Flow position (AE1).
 * Pure.
 */
export function foldPatch(nodes, patched) {
  const byId = new Map(patched.map((node) => [node.id, node]))
  return nodes.map((node) => (byId.has(node.id) ? { ...node, ...byId.get(node.id) } : node))
}

/**
 * Subscribe to the cockpit channel for `runId`/`planId` and fold its seed +
 * deltas into local state.
 *
 * All `channel.on` handlers are registered before `join()` so the server's
 * `after_join` seed is never missed. On unmount the channel is left and the
 * socket disconnected — so a StrictMode double-mount tears its first subscription
 * down cleanly rather than leaking a duplicate.
 *
 * Returns `{ status, graph, runs, attention, history, seeded, requestDetail }`. `status` is the
 * connection state (connecting/live/reconnecting/disconnected/rejected);
 * `seeded` flips true on the first `graph:init` (distinguishing the pre-seed
 * loading state from a genuine zero-node empty run).
 */
export function useCockpitChannel({ runId = "default", planId } = {}) {
  const [status, setStatus] = useState("connecting")
  const [graph, setGraph] = useState({ nodes: [], edges: [], epics: [] })
  const [runs, setRuns] = useState([])
  const [attention, setAttention] = useState({ items: [], runs: [] })
  const [history, setHistory] = useState({})
  const [seeded, setSeeded] = useState(false)
  const channelRef = useRef(null)

  useEffect(() => {
    const socket = new Socket(SOCKET_PATH)
    socket.connect()

    const params = planId ? { plan_id: planId } : {}
    const channel = socket.channel(`cockpit:${runId}`, params)
    channelRef.current = channel

    channel.on("graph:init", (payload) => {
      setGraph({ nodes: payload.nodes, edges: payload.edges, epics: payload.epics })
      // Reseed the sparkline baseline — a reconnect's fresh seed clears prior
      // session accumulation (KTD7).
      setHistory(seedHistory(payload.nodes))
      setSeeded(true)
      setStatus("live")
    })

    channel.on("node:patch", (payload) => {
      setGraph((current) => ({ ...current, nodes: foldPatch(current.nodes, payload.nodes) }))
      setHistory((current) => accumulateHistory(current, payload.nodes))
    })

    channel.on("runs:update", (payload) => setRuns(payload.runs))

    // The needs-me items + per-run attention rollup (R5/R6), server-computed and
    // observe-only. The client only paints them; it never infers attention.
    channel.on("attention:update", (payload) =>
      setAttention({ items: payload.items, runs: payload.runs }),
    )

    // A drop dims the canvas; phoenix auto-reconnects and rejoins, and the
    // resulting fresh graph:init flips status back to live (AE7).
    socket.onError(() => setStatus("reconnecting"))
    socket.onClose(() => setStatus("disconnected"))

    channel
      .join()
      .receive("ok", () => setStatus("live"))
      .receive("error", () => setStatus("rejected"))

    return () => {
      channel.leave()
      socket.disconnect()
      channelRef.current = null
    }
  }, [runId, planId])

  // Observe-only read: fetch a node's detail panel data on demand.
  const requestDetail = (id) =>
    new Promise((resolve) => {
      const channel = channelRef.current
      if (!channel) return resolve(null)
      channel.push("node:detail", { id }).receive("ok", (reply) => resolve(reply.detail))
    })

  return { status, graph, runs, attention, history, seeded, requestDetail }
}
