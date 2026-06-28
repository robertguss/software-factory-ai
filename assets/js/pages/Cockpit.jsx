import { useCallback, useMemo, useRef, useState } from "react"
import { Background, Controls, ReactFlow, ReactFlowProvider, useReactFlow } from "@xyflow/react"
import AppShell from "@/components/app-shell"
import AmbientBorder from "@/components/ambient-border"
import ConnectionStatus, { isLive } from "@/components/connection-status"
import MasterCautionStrip from "@/components/master-caution-strip"
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
function CockpitCanvas({ graph }) {
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

// The run switcher: the live frontier plus any run surfaced by `runs:update`.
function RunSwitcher({ runs, value, onChange }) {
  return (
    <label className="ml-auto flex items-center gap-1.5 text-xs text-muted">
      Run
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="rounded border border-border bg-surface px-1.5 py-0.5 text-fg"
      >
        <option value={LIVE_RUN}>Live</option>
        {runs.map((run) => (
          <option key={run.run_id} value={run.run_id}>
            {run.run_id}
          </option>
        ))}
      </select>
    </label>
  )
}

export default function Cockpit({ plan_id, run_id = LIVE_RUN }) {
  const [selectedRun, setSelectedRun] = useState(run_id)
  const { status, graph, runs, seeded } = useCockpitChannel({
    planId: plan_id,
    runId: selectedRun,
  })
  const live = isLive(status)

  return (
    <AppShell>
      <div className="flex h-screen flex-col">
        <header className="flex items-center gap-3 border-b border-border px-4 py-2">
          <h1 className="text-sm font-semibold">Cockpit</h1>
          <RunSwitcher runs={runs} value={selectedRun} onChange={setSelectedRun} />
          <ConnectionStatus status={status} />
        </header>

        <div className="flex-1 p-2">
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
                  <CockpitCanvas graph={graph} />
                </ReactFlowProvider>
              )}
            </div>
          </AmbientBorder>
        </div>
      </div>
    </AppShell>
  )
}
