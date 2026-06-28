import { ShieldCheck } from "lucide-react"
import SliceCard from "@/components/slice-card"
import { byAttention } from "@/lib/color-law"

// The needs-me rail (R5): the few items needing a human — gate-waiting and failed
// slices — surfaced by the server attention projection (U5), highest-attention
// first. Each row is a compact SliceCard plus a reason label. The rail *navigates*
// (onSelect centers/selects the node); it never acts — no mutation path. Empty is
// a visible "all clear" marker, never a hidden rail, so a calm run still reads.
//
// Security: item text (title/label) flows through SliceCard's escaped text
// interpolation; the reason is a server enum. No dangerouslySetInnerHTML.
const KIND_LABEL = { failed: "failed", gate_waiting: "gate waiting" }

function reasonLabel(item) {
  if (item.kind === "gate_waiting" && item.outcome) {
    return String(item.outcome).replaceAll("_", " ")
  }
  return KIND_LABEL[item.kind] ?? item.kind
}

export default function NeedsMeRail({ items = [], onSelect }) {
  const sorted = [...items].sort(byAttention)

  return (
    <aside aria-label="Needs me" className="flex h-full flex-col gap-1 overflow-y-auto">
      <h2 className="px-1 text-xs font-semibold uppercase tracking-wide text-muted">Needs me</h2>

      {sorted.length === 0 ? (
        <p
          data-testid="all-clear"
          className="flex items-center gap-1.5 px-1 py-2 text-xs text-muted"
        >
          <ShieldCheck size={13} aria-hidden="true" />
          All clear
        </p>
      ) : (
        <ul className="flex flex-col gap-1">
          {sorted.map((item) => (
            <li key={item.slice_id}>
              <button type="button" onClick={() => onSelect?.(item)} className="block w-full text-left">
                <SliceCard
                  node={{
                    id: item.slice_id,
                    title: item.title,
                    label: item.label,
                    state: item.state,
                  }}
                  scale="compact"
                />
                <span className="px-2 text-[10px] uppercase tracking-wide text-muted">
                  {reasonLabel(item)}
                </span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </aside>
  )
}
