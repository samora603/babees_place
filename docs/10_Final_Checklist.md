# Final / Release Checklist

Status: Starter content populated during Phase 0. This is the pre-release gate; it is **not yet satisfiable** (see notes). Cross-references: `docs/audits/Production_Readiness.md`.

Legend: ✅ done · ❌ not done · 🟡 partial

---

## Security
- ❌ `profiles` role-escalation RLS fixed (C-1)
- ❌ Client-side order creation removed; totals server-computed (H-1)
- ✅ `.env` untracked and git-ignored; `.env.example` present (Phase 0)
- ✅ No service-role key in client (verified anon key)
- ❌ RLS verified on every table
- ❌ Storage bucket policies verified
- ❌ Auth hardening (password length ≥ 8, email confirmation, captcha)

## Database
- ❌ Baseline migration generated (`supabase db pull`); schema reproducible
- ❌ Indexes on all FKs + search columns
- ❌ Status/payment CHECK constraints
- ❌ `updated_at` trigger

## Frontend
- ✅ Production build passes
- ❌ `npm run lint` passes (needs ESLint config)
- ❌ Shared layout (navbar/footer on all pages); duplicate `/` route removed
- ❌ `/placeholder.png` added; `getPublicUrl` bug fixed
- ❌ Dead/broken files removed or fixed
- ❌ Error Boundary + real error states

## Testing
- ❌ Unit tests (Vitest)
- ❌ RLS/policy tests
- ❌ E2E happy paths (Playwright)
- ❌ CI runs lint + tests + build

## Deployment / Ops
- ❌ Hosting + deploy config
- ❌ Env separation (dev/staging/prod)
- ❌ Monitoring (error tracking)
- ❌ Logging strategy (remove `console.*`)
- ❌ Backups / PITR verified
- ❌ Payments integrated + verified server-side

## Documentation
- ✅ Technical docs populated (Phase 0)
- 🟡 README/architecture synchronized (Phase 0)
- ✅ Audit reports produced

---

**Gate rule:** do not tag a production release until every Security and Database item above is ✅ and CI is green.
