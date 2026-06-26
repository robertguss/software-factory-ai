import AppShell from "@/components/app-shell"

// Temporary Inertia baseline page (U2): the first React page rendered through
// the server→Inertia→React path, now framed by the dark app shell (U6). Retired
// at the /runs cutover (U10).
export default function Hello({ greeting }) {
  return (
    <AppShell>
      <main className="p-8">
        <h1 className="text-2xl font-semibold text-status-nominal">Cockpit foundation</h1>
        <p className="text-muted">{greeting}</p>
      </main>
    </AppShell>
  )
}
