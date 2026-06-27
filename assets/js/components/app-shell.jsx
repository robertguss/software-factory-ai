import { cn } from "@/lib/cn"

// The dark-mode-first root shell that frames the cockpit (R2). It carries nav
// affordances for future entity screens (plans, evidence, …) that are NOT built
// in this slice — those links are placeholders. The active page mounts in the
// content slot.
const DEFAULT_NAV = [
  { label: "Runs", href: "/runs", current: true },
  { label: "Plans", href: "#", current: false },
  { label: "Evidence", href: "#", current: false },
]

export default function AppShell({ children, nav = DEFAULT_NAV }) {
  return (
    <div className="flex min-h-screen bg-bg text-fg">
      <aside
        aria-label="Primary"
        className="flex w-48 flex-col gap-1 border-r border-border bg-surface p-3"
      >
        <div className="px-2 py-1 text-sm font-semibold text-muted">Conveyor</div>
        <nav className="flex flex-col gap-0.5">
          {nav.map((item) => (
            <a
              key={item.label}
              href={item.href}
              aria-current={item.current ? "page" : undefined}
              className={cn(
                "rounded px-2 py-1 text-sm text-muted hover:text-fg",
                item.current && "bg-bg text-fg",
              )}
            >
              {item.label}
            </a>
          ))}
        </nav>
      </aside>
      <main className="flex-1 overflow-auto">{children}</main>
    </div>
  )
}
