import tailwindcss from "@tailwindcss/vite"
import { defineConfig } from "wxt"

export default defineConfig({
  srcDir: "src",
  // Visible folder (not .output) so it shows up in Chrome's "Load unpacked" dialog.
  outDir: "dist",
  modules: ["@wxt-dev/module-react"],
  manifest: {
    name: "Stash for X",
    description: "Save X posts to your private Stash library.",
    permissions: ["storage", "alarms"],
    // The Stash Mac app's local endpoint (see src/lib/sync.ts).
    host_permissions: ["http://127.0.0.1/*"],
  },
  vite: () => ({
    plugins: [tailwindcss()],
  }),
})
