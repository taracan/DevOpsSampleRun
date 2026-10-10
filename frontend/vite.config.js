import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    // In dev, forward /api to the local backend so the browser sees one origin (same as CloudFront in prod).
    proxy: { "/api": "http://localhost:8000" },
  },
});
