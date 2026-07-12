# Phase 0 — Production Readiness Baseline

Auditor: DevOps / QA Engineer
Date: 2026-07-12
Purpose: baseline assessment of production readiness at the close of Phase 0.
Companion (initial audit): `docs/audits/PRODUCTION_READINESS.md`.

**Verdict: NOT production ready — 3/10.** Phase 0 improved Git/secret hygiene and documentation but did not (by design) change application code or the database.

---

## Readiness matrix

| Dimension | Status | Evidence / notes |
|---|---|---|
| Configuration | 🟡 Partial | `.env.example` added; `config.toml` has wrong `site_url`/redirects (localhost:3000 vs Vite 5173) and `project_id="frontend"` |
| Build | ✅ Works | `npm run build` succeeds (verified) |
| Deployment | ❌ None | No host/deploy config; no `.github/` |
| CI/CD | ❌ None | No pipelines; lint gate broken (no ESLint config) |
| Environment separation | ❌ None | Single Supabase project; no dev/staging/prod split |
| Monitoring | ❌ None | No error tracking/APM |
| Logging | ❌ Ad hoc | 28 `console.*`; no structured logging |
| Backups | ❌ Unverified | No documented backup/PITR policy (depends on Supabase plan) |
| Error handling | 🟡 Partial | Loading/empty states exist; errors swallowed; no Error Boundary |
| Secrets management | ✅ Improved | `.env` untracked + ignored; only public anon key ever committed |
| DB reproducibility | ❌ Broken | Schema not in migrations; empty `remote_schema.sql` |
| Security | ❌ Blockers | Role escalation + order integrity open (see Security Baseline) |
| Payments | ❌ Stub | No real PSP; no server-side verification |
| Testing | ❌ None | 0 tests |

## Improved during Phase 0
- Git hygiene (real `.gitignore`, `frontend/.gitignore`).
- Secret handling (`.env` untracked/ignored, `.env.example`).
- Documentation completeness (all technical docs populated; structure synced).

## Release blockers (must clear before production)
1. Fix `profiles` role-escalation RLS (Security Baseline SB-1).
2. Remove client-side order creation; server-computed totals (SB-2).
3. `supabase db pull` → reproducible schema; verify RLS on all tables (SB-3).
4. Add ESLint config + CI (lint/build/tests must pass).
5. Fix site-wide layout bug (navbar/footer) + duplicate route.
6. Add `/placeholder.png`; fix storage `getPublicUrl`; verify bucket policies.
7. Real payments + server-side verification.
8. Monitoring + logging + verified backups.
9. Correct `config.toml` URLs; set up environment separation.

## Recommended deployment shape (target)
- Frontend → Vercel/Netlify/Cloudflare Pages, `frontend/` build, env via host secrets.
- Backend → hosted Supabase; schema via committed migrations + `supabase db push` in CI.
- Observability → Sentry (frontend) + Supabase log drains; enable PITR/backups per plan.

## Production readiness score: **3/10** (unchanged in substance; hygiene/docs improved, engineering blockers remain).
