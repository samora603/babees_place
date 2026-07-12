# Phase 1 — Stabilization Report

**Project:** Babees Place (storefront brand rendered as "Babis Place" in code — see Remaining Risks)
**Phase:** 1 — Stabilization (Security, Database, Code Quality, Testing, CI/CD)
**Date:** 2026-07-12
**Author:** Lead Software Architect / Principal Engineer (AI-assisted)
**Scope guardrails honored:** No new customer-facing features. No architecture redesign. No changes pushed to any live database.

---

## Executive Summary

Phase 1 restored the project's engineering quality gates and fixed the critical
and high-severity security flaws **in code and in versioned migration files**.

- ✅ **Lint passes** (`npm run lint` → 0 errors).
- ✅ **Tests pass** (`npm run test` → 18 tests green: helpers, Button, routing/auth smoke).
- ✅ **Build passes** (`npm run build`).
- ✅ **CI/CD** workflow added (`.github/workflows/ci.yml`) running lint → test → build.
- ✅ **Critical/High security findings addressed**: role-escalation and order-integrity
  fixes are implemented in the frontend and in migrations `002`/`003`.
- ⚠️ **Two migrations require a human to apply them to the live database** (with a
  backup and a `supabase db pull` baseline first). They are intentionally **not**
  auto-applied. See "Manual Database Steps" below.

The single most important remaining action: **apply migrations 002 and 003 to the
live Supabase project** after taking a backup and generating the baseline. Until
then, the RLS/RPC hardening exists only in the repository, not in production.

---

## Workstream A — Security

### Summary
Addressed the Critical (F-01) and High (F-02, F-13) findings from the Phase 0
remediation plan. Frontend defense-in-depth is live in code; the authoritative
database-side controls are delivered as a reviewed, manual-apply migration.

- **F-01 (CRITICAL) role self-escalation** — `profiles_update_own` lacked a
  `WITH CHECK`, allowing a user to set `role = 'admin'` on their own row.
  - Migration `002` adds a `WITH CHECK` that forbids changing `role`, plus a
    separate `profiles_update_admin` policy so only existing admins can change roles.
  - Defense-in-depth: `AuthContext.updateProfile` and `userService.updateProfile`
    now strip `role`/`is_admin`/`id`/`created_at` from any client payload.
- **F-02 (HIGH) order-total forgery** — the client could insert `orders`/`order_items`
  directly with attacker-controlled prices/totals (and a client-side fallback existed).
  - `Checkout.jsx` now calls **only** the atomic `place_order()` RPC (no fallback).
  - `orderService.createOrderFromCart` (the insecure client path) was deleted.
  - Migration `002` removes the direct `INSERT` RLS policies on `orders`/`order_items`,
    so all order creation must flow through the server-validated RPC (which recomputes
    totals from current product prices).
- **F-13 (HIGH) checkout stock race** — `place_order()` did not lock product rows.
  Migration `002` adds `SELECT ... FOR UPDATE` on the cart's products before validating
  and decrementing stock.
- **Admin-only operations / customer authorization** — verified: `AdminRoute` +
  `is_admin()` in DB; `orders`/`order_items` reads remain owner-or-admin scoped.
- **Supabase Storage policies** — **could not be verified from the repository** (no
  storage config or policies are version-controlled). Documented as a manual review
  item; do not assume the `products` bucket is correctly locked down.

### Files changed
- `frontend/src/context/AuthContext.jsx` — strip privileged fields on update.
- `frontend/src/services/userService.js` — strip privileged fields on update.
- `frontend/src/pages/Checkout.jsx` — remove client-side order fallback.
- `frontend/src/services/orderService.js` — remove `createOrderFromCart`.
- `supabase/migrations/002_phase1_security_hardening.sql` — **new, manual-apply.**
- `docs/03_Security.md` — updated statuses + manual steps.

### Security considerations
- The RLS/RPC changes only take effect **after** migration 002 is applied to prod.
- Removing the direct INSERT policies is safe because `place_order()` is
  `SECURITY DEFINER` and bypasses RLS; legitimate checkout is unaffected.

### Testing performed
- Unit/smoke tests pass. The routing smoke test exercises the auth entry points.
- Order/RLS behavior itself is **not** covered by automated tests yet (needs a
  seeded Supabase test project / pgTAP) — tracked as a remaining risk.

### Remaining risks
- H-2: `products`, `wishlist`, `payments`, etc. are not in migrations; their RLS is
  **UNVERIFIED**. Requires `supabase db pull` + review.
- H-3: Storage bucket visibility/policies unverified.
- M-2: Weak auth config (password length/complexity, email confirmation, captcha) —
  dashboard + `config.toml` change.
- M-1/M-3: No input validation / env-var validation yet.

---

## Workstream B — Database

### Summary
The repository does **not** contain a complete baseline migration (only `001` plus
an empty remote-schema file). No baseline was fabricated. Reviewed the objects that
*are* versioned and authored a manual-apply migration for indexes, constraints, and
an `updated_at` trigger.

- **Baseline generation** — documented (`supabase db pull`) in
  `docs/technical/02_Database.md` and `docs/audits/Supabase_Health_Report.md`.
  `products`/`wishlist`/`payments`/`addresses`/storage are live-only and must be
  captured before applying further migrations.
- **Indexes (F-04)** — migration `003` adds indexes on `orders(user_id)`,
  `orders(created_at)`, `orders(status)`, `order_items(order_id)`,
  `order_items(product_id)`, `cart(product_id)`. Product indexes + full-text search
  are provided as a **commented, deferred** block (require the baseline first).
- **Constraints (F-14)** — `NOT VALID` CHECK constraints on `orders.status` and
  `orders.payment_status` (won't fail on legacy rows; `VALIDATE` statements included
  as comments for after data cleanup).
- **Triggers** — shared `set_updated_at()` + triggers on `orders` and `profiles`
  (their `updated_at` columns were never maintained).
- **Foreign keys / naming** — reviewed. Note the mixed-case identifier
  `products."discountPrice"` (F-12) requires quoting; standardizing to
  `discount_price` is deferred to a later phase because it needs the live baseline
  and a coordinated code change.

### Files changed
- `supabase/migrations/003_phase1_indexes_constraints.sql` — **new, manual-apply.**
- `docs/technical/02_Database.md` — Phase 1 migration notes + baseline reminder.

### Remaining risks
- Migration `003` is not applied to prod.
- `discountPrice` casing and the categories-model contradiction (F-11) remain open.

---

## Workstream C — Code Quality

### Summary
Configured the full quality toolchain and removed confirmed-dead code.

- **ESLint** — `frontend/.eslintrc.cjs` (ESLint 8, recommended + react + react-hooks),
  `.eslintignore`. Fixed the 3 real errors surfaced (`react/no-unescaped-entities`
  in `NotFound.jsx`; `no-unsafe-finally` in `ProductDetail.jsx`). Lint passes with
  0 errors (13 non-blocking warnings remain and are tracked).
- **Prettier** — `.prettierrc.json` + `.prettierignore`; `format`/`format:check` scripts.
- **EditorConfig** — root `.editorconfig`.
- **Husky + lint-staged** — `.husky/pre-commit` runs `lint-staged` (config in
  `frontend/package.json`). Enable once with `git config core.hooksPath .husky`
  (git config was intentionally not modified by tooling).
- **Dead code removed (confirmed unused via reference search):**
  `services/authService.js` (broken + unused), `services/api.js` (legacy axios),
  `lib/auth.js`, `hooks/useAuth.js`, `hooks/useCart.js`, `hooks/useWishlist.js`,
  `hooks/useProducts.js` (only used by the dead page), `pages/ProductsPage.jsx`
  (unrouted), `components/auth/OtpInput.jsx` (unused). Removed the empty `auth/` dir.
- **Dead route removed** — duplicate `/` route in `App.jsx` (unreachable).
- **Unused dependencies removed** — `axios`, `react-image-gallery`.
- **Kept (intentionally):** `hooks/usePagination.js` (isolated, non-broken utility;
  documented as currently unused rather than removed).

### Files changed
- New config: `.editorconfig`, `frontend/.eslintrc.cjs`, `frontend/.eslintignore`,
  `frontend/.prettierrc.json`, `frontend/.prettierignore`, `.husky/pre-commit`.
- `frontend/package.json` — scripts, `engines`, `lint-staged`, dep removals.
- Deleted: the 9 dead files listed above.
- Edited: `frontend/src/pages/NotFound.jsx`, `frontend/src/pages/ProductDetail.jsx`,
  `frontend/src/App.jsx`.
- `docs/13_CODING_STANDARDS.md` — tooling status updated.

### Testing performed
- `npm run lint` → 0 errors. `npm run build` → success. `npm run test` → 18 passing.

### Remaining risks
- 13 `no-unused-vars` warnings remain (non-blocking); clean up incrementally.
- Site-wide layout bug (Navbar/Footer only on `/`) is **not** fixed here because a
  shared layout route touches app structure; deferred and documented (F-05 residual).

---

## Workstream D — Testing

### Summary
Established the testing foundation and added smoke coverage.

- **Vitest + React Testing Library + jsdom** — `frontend/vitest.config.js`,
  `src/test/setup.js`, and a reusable `src/test/supabaseMock.js`.
- **Smoke tests (18 assertions across 3 files):**
  - `src/utils/helpers.test.js` — currency/phone/discount/image helpers.
  - `src/components/ui/Button.test.jsx` — render, disabled-while-loading, click.
  - `src/test/routing.test.jsx` — **app startup + routing + auth entry points**
    (`/login`, `/register`, 404) with Supabase mocked.
- **Playwright** — `frontend/playwright.config.js` + `frontend/e2e/smoke.spec.js`.
  Opt-in (needs `npx playwright install` and `VITE_SUPABASE_*`); **not** in the
  required CI gate.

### Files changed
- New: `frontend/vitest.config.js`, `frontend/playwright.config.js`,
  `frontend/src/test/setup.js`, `frontend/src/test/supabaseMock.js`,
  `frontend/src/test/routing.test.jsx`, `frontend/src/utils/helpers.test.js`,
  `frontend/src/components/ui/Button.test.jsx`, `frontend/e2e/smoke.spec.js`.
- `frontend/.gitignore` — ignore `coverage/`, `playwright-report/`, `test-results/`.

### Remaining risks
- No service-layer or RLS/policy tests yet (highest-value next test targets).
- Playwright is unproven in CI (documented as opt-in).

---

## Workstream E — CI/CD

### Summary
Added `.github/workflows/ci.yml`: on push/PR to main/master it checks out, sets up
Node 20 with npm cache, runs `npm ci`, then `lint` → `test` → `build`. Any failing
stage fails the workflow. The build step uses placeholder `VITE_SUPABASE_*` env so
it never depends on real secrets.

### Files changed
- New: `.github/workflows/ci.yml`.

### Remaining risks
- Playwright e2e is not wired into CI (needs browsers + env/secrets).

---

## Manual Database Steps (REQUIRED — not performed by tooling)

> These affect the **live** Supabase project and were deliberately not executed.

1. **Back up** the project (Dashboard → Database → Backups, or `supabase db dump`).
2. **Generate the baseline:** `supabase db pull` — commit the resulting migration so
   `products`, `wishlist`, `payments`, `addresses`, storage, etc. are versioned.
3. **Review** `supabase/migrations/002_phase1_security_hardening.sql` and
   `003_phase1_indexes_constraints.sql`.
4. **Apply:** `supabase db push` (or paste into the SQL Editor). Order: 002 then 003.
5. After confirming existing `orders` rows conform, run the commented
   `VALIDATE CONSTRAINT` statements in 003.
6. In the dashboard, harden **Auth** settings (password policy, email confirmation,
   captcha) and review **Storage** bucket policies for `products`.
7. Re-test checkout and profile-update flows against the updated database.

---

## Completion Criteria

| Criterion | Status | Evidence |
|---|---|---|
| All Critical findings resolved or documented with manual steps | ✅ | F-01/F-02 fixed in code + migration 002; manual apply steps documented |
| Lint passes | ✅ | `npm run lint` → 0 errors |
| Tests pass | ✅ | `npm run test` → 18 passed |
| Build passes | ✅ | `npm run build` → success |
| Documentation synchronized | ✅ | README, 03_Security, 13_CODING_STANDARDS, technical/02 & 09 updated |
| Phase1_Stabilization_Report.md generated | ✅ | this document |

**Phase 1 status: COMPLETE in the repository.** Production is only fully hardened
once the Manual Database Steps above are executed by a human with prod access.

---

## Remaining Risks & Recommended Phase 2 Inputs

| ID | Severity | Item | Suggested owner action |
|---|---|---|---|
| H-2 | High | Untracked schema; RLS on `products`/`wishlist`/`payments` unverified | `supabase db pull`, review RLS |
| H-3 | High | Storage policies unverified | Review `products` bucket policies |
| — | High | Migrations 002/003 not applied to prod | Apply with backup |
| M-2 | Medium | Weak auth config | Dashboard + `config.toml` |
| M-1/M-3 | Medium | No input/env validation | Add zod + env guard |
| F-05 | Medium | Site-wide layout bug (Navbar/Footer only on `/`) | Introduce shared layout route (Phase 2) |
| F-11/F-12 | Medium | Categories model contradiction; `discountPrice` casing | Reconcile with baseline |
| F-22 | Low | Brand naming "Babis" vs "Babees" | Product decision, then normalize |
| — | Medium | No service/RLS tests | Add seeded Supabase test project |
