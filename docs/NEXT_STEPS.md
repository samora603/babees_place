# Next Steps — Engineering Roadmap

Owner: Edwin Samora
Date: 2026-07-12
Basis: `docs/audits/` (PROJECT, SECURITY, FRONTEND, DATABASE, SUPABASE, PERFORMANCE, PRODUCTION_READINESS).
Aligned with the project's engineering standards (`ENGINEERING.md`, `AI_COLLABORATION.md`, `DECISIONS.md`): security-first, reproducible, documented, tested.

Effort key: **S** ≤ half-day · **M** ~1–2 days · **L** ~3–5 days.
Risk = likelihood/impact of the *change* itself.

---

## Sprint 1 (recommended focus): Security, integrity & reproducibility blockers

These are release blockers. Do them first, in order.

### CRITICAL

**1. Close the `profiles` privilege-escalation hole**
- Problem: `profiles_update_own` has no `WITH CHECK`; any user can `UPDATE role='admin'` on their own row.
- Why it matters: defeats all authorization (admin gating, admin-only order updates).
- Effort: **M** · Dependencies: none · Risk: Medium (touches auth) · Impact: Very High.
- Done when: a non-admin cannot change `role` (verified by a policy test); admin role changes only via a `SECURITY DEFINER` admin RPC or restricted column grants.

**2. Remove client-side order creation; trust only `place_order`**
- Problem: `Checkout.jsx` falls back to `createOrderFromCart`, and RLS lets the client set `orders.total_amount` and `order_items.price`.
- Why it matters: customers can fabricate cheap orders / arbitrary prices.
- Effort: **M** · Depends on: #1 mindset · Risk: Medium · Impact: Very High.
- Done when: order/item inserts are denied to `authenticated` directly; all checkout goes through the RPC (which also gets `FOR UPDATE` locking to stop oversell).

**3. Fix Git hygiene & secrets**
- Problem: root `.gitignore` is a *directory*; `frontend/.env` is committed; no `.env.example`.
- Why it matters: future secret leaks; build artifacts can be committed.
- Effort: **S** · Depends on: none · Risk: Low · Impact: High.
- Done when: real `.gitignore` (root + `frontend/`), `git rm --cached frontend/.env`, `.env.example` added, keys rotated if any private key was ever tracked.

### HIGH

**4. Make the database reproducible + verify RLS everywhere**
- Problem: only 4 tables in migrations; `20260617042152_remote_schema.sql` empty; `products/categories/wishlist/payments/pickup_locations/addresses` unversioned; their RLS unknown.
- Why it matters: no reproducible env, can't prove security, breaks `supabase db reset`.
- Effort: **L** · Depends on: none · Risk: Medium (must match live) · Impact: High.
- Done when: `supabase db pull` output committed, empty migration removed, every table has verified RLS, `config.toml` `site_url`/redirects/`project_id` corrected, `seed.sql` added or seeding disabled.

**5. Add database indexes + product search**
- Problem: no indexes; `ilike '%%'` search; `getCategories` full-table scan; client-side revenue aggregation.
- Why it matters: query performance degrades quickly with data.
- Effort: **M** · Depends on: #4 · Risk: Low · Impact: High.
- Done when: indexes on all FKs + `products(category, slug)`, full-text (`tsvector`+GIN) search, a `categories`/stats RPC replaces client scans.

---

## Sprint 2: Correctness, UX & tooling

### HIGH

**6. Fix the site-wide layout bug**
- Problem: `Navbar`/`Footer` render only inside the `/` route; every other page has no chrome; duplicate `/` route.
- Effort: **M** · Depends on: none · Risk: Low · Impact: High (usability).
- Done when: a shared `<Layout>` (Outlet) wraps public + protected routes; admin keeps `AdminLayout`; duplicate route removed.

**7. Remove dead/broken code & runtime bugs**
- Problem: `authService.js` (invalid JS), `services/api.js`, `lib/auth.js`, `hooks/useAuth|useCart|useWishlist`, `pages/ProductsPage.jsx`, `components/auth/OtpInput.jsx` are dead; `/placeholder.png` missing; `getPublicUrl` destructured wrong.
- Effort: **M** · Depends on: none · Risk: Low · Impact: Medium.
- Done when: dead files deleted, `/placeholder.png` added, storage upload returns real URLs, cart logic single-sourced in `CartContext`.

**8. Stop swallowing errors; add Error Boundary + env validation**
- Problem: `productService` returns `error:null` on failure; no boundary; no env guard.
- Effort: **M** · Risk: Low · Impact: Medium.
- Done when: services surface errors, pages show error states, a top-level Error Boundary exists, `supabaseClient` throws a clear message if envs are missing.

**9. Restore tooling & CI**
- Problem: `npm run lint` fails (no ESLint config, lints `dist/`); no CI.
- Effort: **M** · Depends on: none · Risk: Low · Impact: High (quality gate).
- Done when: ESLint flat/legacy config + `.eslintignore`, lint passes clean, `.github/workflows/ci.yml` runs lint + build (+ tests from #10) on PRs.

### MEDIUM

**10. Test baseline**
- Problem: zero tests.
- Effort: **L** · Depends on: #9 · Risk: Low · Impact: High.
- Done when: Vitest+RTL unit tests (services, helpers, cart math, guards), RLS policy tests (esp. role escalation & cross-user order reads), Playwright happy-path (browse→cart→checkout→order) + admin gating, all wired into CI.

---

## Sprint 3: Feature completion & launch prep

### MEDIUM

**11. Payments (M-Pesa) via Edge Function**
- Problem: `paymentService` is a stub; no `payments` table; no verification.
- Effort: **L** · Depends on: #4 · Risk: High (money) · Impact: High.
- Done when: STK push + callback verified server-side in an Edge Function, `payments` table with RLS, order `payment_status` updated only by the server.

**12. Finish checkout (delivery/pickup) + Admin Settings**
- Problem: `DELIVERY_TYPES`/pickup exist but checkout hardcodes "Free"; `AdminSettings` is a placeholder.
- Effort: **M** · Depends on: #4, #6 · Risk: Low · Impact: Medium.

**13. Reviews & notifications (if in scope)**
- Problem: only `StarRating` exists; notifications are toasts.
- Effort: **L** · Depends on: #4 · Risk: Low · Impact: Medium.

**14. Documentation sync**
- Problem: ~half of `docs/` empty; CHANGELOG/README inaccurate; broken refs; no diagrams.
- Effort: **M** · Depends on: features stabilizing · Risk: Low · Impact: Medium.
- Done when: technical docs (DB schema, Auth, API, Deployment, Testing) filled, ERD + architecture/sequence diagrams added, CHANGELOG/README corrected, brand name unified (Babees vs Babis), doc index added, `04_Authentication.md` filename fixed.

### LOW

**15. Performance polish**
- `manualChunks` vendor split; evaluate dropping `swiper`/`recharts` weight; TanStack Query cache; scope realtime subscriptions to the user; image optimization (WebP/`srcset`/dimensions/lazy).
- Effort: **M** · Risk: Low · Impact: Medium.

**16. Observability & backups**
- Sentry (frontend), Supabase log drains, verify PITR/backups per plan.
- Effort: **M** · Risk: Low · Impact: Medium.

**17. Auth hardening & cleanup**
- Password length ≥ 8 + complexity, email confirmation, captcha; remove 28 `console.*`; add a logger; consider TypeScript migration.
- Effort: **M** · Risk: Low · Impact: Medium.

---

## Suggested order of execution
`1 → 2 → 3` (security blockers) → `4 → 5` (reproducible, indexed DB) → `6 → 7 → 8 → 9` (correctness + tooling) → `10` (tests) → `11 → 12` (payments/checkout) → `14` (docs) → `13, 15, 16, 17` (enhancements/hardening).

**Target:** clear Sprints 1–2 to reach a secure, reproducible, testable MVP; Sprint 3 for launch readiness (~6–9 weeks total for one focused engineer).
