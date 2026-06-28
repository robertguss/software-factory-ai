import { cva } from "class-variance-authority"
import { colorLaw } from "@/lib/color-law"
import { cn } from "@/lib/cn"

// A single run-DAG slice rendered as a status card from one primitive at three
// scales (R1): nano in the DAG, compact in lists/the needs-me rail, full as the
// dossier header. Every scale applies the same color-law treatment + icon
// (R8/R10) and the same data-state/data-severity attributes — only the fields
// shown and the density differ (AE8).
//
// Security: `title`/`label` (and any text field) are agent/repo-derived. They
// only ever pass through React text interpolation (which escapes), never
// dangerouslySetInnerHTML.

const card = cva("flex rounded-md border bg-surface text-fg", {
  variants: {
    scale: {
      nano: "items-center gap-1.5 px-2 py-1 text-xs",
      compact: "items-center gap-2 px-2.5 py-1.5 text-sm",
      full: "flex-col items-stretch gap-1 px-3 py-2 text-sm",
    },
  },
  defaultVariants: { scale: "nano" },
})

export default function SliceCard({ node, scale = "nano" }) {
  const { title, label, state, epic_id = null, blocked_by = [], starved_dependents = 0 } = node
  const law = colorLaw(state, { starved_dependents })
  const Icon = law.icon
  const name = title || label

  // The token is a role name backed by a :root CSS variable (app.css). Driving
  // color through the variable (not a dynamic Tailwind class) keeps it out of
  // the purge path — `bg-${token}` would never be seen by the scanner.
  const tone = `var(--color-${law.token})`

  const starvedBadge = starved_dependents > 0 && (
    <span
      data-testid="starved-count"
      className="ml-auto tabular-nums text-muted"
      title="starved dependents"
    >
      {starved_dependents}
    </span>
  )

  return (
    <article
      data-state={state}
      data-severity={law.severity ?? "none"}
      data-scale={scale}
      style={{ borderColor: tone, color: tone }}
      className={cn(card({ scale }))}
    >
      {scale === "full" ? (
        <>
          <header className="flex items-center gap-1.5">
            <Icon size={14} aria-hidden="true" />
            <span className="truncate text-fg" title={name}>
              {name}
            </span>
            {starvedBadge}
          </header>
          <dl className="grid grid-cols-[auto_1fr] gap-x-2 gap-y-0.5 text-xs text-muted">
            <dt>state</dt>
            <dd className="text-fg">{state}</dd>
            {epic_id != null && (
              <>
                <dt>epic</dt>
                <dd className="truncate text-fg" title={String(epic_id)}>
                  {epic_id}
                </dd>
              </>
            )}
            <dt>blocked by</dt>
            <dd className="text-fg">{blocked_by.length}</dd>
            <dt>starved</dt>
            <dd className="text-fg">{starved_dependents}</dd>
          </dl>
        </>
      ) : (
        <>
          <Icon size={scale === "compact" ? 13 : 12} aria-hidden="true" />
          <span className="truncate text-fg" title={name}>
            {name}
          </span>
          {scale === "compact" && (
            <span className="text-muted" data-testid="compact-meta">
              {state}
              {epic_id != null ? ` · ${epic_id}` : ""}
            </span>
          )}
          {starvedBadge}
        </>
      )}
    </article>
  )
}
