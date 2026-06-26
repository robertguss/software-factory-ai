// Conveyor cockpit browser runtime.
//
// Bundled by esbuild (see the `:esbuild` profile in config/config.exs). The
// `phoenix` and `phoenix_live_view` packages resolve from ../deps via NODE_PATH;
// npm packages (added later for the cockpit graph) resolve from
// assets/node_modules. Until this bundle existed there was no <script> on the
// page, so LiveView's client never connected and `connected?/1` was always false
// outside LiveViewTest.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { createInertiaApp } from "@inertiajs/react"
import { createRoot } from "react-dom/client"
import axios from "axios"
import Dag from "./hooks/dag"
import Hello from "@/pages/Hello"

// Inertia uses axios; Phoenix expects the CSRF token in `x-csrf-token`.
axios.defaults.xsrfHeaderName = "x-csrf-token"

// Static page registry. This esbuild profile has no Vite-style glob or code
// splitting, so pages resolve by name from this map (not dynamic import).
const pages = { Hello }

// Bootstrap Inertia only when its mount node is present. LiveView routes
// (/runs, /parked) render no #app node and keep using LiveSocket alone.
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
  hooks: { Dag },
})

liveSocket.connect()

// Expose for debugging in the browser console:
//   liveSocket.enableDebug()
window.liveSocket = liveSocket
