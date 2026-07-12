# Production Readiness Audit — Babees Place

Auditor roles: DevOps Engineer + QA Engineer
Date: 2026-07-12
Verdict: **NOT production ready.** Estimated **3 / 10**.

This document covers Part 8 (Testing) and Part 9 (Deployment).

---

## Part 8 — Testing audit

| Item | Status | Evidence |
|---|---|---|
| Unit test framework | ❌ None | No Vitest/Jest in `package.json` |
| Test files | ❌ None | No `*.test.*` / `*.spec.*` in `src/` |
| Integration / e2e | ❌ None | No Playwright/Cypress config |
| Test scripts | ❌ None | `package.json` scripts = dev/build/preview/lint only |
| Lint (as a quality gate) | ❌ Broken | `npm run lint` fails: "ESLint couldn't find a configuration file" |
| Manual test checklist | 🟡 Documented only | `README`/`ENGINEERING` list what to verify; `docs/technical/09_Testing.md` is **empty (0 bytes)** |

**Testing coverage: 0%.** The project's own Definition of Done ("No lint errors", "tested code") cannot currently be met because lint is non-functional and no automated tests exist.

### Critical areas lacking tests (highest risk first)
1. `place_order` RPC (checkout correctness, stock, totals).
2. RLS policies (especially the `profiles` role-escalation flaw — a test would have caught it).
3. Auth flows (login/register/session/route guards, admin gating).
4. Cart math (two implementations disagree on pricing).
5. Order mapping/history.

### Recommended testing strategy
- **Unit:** Vitest + React Testing Library for services (mock supabase-js), helpers (`formatCurrency`, `normalizePhone`, `discountPercent`), and context reducers.
- **Policy tests:** pgTAP or a seeded Supabase test project asserting RLS (e.g., a `user` cannot `UPDATE role`, cannot read others' orders).
- **Integration/e2e:** Playwright happy paths — browse → add to cart → checkout → order visible; admin login → manage product/order; and negative auth (non-admin blocked from `/admin`).
- **CI gate:** lint + unit + build must pass on every PR before any deploy.

---

## Part 9 — Deployment audit

| Area | Status | Notes |
|---|---|---|
| Build process | ✅ Works | `vite build` succeeds (verified) |
| Environment variables | ⚠️ Risky | Only `VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY`. `.env` is **committed**; **no `.env.example`** |
| Root `.gitignore` | ❌ Broken | It is an **empty directory**, not a file → no ignore rules (see SECURITY_AUDIT C-3) |
| Deployment config | ❌ Missing | No Vercel/Netlify/Docker config; `.vercel` exists only in the user's home dir, not the repo |
| CI/CD | ❌ Missing | No `.github/` (README references it, but it does not exist) |
| Supabase config | 🟡 Partial | `config.toml` present but `site_url`/redirect URLs wrong (localhost:3000 vs Vite 5173, `https` typo); `project_id="frontend"` |
| DB migrations | ❌ Incomplete | `products` + 5 tables not in migrations; `remote_schema.sql` empty → environment not reproducible |
| Storage | ❌ Unverified | `products` bucket used in code but not declared/verified; upload URL bug |
| Monitoring | ❌ None | No Sentry/APM/error tracking |
| Logging | ❌ Ad hoc | 28 `console.*` calls; no structured logging |
| Backups | ❌ Not addressed | No backup/restore policy documented (Supabase daily backups depend on plan — unverified) |
| Secrets management | ❌ Weak | Committed `.env`, broken ignore rules |
| Payments | ❌ Stub | `paymentService` is a local stub; no M-Pesa/PSP integration; no server-side verification |
| SSL/Domain | ❌ Not addressed | No domain/SSL config in repo |

### Release blockers (must fix before any production deploy)
1. **Fix the `profiles` privilege-escalation RLS flaw** (SECURITY_AUDIT C-1).
2. **Remove client-side order creation**; enforce server-computed totals (SECURITY_AUDIT H-1).
3. **Make the schema reproducible** — commit full migrations; prove RLS on all tables.
4. **Fix Git hygiene** — real `.gitignore`, untrack `.env`, add `.env.example`, rotate credentials if needed.
5. **Fix the site-wide layout bug** (no navbar/footer off home page — FRONTEND_AUDIT §2).
6. **Add `/placeholder.png`** and fix the storage `getPublicUrl` bug.
7. **Stand up CI** (lint + tests + build) and fix the ESLint config so lint runs.
8. **Real payments + monitoring/logging** before accepting money.

### Deployment target recommendation
- Frontend: static host (Vercel/Netlify/Cloudflare Pages) building `frontend/`, with env vars injected at build time (never committed).
- Backend: hosted Supabase; manage schema via committed migrations and `supabase db push` in CI.
- Add Sentry for frontend + Supabase log drains for backend; enable point-in-time recovery/backups per plan.
