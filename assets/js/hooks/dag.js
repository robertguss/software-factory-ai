// Dag — the cockpit's living dependency graph.
//
// Mounts Cytoscape.js with an elkjs layered (Sugiyama) layout, direction RIGHT,
// inside a `phx-update="ignore"` container so LiveView never touches the canvas.
// The server seam:
//   • server `push_event("graph:init", …)`  → full (re)seed; relayout (R4 structural).
//   • server `push_event("node:patch", …)`  → attribute diff on named nodes; NO relayout (R9).
//   • client `pushEvent("node:select", {id})` → open the read-only detail panel (U5).
//
// Cytoscape has no built-in ELK binding: `elkjs` is the solver and `cytoscape-elk`
// is the adapter that registers the `elk` layout.
import cytoscape from "cytoscape"
import elk from "cytoscape-elk"

cytoscape.use(elk)

const LAYOUT = {
  name: "elk",
  elk: {
    algorithm: "layered",
    "elk.direction": "RIGHT",
    "elk.layered.spacing.nodeNodeBetweenLayers": 60,
    "elk.spacing.nodeNode": 28,
  },
}

// One colour token per computed node state (R10). Mirrors the server taxonomy.
const STATE_COLORS = {
  stalled: "#b91c1c",
  running: "#0f766e",
  skipped: "#a16207",
  blocked: "#64748b",
  ready_idle: "#2563eb",
  done: "#15803d",
  failed: "#991b1b",
  parked: "#7c3aed",
}

const STYLE = [
  {
    selector: "node",
    style: {
      "background-color": (ele) => STATE_COLORS[ele.data("state")] || "#94a3b8",
      label: "data(label)",
      color: "#0f172a",
      "font-size": 11,
      "text-valign": "center",
      "text-halign": "center",
      "text-margin-y": 0,
      width: 46,
      height: 46,
      "border-width": 2,
      "border-color": "#ffffff",
    },
  },
  {
    selector: "node:parent",
    style: {
      "background-opacity": 0.08,
      "background-color": "#0f172a",
      label: "data(label)",
      "text-valign": "top",
      "text-halign": "center",
      "font-size": 12,
      "border-width": 1,
      "border-color": "#cbd5e1",
      padding: 16,
    },
  },
  {
    selector: "edge",
    style: {
      width: 2,
      "line-color": "#cbd5e1",
      "target-arrow-color": "#cbd5e1",
      "target-arrow-shape": "triangle",
      "curve-style": "bezier",
    },
  },
  {
    // Edge-flow animation is limited to edges leaving the active node (R9).
    selector: "edge.flowing",
    style: {
      "line-color": "#0f766e",
      "target-arrow-color": "#0f766e",
      "line-dash-pattern": [6, 4],
      "line-style": "dashed",
    },
  },
]

const Dag = {
  mounted() {
    this.cy = cytoscape({
      container: this.el,
      style: STYLE,
      wheelSensitivity: 0.2,
      // Topology is server-authoritative; the user does not edit it (observe-only).
      autoungrabify: true,
      boxSelectionEnabled: false,
    })

    this.cy.on("tap", "node", (event) => {
      const node = event.target
      if (node.isParent()) return
      this.pushEvent("node:select", { id: node.id() })
    })

    // Full (re)seed + relayout.
    this.handleEvent("graph:init", ({ nodes, edges, epics }) => {
      this.seed(nodes || [], edges || [], epics || [])
    })

    // Targeted attribute diff — patch named nodes, no relayout (R9).
    this.handleEvent("node:patch", ({ nodes }) => {
      this.patch(nodes || [])
    })

    // Ask the server for the initial graph once the hook is live, so the seed is
    // never raced by a push that arrives before `handleEvent` is registered.
    this.pushEvent("dag:mounted", {})
  },

  destroyed() {
    if (this.cy) this.cy.destroy()
  },

  seed(nodes, edges, epics) {
    const elements = [
      ...epics.map((epic) => ({
        data: { id: epic.id, label: epic.label },
      })),
      ...nodes.map((node) => ({
        data: {
          id: node.id,
          label: node.label,
          state: node.state,
          parent: node.epic_id || undefined,
        },
      })),
      ...edges.map((edge) => ({
        data: { id: edge.id, source: edge.from, target: edge.to },
      })),
    ]

    this.cy.startBatch()
    this.cy.elements().remove()
    this.cy.add(elements)
    this.cy.endBatch()
    this.cy.layout(LAYOUT).run()
  },

  patch(nodes) {
    this.cy.startBatch()
    nodes.forEach((node) => {
      const ele = this.cy.getElementById(node.id)
      if (ele.nonempty()) ele.data("state", node.state)
    })
    this.cy.endBatch()
  },
}

export default Dag
