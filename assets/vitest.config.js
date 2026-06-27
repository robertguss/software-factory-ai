import { defineConfig } from "vitest/config"
import { fileURLToPath } from "node:url"

export default defineConfig({
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./js", import.meta.url)),
      // The phoenix JS client lives in deps/ (esbuild resolves it via NODE_PATH);
      // vitest can't see that, so alias it to an inert stub. Tests that exercise
      // the socket replace it with a fake via vi.mock.
      phoenix: fileURLToPath(new URL("./test/stubs/phoenix.js", import.meta.url)),
    },
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./vitest.setup.js"],
    include: ["js/**/*.test.{js,jsx}"],
  },
})
