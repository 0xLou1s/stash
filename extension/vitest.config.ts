import { defineConfig } from "vitest/config"
import { WxtVitest } from "wxt/testing/vitest-plugin"

// WxtVitest wires up WXT's auto-imports, path aliases and an in-memory
// `browser` (including storage), so tests run without Chrome.
export default defineConfig({
  plugins: [WxtVitest()],
  test: {
    environment: "happy-dom",
  },
})
