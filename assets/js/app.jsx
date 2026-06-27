// Conveyor cockpit browser runtime.
//
// Bundled by esbuild (see the `:esbuild` profile in config/config.exs). The
// `phoenix` and `phoenix_live_view` packages resolve from ../deps via NODE_PATH;
// npm packages resolve from assets/node_modules. The page mounts either an
// Inertia/React page (the cockpit at /runs) or a LiveView (/parked) — both share
// this one bundle and the LiveSocket below keeps /parked live.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { createInertiaApp } from "@inertiajs/react"
import { createRoot } from "react-dom/client"
import axios from "axios"
import Cockpit from "@/pages/Cockpit"

// Inertia uses axios; Phoenix expects the CSRF token in `x-csrf-token`.
axios.defaults.xsrfHeaderName = "x-csrf-token"

// Static page registry. This esbuild profile has no Vite-style glob or code
// splitting, so pages resolve by name from this map (not dynamic import).
const pages = { Cockpit }

// Bootstrap Inertia only when its mount node is present. LiveView routes
// (/parked) render no #app node and keep using LiveSocket alone.
if (document.getElementById("app")) {
  createInertiaApp({
    resolve: (name) => pages[name],
    setup({ App, el, props }) {
      createRoot(el).render(<App {...props} />)
    },
  })
}

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content")

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
})

liveSocket.connect()

// Expose for debugging in the browser console:
//   liveSocket.enableDebug()
window.liveSocket = liveSocket
