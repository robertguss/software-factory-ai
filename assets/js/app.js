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
