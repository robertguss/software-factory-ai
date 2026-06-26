import { cn } from "@/lib/cn"

// The connection states the cockpit surfaces (R6/AE7). "live" is the only calm
// one; every other state means the canvas is stale.
export const STATUS_LABELS = {
  connecting: "Connecting…",
  live: "Live",
  reconnecting: "Reconnecting…",
  disconnected: "Disconnected",
  rejected: "Connection refused",
}

export function isLive(status) {
  return status === "live"
}

export default function ConnectionStatus({ status }) {
  const label = STATUS_LABELS[status] ?? status
  const live = isLive(status)

  return (
    <span
      role="status"
      data-status={status}
      className={cn(
        "inline-flex items-center gap-1.5 rounded px-2 py-0.5 text-xs",
        live ? "text-status-nominal" : "text-sev-caution",
      )}
    >
      <span
        aria-hidden="true"
        className={cn("size-1.5 rounded-full", live ? "bg-status-nominal" : "bg-sev-caution")}
      />
      {label}
    </span>
  )
}
