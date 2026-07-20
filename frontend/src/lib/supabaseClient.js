import { createClient } from '@supabase/supabase-js';

/**
 * Vite injects only VITE_* vars from .env / CI / host env at build & test time.
 * Never put the service_role key here — browser clients use the public anon key only.
 *
 * Required names (must match local `.env`, CI, and Vercel exactly):
 *   VITE_SUPABASE_URL
 *   VITE_SUPABASE_ANON_KEY
 */
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    [
      'Missing Supabase environment variables.',
      'Required: VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.',
      'Local: copy frontend/.env.example → frontend/.env.',
      'Vercel: Project Settings → Environment Variables (same exact names, Production).',
      'Vite does not embed SUPABASE_URL / SUPABASE_ANON_KEY without the VITE_ prefix.',
    ].join(' '),
  );
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});

export default supabase;
