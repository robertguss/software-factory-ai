import { topException } from "@/lib/color-law"

// A persistent strip pinning the single top-ranked exception, with a jump
// affordance (R9). Calm runs render nothing. `onJump` receives the pinned node
// id so the page can center/select it.
export default function MasterCautionStrip({ nodes = [], onJump }) {
  const top = topException(nodes)
  if (!top) return null

  const Icon = top.icon
  const { node } = top
  const name = node.title || node.label || node.id

  return (
    <div
      role="status"
      data-severity={top.severity}
      className="flex items-center gap-2 px-3 py-1.5 text-sm"
      style={{ color: `var(--color-${top.token})` }}
    >
      <Icon size={14} aria-hidden="true" />
      <span className="truncate font-medium">{name}</span>
      <span className="text-muted">{node.state}</span>
      <button
        type="button"
        onClick={() => onJump?.(node.id)}
        className="ml-auto rounded border px-2 py-0.5 text-xs text-muted hover:text-fg"
      >
        Jump
      </button>
    </div>
  )
}
