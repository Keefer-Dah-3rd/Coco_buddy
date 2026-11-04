import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// One self-contained script for any website (Semplice/WordPress included): React, Coco,
// her styles and her barks all inside dist/embed/coco-embed.js. It mounts into every
// element with a `data-coco` attribute.
export default defineConfig({
  plugins: [react()],
  define: { "process.env.NODE_ENV": JSON.stringify("production") },
  build: {
    outDir: "dist/embed",
    emptyOutDir: true,
    assetsInlineLimit: Number.MAX_SAFE_INTEGER,
    lib: {
      entry: "src/embed.tsx",
      name: "CocoEmbed",
      formats: ["iife"],
      fileName: () => "coco-embed.js",
    },
  },
});
