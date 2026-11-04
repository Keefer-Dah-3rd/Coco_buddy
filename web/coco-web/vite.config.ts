import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The demo page (index.html). `npm run dev` serves it; `npm run build` writes dist/demo.
export default defineConfig({
  plugins: [react()],
  build: { outDir: "dist/demo", emptyOutDir: true },
});
