// Temporary Inertia baseline page (U2): the first React page rendered through
// the server→Inertia→React path. Retired at the /runs cutover (U10).
export default function Hello({ greeting }) {
  return (
    <main>
      <h1>Cockpit foundation</h1>
      <p>{greeting}</p>
    </main>
  )
}
