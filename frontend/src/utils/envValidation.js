/**
 * Environment validation helpers (CI + boot).
 * Never requires secrets beyond public Vite vars.
 */

const REQUIRED = ['VITE_SUPABASE_URL', 'VITE_SUPABASE_ANON_KEY'];

export function validateClientEnv(env = import.meta.env) {
  const missing = REQUIRED.filter((key) => !env[key]);
  const warnings = [];

  if (env.VITE_SUPABASE_ANON_KEY && /service_role/i.test(String(env.VITE_SUPABASE_ANON_KEY))) {
    warnings.push('VITE_SUPABASE_ANON_KEY looks like a service_role key — remove immediately');
  }

  return {
    ok: missing.length === 0 && warnings.length === 0,
    missing,
    warnings,
  };
}

/** Soft rate-limit helper for future API wrappers (client-side debounce token bucket). */
export function createRateLimiter({ max = 20, windowMs = 60_000 } = {}) {
  const hits = [];
  return {
    allow() {
      const now = Date.now();
      while (hits.length && now - hits[0] > windowMs) hits.shift();
      if (hits.length >= max) return false;
      hits.push(now);
      return true;
    },
    remaining() {
      const now = Date.now();
      while (hits.length && now - hits[0] > windowMs) hits.shift();
      return Math.max(0, max - hits.length);
    },
  };
}
