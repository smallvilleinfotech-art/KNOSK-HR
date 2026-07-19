import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
  // Relative base so the built app works whether it's served at a domain
  // root (username.github.io) or a project subpath (username.github.io/repo/) —
  // GitHub Pages needs this, a plain "/" base is what causes 404s like
  // "GET /src/main.jsx" (that's also a sign the *unbuilt* source was
  // deployed instead of the dist/ output — see the deploy workflow).
  base: './',
  server: {
    host: true,
  },
})
