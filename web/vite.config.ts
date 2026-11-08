/// <reference types="vitest" />
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// One stable bundle (no content hashes) that every Quarto page includes:
// site/assets/app/app.js + app.css. Pages mount views via
// <div class="jt-mount" data-view="..."></div>.
export default defineConfig({
  plugins: [react()],
  base: "./",
  build: {
    outDir: "../site/assets/app",
    emptyOutDir: true,
    cssCodeSplit: false,
    sourcemap: false,
    rollupOptions: {
      input: "src/main.tsx",
      output: {
        entryFileNames: "app.js",
        assetFileNames: "app.[ext]",
        inlineDynamicImports: true,
      },
    },
  },
  test: { environment: "node" },
});
