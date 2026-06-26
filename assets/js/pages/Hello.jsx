// Temporary Inertia baseline page (U2): the first React page rendered through
// the server→Inertia→React path. Retired at the /runs cutover (U10).
export default function Hello({ greeting }) {
  return (
    <main className="min-h-screen bg-bg p-8 text-fg">
      <h1 className="text-2xl font-semibold text-status-nominal">Cockpit foundation</h1>
      <p className="text-muted">{greeting}</p>
    </main>
  )
}
