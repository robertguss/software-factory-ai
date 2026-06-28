import { X } from "lucide-react"
import SliceCard from "@/components/slice-card"
import GateBoard from "@/components/gate-board"
import { colorLaw } from "@/lib/color-law"

// The read-only slice dossier (R7): a full-scale SliceCard header, a failure
// fingerprint (session state-transition sparkline + blocked_by chain), the
// non-vacuous gate board, and the review/evidence the run produced. It occupies a
// fixed column that is always in the DOM, so opening it never reflows the canvas;
// idle shows a placeholder, in-flight a skeleton, an error an inline retry.
//
// Observe-only + XSS-safe: nothing here acts, and all agent/repo-derived text
// (findings, summaries, slice title) renders via JSX interpolation only.

function Sparkline({ history }) {
  if (history.length < 2) {
    return <p className="text-xs text-muted">No transitions yet this session.</p>
  }

  return (
    <div data-testid="sparkline" aria-label="state transitions" className="flex items-end gap-0.5">
      {history.map((state, i) => {
        const law = colorLaw(state)
        return (
          <span
            key={i}
            title={state}
            style={{ backgroundColor: `var(--color-${law.token})`, height: law.rank > 0 ? 12 : 6 }}
            className="w-1 rounded-sm"
          />
        )
      })}
    </div>
  )
}

function findingText(finding) {
  if (typeof finding === "string") return finding
  return finding.message ?? finding.title ?? finding.summary ?? finding.detail ?? ""
}

function Reviews({ reviews }) {
  if (!reviews?.length) return null

  return (
    <section>
      <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">Reviews</h3>
      <ul className="flex flex-col gap-1 text-xs">
        {reviews.map((review, i) => (
          <li key={i} className="rounded border border-border px-2 py-1">
            <div className="flex gap-2 text-fg">
              <span>{review.decision}</span>
              <span className="text-muted">· {review.recommendation}</span>
            </div>
            {review.summary && <p className="text-muted">{review.summary}</p>}
            {(review.findings ?? []).map((finding, j) => (
              <p key={j} className="text-muted">
                {findingText(finding)}
              </p>
            ))}
          </li>
        ))}
      </ul>
    </section>
  )
}

function Evidence({ evidence }) {
  if (!evidence?.length) return null

  return (
    <section>
      <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">Evidence</h3>
      <ul className="flex flex-col gap-1 text-xs">
        {evidence.map((record, i) => (
          <li key={i} className="rounded border border-border px-2 py-1 text-muted">
            {record.summary && <p>{record.summary}</p>}
            {(record.acceptance_results ?? []).length > 0 && (
              <p>{record.acceptance_results.length} acceptance checks</p>
            )}
            {(record.risks ?? []).length > 0 && <p>{record.risks.length} risks</p>}
          </li>
        ))}
      </ul>
    </section>
  )
}

export default function DossierPanel({
  node,
  detail,
  state = "idle",
  history = [],
  onRetry,
  onClose,
}) {
  if (!node) {
    return (
      <aside aria-label="Slice dossier" className="h-full overflow-y-auto">
        <p data-testid="dossier-empty" className="p-2 text-xs text-muted">
          Select a node to inspect its dossier.
        </p>
      </aside>
    )
  }

  return (
    <aside
      aria-label="Slice dossier"
      className="flex h-full flex-col gap-2 overflow-y-auto text-sm"
    >
      <header className="flex items-start gap-2">
        <div className="min-w-0 flex-1">
          <SliceCard node={node} scale="full" />
        </div>
        <button
          type="button"
          aria-label="Close dossier"
          onClick={onClose}
          className="rounded p-1 text-muted hover:text-fg"
        >
          <X size={14} aria-hidden="true" />
        </button>
      </header>

      {state === "loading" && (
        <div data-testid="dossier-skeleton" className="h-24 animate-pulse rounded bg-surface" />
      )}

      {state === "error" && (
        <div data-testid="dossier-error" className="rounded border border-border p-2 text-xs">
          <p className="text-fg">Couldn’t load this dossier.</p>
          <button
            type="button"
            onClick={onRetry}
            className="mt-1 rounded border border-border px-2 py-0.5 text-muted hover:text-fg"
          >
            Retry
          </button>
        </div>
      )}

      {state === "ready" && detail && (
        <>
          <section>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">
              Failure fingerprint
            </h3>
            <Sparkline history={history} />
            {detail.blocked_by?.length > 0 && (
              <p className="mt-1 text-xs text-muted">blocked by {detail.blocked_by.join(" → ")}</p>
            )}
          </section>

          <section>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">Gate</h3>
            <GateBoard gate={detail.gate} />
          </section>

          <Reviews reviews={detail.reviews} />
          <Evidence evidence={detail.evidence} />
        </>
      )}
    </aside>
  )
}
