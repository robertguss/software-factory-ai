import { Handle, Position } from "@xyflow/react"
import { Layers } from "lucide-react"

// A folded epic (R4): one compact chip standing in for a completed epic's members,
// showing the epic label and a "done/total · failed" rollup. Failed members tint
// the chip with the warning treatment so a folded-away failure stays visible.
// Defined at module scope and registered in the canvas `edgeTypes`/`nodeTypes`.
export default function EpicChip({ data = {} }) {
  const { label, total = 0, done = 0, failed = 0 } = data
  const tone = failed > 0 ? "var(--color-sev-warning)" : "var(--color-border)"

  return (
    <>
      <Handle type="target" position={Position.Left} className="!bg-border" />
      <article
        data-testid="epic-chip"
        data-failed={failed}
        style={{ borderColor: tone }}
        className="flex items-center gap-1.5 rounded-md border bg-surface px-2.5 py-1.5 text-xs text-fg"
      >
        <Layers size={13} aria-hidden="true" style={{ color: tone }} />
        <span className="truncate" title={label}>
          {label}
        </span>
        <span className="ml-auto tabular-nums text-muted">
          {done}/{total}
          {failed > 0 ? ` · ${failed} failed` : ""}
        </span>
      </article>
      <Handle type="source" position={Position.Right} className="!bg-border" />
    </>
  )
}
