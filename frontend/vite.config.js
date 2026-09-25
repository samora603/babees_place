import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';
import { siteUrlSeoPlugin } from './vite.seoPlugin.js';

const REQUIRED_VITE_ENV = ['VITE_SUPABASE_URL', 'VITE_SUPABASE_ANON_KEY'];

export default defineConfig(({ mode }) => {
  // Vite only exposes VITE_* to the client. loadEnv merges .env* + process.env
  // (Vercel Project Settings inject process.env at build time).
  const env = loadEnv(mode, process.cwd(), 'VITE_');

  if (mode === 'production') {
    const missing = REQUIRED_VITE_ENV.filter((key) => !String(env[key] || '').trim());
    if (missing.length) {
      throw new Error(
        [
          `Missing required Vite env for production build: ${missing.join(', ')}.`,
          'Set these exact names in Vercel → Project Settings → Environment Variables',
          '(Production), with Root Directory = frontend. Do not use SUPABASE_URL /',
          'SUPABASE_ANON_KEY without the VITE_ prefix — Vite will not embed them.',
          'Use the public anon/publishable key only; never the service_role key.',
        ].join(' '),
      );
    }
  }

  return {
    plugins: [
      react(),
      siteUrlSeoPlugin(env.VITE_SITE_URL),
    ],
    resolve: {
      alias: {
        '@': path.resolve(__dirname, './src'),
      },
    },
    server: {
      port: 5173,
    },
    build: {
      sourcemap: mode !== 'production',
      chunkSizeWarningLimit: 700,
      rollupOptions: {
        output: {
          manualChunks: {
            react: ['react', 'react-dom', 'react-router-dom'],
            supabase: ['@supabase/supabase-js'],
            charts: ['recharts'],
            icons: ['react-icons/fi', 'react-icons/gi'],
          },
        },
      },
    },
  };
});
