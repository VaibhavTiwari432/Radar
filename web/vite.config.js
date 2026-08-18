import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { resolve } from 'node:path';

export default defineConfig({
  plugins: [react()],
  // console.html is the only page. The replay/HiFi clients were retired to
  // trash/retired-web-clients-20260815/ (15 Aug 2026).
  build: {
    rollupOptions: {
      input: { console: resolve(__dirname, 'console.html') },
    },
  },
});
