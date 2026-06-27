import { colorLaw } from "@/lib/color-law"
import { cn } from "@/lib/cn"

// A single run-DAG node rendered as a status card at DAG/nano scale (R7) — the
// replacement for the old Cytoscape circle. Purely presentational: it consumes
// one node_payload (the U7 wire shape) and applies the color-law treatment +
// icon (R8/R10). Compact/full scales are deferred (Scope Boundaries).
//
// Security: `title`/`label` are agent/repo-derived. They only ever pass through
// React text interpolation (which escapes), never dangerouslySetInnerHTML.
export default function SliceCard({ node }) {
  const { title, label, state, starved_dependents = 0 } = node
  const law = colorLaw(state, { starved_dependents })
  const Icon = law.icon
  const name = title || label

  // The token is a role name backed by a :root CSS variable (app.css). Driving
  // color through the variable (not a dynamic Tailwind class) keeps it out of
  // the purge path — `bg-${token}` would never be seen by the scanner.
  const tone = `var(--color-${law.token})`

  return (
    <article
      data-state={state}
      data-severity={law.severity ?? "none"}
      style={{ borderColor: tone, color: tone }}
      className={cn(
        "flex items-center gap-1.5 rounded-md border bg-surface px-2 py-1 text-xs",
      )}
    >
      <Icon size={12} aria-hidden="true" />
      <span className="truncate text-fg" title={name}>
        {name}
      </span>
      {starved_dependents > 0 && (
        <span
          data-testid="starved-count"
          className="ml-auto tabular-nums text-muted"
          title="starved dependents"
        >
          {starved_dependents}
        </span>
      )}
    </article>
  )
}
