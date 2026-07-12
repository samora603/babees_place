# Deployment — Technical Reference

Status: Starter content populated during Phase 0. Describes the **current** (minimal) state and the **target** process. No deployment pipeline exists yet.
Source of truth: `frontend/`, `supabase/config.toml`, repository state.

---

## 1. Current state (verified)
- Frontend build: `cd frontend && npm install && npm run build` → **succeeds** (Vite, ~1,013 modules).
- Env vars required: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` (see `frontend/.env.example`).
- Backend: hosted Supabase project (`ref: qfcygrxrfszcdltangec`, per `supabase/.temp/`).
- ❌ No CI/CD (`.github/` does not exist).
- ❌ No hosting/deploy config committed (no Vercel/Netlify/Docker).
- ❌ No monitoring, logging, or backup policy.
- ⚠️ Schema not fully in migrations (see `02_Database.md`).

## 2. Target deployment (recommended)

### Frontend (static SPA)
- Host: Vercel / Netlify / Cloudflare Pages.
- Build command: `npm run build` (root `frontend/`); output `dist/`.
- Inject `VITE_*` env vars at build time via host secrets (never commit `.env`).

### Backend (Supabase)
- Manage schema via committed migrations: `supabase db push` from CI.
- Generate the missing baseline first: `supabase db pull` (see `02_Database.md`).
- Configure Storage buckets + policies explicitly.
- Fix `config.toml` `site_url`/`additional_redirect_urls` to the real production/dev URLs.

## 3. Pre-deploy checklist (target — cf. `docs/10_Final_Checklist.md`)
- [ ] Production build passes with no errors.
- [ ] `npm run lint` passes (requires adding an ESLint config).
- [ ] No secrets committed; `.env` untracked; `.env.example` current.
- [ ] All tables have verified RLS; critical `profiles` policy fixed.
- [ ] Storage bucket policies reviewed.
- [ ] Env vars configured in host.
- [ ] Error tracking (e.g., Sentry) enabled.
- [ ] Backups / PITR enabled per Supabase plan.

## 4. Environment separation (recommended)
- Separate Supabase projects for `dev` / `staging` / `prod`, each with its own env vars.
- Never point a preview build at the production database.

## 5. Known gaps → see `docs/audits/Production_Readiness.md`.
