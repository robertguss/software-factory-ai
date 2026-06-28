import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import { Background, Controls, ReactFlow, ReactFlowProvider, useReactFlow } from "@xyflow/react"
import AppShell from "@/components/app-shell"
import AmbientBorder from "@/components/ambient-border"
import ConnectionStatus, { isLive } from "@/components/connection-status"
import MasterCautionStrip from "@/components/master-caution-strip"
import NeedsMeRail from "@/components/needs-me-rail"
import SliceNode from "@/components/slice-node"
import EpicChip from "@/components/epic-chip"
import FlowEdge from "@/components/flow-edge"
import { useCockpitChannel } from "@/hooks/use-cockpit-channel"
import { cn } from "@/lib/cn"
import { downstreamWaitingCounts } from "@/lib/edge-weight"
import { layoutPositions, toFlowEdges, toFlowNodes, topologyKey } from "@/lib/flow"

// Defined at module scope so React Flow's type registries stay stable.
const nodeTypes = { slice: SliceNode, epicChip: EpicChip }
const edgeTypes = { slice: FlowEdge }
const LIVE_RUN = "default"
// Past this zoom, semantic zoom expands every folded epic (no mode switch, AE3).
const ZOOM_EXPAND_THRESHOLD = 1.4

// The graph canvas. Positions are recomputed by dagre only when the topology
// changes; a data-only patch reuses them (no relayout, AE1).
function CockpitCanvas({ graph, focus }) {
  const { setCenter } = useReactFlow()
  const positionsRef = useRef(new Map())
  const topo = topologyKey(graph.nodes, graph.edges)

  // A pin keeps a chosen node from being auto-folded away (R4); component-local.
  const [pinned, setPinned] = useState(() => new Set())
  const togglePin = useCallback((id) => {
    setPinned((prev) => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })
  }, [])
  // Semantic zoom: zooming in expands the folded past (overview ↔ detail).
  const [expandAll, setExpandAll] = useState(false)

  // A needs-me rail selection (R5/AE5): pin the target so it survives a fold,
  // then center the viewport on it — a navigation, never a mutation.
  useEffect(() => {
    if (!focus?.id) return
    setPinned((prev) => new Set(prev).add(focus.id))
    const pos = positionsRef.current.get(focus.id)
    if (pos) setCenter(pos.x, pos.y, { zoom: 1.2, duration: 300 })
  }, [focus, setCenter])

  useMemo(() => {
    positionsRef.current = layoutPositions(graph.nodes, graph.edges)
  }, [topo])

  // Edge weight depends on node state, so it recomputes per patch (not just on a
  // topology change); memoized on the graph object the hook swaps per patch.
  const counts = useMemo(
    () => downstreamWaitingCounts(graph.nodes, graph.edges),
    [graph],
  )

  const foldOpts = { pinned, expandAll, epics: graph.epics }
  const rfNodes = toFlowNodes(graph.nodes, positionsRef.current, foldOpts).map((n) =>
    n.type === "slice"
      ? { ...n, data: { ...n.data, pinned: pinned.has(n.id), onTogglePin: togglePin } }
      : n,
  )
  const rfEdges = toFlowEdges(graph.edges, graph.nodes, { counts, pinned, expandAll })

  // The caution-strip jump centers the viewport on the pinned node.
  const jumpTo = (id) => {
    const pos = positionsRef.current.get(id)
    if (pos) setCenter(pos.x, pos.y, { zoom: 1.2, duration: 300 })
  }

  return (
    <div className="flex h-full flex-col">
      <MasterCautionStrip nodes={graph.nodes} onJump={jumpTo} />
      <div className="relative flex-1">
        <ReactFlow
          nodes={rfNodes}
          edges={rfEdges}
          nodeTypes={nodeTypes}
          edgeTypes={edgeTypes}
          nodesDraggable={false}
          fitView
          onlyRenderVisibleElements
          onMove={(_e, viewport) => setExpandAll(viewport.zoom >= ZOOM_EXPAND_THRESHOLD)}
          proOptions={{ hideAttribution: true }}
        >
          <Background />
          <Controls showInteractive={false} />
        </ReactFlow>
      </div>
    </div>
  )
}

// The run switcher: the live frontier plus any run surfaced by `runs:update`,
// ordered by attention (R6) — runs with more needing-a-human items sort first.
function RunSwitcher({ runs, attention = [], value, onChange }) {
  const attentionByRun = new Map(attention.map((r) => [r.run_id, r.attention]))
  const ordered = [...runs].sort(
    (a, b) => (attentionByRun.get(b.run_id) ?? 0) - (attentionByRun.get(a.run_id) ?? 0),
  )

  return (
    <label className="ml-auto flex items-center gap-1.5 text-xs text-muted">
      Run
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="rounded border border-border bg-surface px-1.5 py-0.5 text-fg"
      >
        <option value={LIVE_RUN}>Live</option>
        {ordered.map((run) => (
          <option key={run.run_id} value={run.run_id}>
            {run.run_id}
            {attentionByRun.get(run.run_id) ? ` (${attentionByRun.get(run.run_id)})` : ""}
          </option>
        ))}
      </select>
    </label>
  )
}

// The selected run survives a reload by living in the URL (R6/AE10).
function runFromUrl(fallback) {
  if (typeof window === "undefined") return fallback
  return new URLSearchParams(window.location.search).get("run") || fallback
}

function persistRunToUrl(runId) {
  if (typeof window === "undefined") return
  const url = new URL(window.location.href)
  url.searchParams.set("run", runId)
  window.history.replaceState({}, "", url)
}

export default function Cockpit({ plan_id, run_id = LIVE_RUN }) {
  const [selectedRun, setSelectedRun] = useState(() => runFromUrl(run_id))
  const { status, graph, runs, attention, seeded } = useCockpitChannel({
    planId: plan_id,
    runId: selectedRun,
  })
  const live = isLive(status)

  const changeRun = useCallback((id) => {
    setSelectedRun(id)
    persistRunToUrl(id)
  }, [])

  // A needs-me selection requests the canvas center on a node (R5). The bump
  // counter re-fires the effect even when the same node is selected twice.
  const [focus, setFocus] = useState(null)
  const focusNode = useCallback(
    (slice_id) => setFocus((prev) => ({ id: slice_id, n: (prev?.n ?? 0) + 1 })),
    [],
  )

  return (
    <AppShell>
      <div className="flex h-screen flex-col">
        <header className="flex items-center gap-3 border-b border-border px-4 py-2">
          <h1 className="text-sm font-semibold">Cockpit</h1>
          <RunSwitcher
            runs={runs}
            attention={attention.runs}
            value={selectedRun}
            onChange={changeRun}
          />
          <ConnectionStatus status={status} />
        </header>

        <div className="flex flex-1 gap-2 p-2">
          <div className="w-56 shrink-0 overflow-y-auto border-r border-border pr-2">
            <NeedsMeRail items={attention.items} onSelect={(item) => focusNode(item.slice_id)} />
          </div>

          <div className="min-w-0 flex-1">
            <AmbientBorder nodes={graph.nodes}>
              {/* When the socket is not live the canvas is dimmed/stale-marked (AE7). */}
              <div
                data-stale={!live}
                className={cn("h-full transition-opacity", !live && "opacity-60")}
              >
                {!seeded ? (
                  <p className="flex h-full items-center justify-center text-muted">Loading run…</p>
                ) : graph.nodes.length === 0 ? (
                  <p className="flex h-full items-center justify-center text-muted">
                    No plan to display yet
                  </p>
                ) : (
                  <ReactFlowProvider>
                    <CockpitCanvas graph={graph} focus={focus} />
                  </ReactFlowProvider>
                )}
              </div>
            </AmbientBorder>
          </div>
        </div>
      </div>
    </AppShell>
  )
}
