// Test stub for the `phoenix` JS client. In production, esbuild bundles the real
// client from deps/phoenix via NODE_PATH; vitest can't see that path, so the
// vitest config aliases `phoenix` to this inert default. The channel-hook test
// replaces it with a controllable fake via vi.mock; any other test that pulls
// the hook in transitively gets this no-op.
export class Socket {
  connect() {}
  disconnect() {}
  channel() {
    const channel = {
      on: () => channel,
      join: () => ({ receive: () => ({ receive: () => {} }) }),
      push: () => ({ receive: () => {} }),
      leave: () => {},
    }
    return channel
  }
  onError() {}
  onClose() {}
}
