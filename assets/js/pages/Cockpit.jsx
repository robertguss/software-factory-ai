import { useMemo, useRef, useState } from "react"
import { Background, Controls, ReactFlow, ReactFlowProvider, useReactFlow } from "@xyflow/react"
import AppShell from "@/components/app-shell"
import AmbientBorder from "@/components/ambient-border"
import ConnectionStatus, { isLive } from "@/components/connection-status"
import MasterCautionStrip from "@/components/master-caution-strip"
import SliceNode from "@/components/slice-node"
import { useCockpitChannel } from "@/hooks/use-cockpit-channel"
import { cn } from "@/lib/cn"
import { layoutPositions, toFlowEdges, toFlowNodes, topologyKey } from "@/lib/flow"

// Defined at module scope so React Flow's node-type registry is stable.
const nodeTypes = { slice: SliceNode }
const LIVE_RUN = "default"

// The graph canvas. Positions are recomputed by dagre only when the topology
// changes; a data-only patch reuses them (no relayout, AE1).
function CockpitCanvas({ graph }) {
  const { setCenter } = useReactFlow()
  const positionsRef = useRef(new Map())
  const topo = topologyKey(graph.nodes, graph.edges)

  useMemo(() => {
    positionsRef.current = layoutPositions(graph.nodes, graph.edges)
  }, [topo])

  const rfNodes = toFlowNodes(graph.nodes, positionsRef.current)
  const rfEdges = toFlowEdges(graph.edges)

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
          nodesDraggable={false}
          fitView
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
