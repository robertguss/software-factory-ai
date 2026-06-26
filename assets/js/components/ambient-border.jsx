import { overallSeverity, SEVERITY } from "@/lib/color-law"

// A thin ambient viewport border encoding overall run health (R9): calm (neutral
// border) when no exceptions, else the max severity's tone. Shares the color-law
// ranking via overallSeverity.
export default function AmbientBorder({ nodes = [], children }) {
  const severity = overallSeverity(nodes)
  const token = severity ? SEVERITY[severity].token : "border"

  return (
    <div
      data-severity={severity ?? "none"}
      className="h-full w-full border-2"
      style={{ borderColor: `var(--color-${token})` }}
    >
      {children}
    </div>
  )
}
