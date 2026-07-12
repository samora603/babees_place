# Phase 0 — Remediation Plan

Author: Lead Software Architect / Principal Engineer
Date: 2026-07-12
Purpose: consolidate every finding into a single, dependency-aware remediation plan **before** further repository modifications.

> **Status disclosure (read first).** The Phase 0 *hygiene & documentation* changes were already applied in a prior working session:
> `.gitignore` repaired, `frontend/.gitignore` added, `frontend/.env` untracked + `.env.example` added, corrupted `04_Authentication.md` filename fixed, all empty docs populated, README/ENGINEERING/etc. synchronized, and the audit report set generated.
> Those items are marked **✅ ALREADY APPLIED**. Everything else is **⏳ PENDING** and requires approval before implementation (most are Phase 1 code/DB changes). No new repository changes are made by this plan except creating this file.

Evidence sources: `Phase0_Repository_Audit.md`, `Documentation_Audit.md`, `Dependency_Audit.md`, `Frontend_Health_Report.md`, `Supabase_Health_Report.md`, `Environment_Audit.md`, `Security_Baseline.md`, `Production_Readiness.md`, `Technical_Debt_Register.md`, plus the initial `PROJECT_AUDIT.md` set. Verified build (`npm run build` ✅) and lint (`npm run lint` ❌ no config). The **live Supabase project was not accessed** — remote facts are **UNVERIFIED**.

---

## 1. Complete Findings Register

Each finding: **Severity · Evidence · Root Cause · Risk · Recommended Fix · Files affected · Status.**

---

### F-01 — `profiles` UPDATE policy allows role self-escalation
- **Severity:** Critical
- **Evidence:** `supabase/migrations/001_schema_rls_place_order.sql:132-134` — `CREATE POLICY profiles_update_own ... FOR UPDATE USING (auth.uid() = id)` with **no `WITH CHECK`** and no column restriction. `AuthContext.updateProfile` / `userService.updateProfile` spread arbitrary fields into the update.
- **Root Cause:** RLS update policy written without column-level protection; `role` lives in the user-writable row.
- **Risk:** Any authenticated user can `update({role:'admin'})` and gain full admin access — defeats `AdminRoute`, `is_admin()`, and all admin-only policies.
- **Recommended Fix:** Add `WITH CHECK` forbidding role change (or revoke `UPDATE(role)` from `authenticated` and change roles only via a `SECURITY DEFINER` admin RPC).
- **Files affected:** new migration under `supabase/migrations/`; (optionally) `frontend/src/context/AuthContext.jsx`, `frontend/src/services/userService.js`.
- **Status:** ⏳ PENDING (Phase 1 — DB change; **manual confirmation required**).

### F-02 — Client-side order creation allows forged totals/prices
- **Severity:** High
- **Evidence:** `frontend/src/pages/Checkout.jsx:34-42` falls back to `orderService.createOrderFromCart` (`orderService.js:67-129`); RLS `orders_insert_own` / `order_items_insert_own` only check ownership, not amounts.
- **Root Cause:** A convenience fallback path bypasses the server-authoritative `place_order` RPC; RLS trusts client-supplied `total_amount`/`price`.
- **Risk:** Customer can create orders with arbitrary low totals / arbitrary prices → financial loss.
- **Recommended Fix:** Remove the fallback; make `place_order` the only write path; deny direct `orders`/`order_items` inserts from `authenticated`.
- **Files affected:** `frontend/src/pages/Checkout.jsx`, `frontend/src/services/orderService.js`, new migration (RLS tightening).
- **Status:** ⏳ PENDING (Phase 1).

### F-03 — Database schema not reproducible from migrations
- **Severity:** High
- **Evidence:** `supabase/migrations/20260617042152_remote_schema.sql` is **0 bytes**; migration `001` defines only `profiles/orders/order_items/cart`; code references `products, categories, wishlist, payments, pickup_locations, addresses`.
- **Root Cause:** Schema was built manually on the live project; a `db pull` was never completed.
- **Risk:** `supabase db reset` yields a broken app; RLS on 6 tables is unverifiable; no disaster recovery from source.
- **Recommended Fix:** Run `supabase db pull` (authenticated) to generate a baseline migration; review + commit; remove/replace the empty file. **Do NOT fabricate migrations.**
- **Files affected:** `supabase/migrations/` (new baseline), remove empty `20260617042152_remote_schema.sql`.
- **Status:** ⏳ PENDING (**requires project access + manual confirmation**).

### F-04 — No indexes on foreign keys / search columns
- **Severity:** High
- **Evidence:** No `CREATE INDEX` in any migration; queries use `orders.user_id`, `order_items.order_id`, `cart.product_id`, `products.category/slug/name`.
- **Root Cause:** Indexes never declared.
- **Risk:** Sequential scans; performance degrades with data volume.
- **Recommended Fix:** Add indexes on FKs + common filters; full-text search for products.
- **Files affected:** new migration (after F-03 baseline exists).
- **Status:** ⏳ PENDING (depends on F-03).

### F-05 — Site-wide layout bug (navbar/footer only on `/`)
- **Severity:** High
- **Evidence:** `frontend/src/App.jsx:50-59` renders `Navbar`/`Footer` only inside the `/` route; grep confirms no page renders them. Duplicate `<Route path="/">` at `:50` and `:61`.
- **Root Cause:** No shared layout wrapper; chrome hard-coded into the home route.
- **Risk:** No navigation/footer on any non-home page → broken UX across the app.
- **Recommended Fix:** Introduce a shared `<Layout>` with `<Outlet/>` wrapping public/protected groups; remove duplicate route.
- **Files affected:** `frontend/src/App.jsx` (+ possibly a new `components/layout/Layout.jsx`).
- **Status:** ⏳ PENDING (Phase 1).

### F-06 — Broken/dead source files
- **Severity:** Medium
- **Evidence:** `services/authService.js` contains Markdown fences (invalid JS); `services/api.js`, `lib/auth.js`, `hooks/useAuth.js`, `hooks/useCart.js`, `hooks/useWishlist.js`, `pages/ProductsPage.jsx`, `components/auth/OtpInput.jsx` have zero import references.
- **Root Cause:** Abandoned/duplicated code left in place.
- **Risk:** Confusion, drift, false sense of features (OTP); invalid file could be edited into the build.
- **Recommended Fix:** Delete after confirming no planned use (destructive — see §3).
- **Files affected:** the 8 files listed.
- **Status:** ⏳ PENDING (**manual confirmation — destructive**).

### F-07 — Missing `/placeholder.png` asset
- **Severity:** Medium
- **Evidence:** referenced in `CartContext.jsx`, `orderService.mapOrder`, `helpers.getPrimaryImage`; `ls public/` shows it absent.
- **Root Cause:** Asset never added.
- **Risk:** Broken fallback images in cart/wishlist/orders.
- **Recommended Fix:** Add `frontend/public/placeholder.png` (or change the fallback path).
- **Files affected:** `frontend/public/placeholder.png` (new binary asset).
- **Status:** ⏳ PENDING (needs a real image; **manual confirmation**).

### F-08 — Storage `getPublicUrl` mis-destructured
- **Severity:** Medium
- **Evidence:** `adminService.js:210` uses `{ publicURL }`; supabase-js v2 returns `{ data: { publicUrl } }`.
- **Root Cause:** API-shape drift from supabase-js v1→v2.
- **Risk:** Uploaded product images resolve to `undefined` URLs.
- **Recommended Fix:** Use `const { data:{ publicUrl } } = supabase.storage.from('products').getPublicUrl(path)`.
- **Files affected:** `frontend/src/services/adminService.js`.
- **Status:** ⏳ PENDING (Phase 1).

### F-09 — Services swallow errors; no Error Boundary; no env validation
- **Severity:** Medium
- **Evidence:** `productService.js:18-29,35-43` return `error:null`; no `<ErrorBoundary>`; `lib/supabaseClient.js` no env guard.
- **Root Cause:** Defensive coding that hides failures; missing global safety nets.
- **Risk:** Real failures render as empty states; render errors blank the app; missing env fails silently.
- **Recommended Fix:** Propagate errors; add Error Boundary; validate envs at client creation.
- **Files affected:** `frontend/src/services/productService.js` (+ others), new `components/ErrorBoundary.jsx`, `frontend/src/lib/supabaseClient.js`, `frontend/src/App.jsx`/`main.jsx`.
- **Status:** ⏳ PENDING.

### F-10 — Duplicate cart logic with inconsistent pricing
- **Severity:** Medium
- **Evidence:** `context/CartContext.jsx` (uses `discountPrice ?? price`) vs unused `hooks/useCart.js:43` (uses raw `price`).
- **Root Cause:** Two implementations; one abandoned.
- **Risk:** If the hook is ever used, cart totals diverge.
- **Recommended Fix:** Delete `hooks/useCart.js`; keep `CartContext` as the single source.
- **Files affected:** `frontend/src/hooks/useCart.js` (delete).
- **Status:** ⏳ PENDING (destructive — folded into F-06).

### F-11 — Categories model contradiction
- **Severity:** Medium
- **Evidence:** `productService.getCategories` derives categories from `products.category` text; `adminService` has `createCategory/updateCategory/deleteCategory` against a `categories` table.
- **Root Cause:** Two competing designs.
- **Risk:** No FK integrity; admin category CRUD may target a non-existent/unused table.
- **Recommended Fix:** Choose one model; if keeping `categories`, migrate `products.category` to a FK.
- **Files affected:** `frontend/src/services/{productService,adminService}.js`, migration.
- **Status:** ⏳ PENDING (depends on F-03).

### F-12 — Mixed identifier casing in DB (`"discountPrice"`)
- **Severity:** Medium
- **Evidence:** `001_...sql:194,214` reference `p."discountPrice"` alongside snake_case columns.
- **Root Cause:** Inconsistent naming convention.
- **Risk:** Fragile case-sensitive identifiers; violates project convention.
- **Recommended Fix:** Rename to `discount_price` (coordinated migration + code).
- **Files affected:** migration, `orderService.js`, `CartContext.jsx`, others referencing `discountPrice`.
- **Status:** ⏳ PENDING (depends on F-03).

### F-13 — `place_order` lacks row locking (oversell race)
- **Severity:** Medium
- **Evidence:** `001_...sql:182-191` iterates cart to check stock without `FOR UPDATE`.
- **Root Cause:** No pessimistic lock during checkout.
- **Risk:** Concurrent checkouts can oversell inventory.
- **Recommended Fix:** `SELECT ... FOR UPDATE` on product rows within the RPC.
- **Files affected:** migration (RPC redefinition).
- **Status:** ⏳ PENDING (depends on F-03).

### F-14 — No status/payment CHECK constraints; no `updated_at` trigger
- **Severity:** Low/Medium
- **Evidence:** `orders.status`/`payment_status` are free `TEXT`; `updated_at` set only manually in `adminService.updateOrderStatus`.
- **Root Cause:** Constraints/triggers not added.
- **Risk:** Invalid states possible; `updated_at` drifts.
- **Recommended Fix:** Add CHECK constraints/enums + a `BEFORE UPDATE` trigger.
- **Files affected:** migration.
- **Status:** ⏳ PENDING.

### F-15 — ESLint config missing → lint broken
- **Severity:** Medium
- **Evidence:** `npm run lint` → "ESLint couldn't find a configuration file"; it even scans `dist/`.
- **Root Cause:** `lint` script exists but no `.eslintrc`/flat config and no `.eslintignore`.
- **Risk:** No quality gate; DoD "no lint errors" unachievable.
- **Recommended Fix:** Add ESLint config + `.eslintignore`; wire into CI.
- **Files affected:** new `frontend/.eslintrc.cjs` (or `eslint.config.js`), `frontend/.eslintignore`.
- **Status:** ⏳ PENDING.

### F-16 — No tests / no framework
- **Severity:** High
- **Evidence:** no `*.test.*`/`*.spec.*`; no Vitest/Jest/Playwright in `package.json`.
- **Root Cause:** Testing never set up.
- **Risk:** No regression safety; the F-01 flaw would have been caught by a policy test.
- **Recommended Fix:** Add Vitest+RTL, Playwright, and RLS/policy tests; CI gate.
- **Files affected:** `frontend/package.json`, new test config + test files, CI workflow.
- **Status:** ⏳ PENDING.

### F-17 — No CI/CD, monitoring, logging, backups
- **Severity:** High
- **Evidence:** no `.github/`; 28 `console.*`; no error tracking; no backup policy documented.
- **Root Cause:** Ops not established.
- **Risk:** Operational blindness; no automated gates.
- **Recommended Fix:** Add CI (lint/build/test), Sentry, log drains, verify PITR/backups.
- **Files affected:** new `.github/workflows/ci.yml`, monitoring config.
- **Status:** ⏳ PENDING.

### F-18 — Weak auth config + wrong redirect URLs
- **Severity:** Medium
- **Evidence:** `config.toml` `minimum_password_length=6`, no complexity, `enable_confirmations=false`, no captcha; `site_url=http://127.0.0.1:3000` but Vite runs on 5173; redirect uses `https://127.0.0.1:3000`; `project_id="frontend"`; `db.seed → ./seed.sql` absent.
- **Root Cause:** Defaults left in place / dev config not updated.
- **Risk:** Weak accounts; broken auth redirects; failed `db reset` seeding.
- **Recommended Fix:** Raise password policy, enable email confirmation/captcha, fix URLs/`project_id`, add or disable seed.
- **Files affected:** `supabase/config.toml` (+ optional `supabase/seed.sql`).
- **Status:** ⏳ PENDING.

### F-19 — Unused dependencies
- **Severity:** Low
- **Evidence:** `react-image-gallery` (0 imports); `axios` (only in dead `services/api.js`).
- **Root Cause:** Deps left after refactor.
- **Risk:** Bundle/attack surface, confusion.
- **Recommended Fix:** Remove with dead-code cleanup.
- **Files affected:** `frontend/package.json`, `frontend/package-lock.json`.
- **Status:** ⏳ PENDING (depends on F-06).

### F-20 — 28 `console.*` statements; no logger
- **Severity:** Low
- **Evidence:** `grep -rn "console\." src | wc -l` = 28.
- **Root Cause:** Debug logging left in.
- **Risk:** Log noise; possible info leak in prod.
- **Recommended Fix:** Remove or route through a logger util.
- **Files affected:** multiple `src/` files.
- **Status:** ⏳ PENDING.

### F-21 — Inconsistent service return shapes
- **Severity:** Medium
- **Evidence:** services variously return `{data:{data}}`, `{data:{items}}`, `{data:{products}}`, `{order}`.
- **Root Cause:** Organic growth without a contract.
- **Risk:** Harder maintenance; call-site bugs.
- **Recommended Fix:** Define one service return contract; refactor incrementally.
- **Files affected:** `frontend/src/services/*`, call sites.
- **Status:** ⏳ PENDING.

### F-22 — Brand naming inconsistency (Babees vs Babis)
- **Severity:** Low
- **Evidence:** docs "Babees"; `package.json` `babis-place-frontend`, `Login.jsx`, migration header "Babis" (5 hits).
- **Root Cause:** Name change not propagated.
- **Risk:** Cosmetic/branding inconsistency.
- **Recommended Fix:** Pick canonical brand; align code + docs.
- **Files affected:** `frontend/package.json`, `Login.jsx`, migration comment, docs.
- **Status:** ⏳ PENDING (README note already added).

### F-23 — Tooling committed inside app tree
- **Severity:** Low
- **Evidence:** `frontend/.agents/` (40 tracked files) + `skills-lock.json`; `frontend/.qodo/` (untracked).
- **Root Cause:** AI tool artifacts stored in app.
- **Risk:** Repo bloat; unclear ownership.
- **Recommended Fix:** Relocate out of `frontend/` or ignore.
- **Files affected:** `frontend/.agents/`, `frontend/skills-lock.json`, `.gitignore`.
- **Status:** ⏳ PENDING (**manual confirmation — moving tracked files**).

### F-24 — Empty `docs/` subdirectories
- **Severity:** Low
- **Evidence:** `find docs -type d -empty` → `operations`, `prompts`, `references`, `testing`.
- **Root Cause:** Placeholder dirs created but unused (Git omits empty dirs).
- **Risk:** Clutter/confusion.
- **Recommended Fix:** Populate, add `.gitkeep`, or remove.
- **Files affected:** the 4 dirs.
- **Status:** ⏳ PENDING.

### F-25 — No diagrams / onboarding / deployment runbook / data-model ADRs
- **Severity:** Medium
- **Evidence:** no C4/ERD/sequence diagrams; DECISIONS.md ADR-014 folder list stale; no setup runbook beyond README.
- **Root Cause:** Documentation not yet produced.
- **Risk:** Slower onboarding; architecture not communicated.
- **Recommended Fix:** Add diagrams + onboarding + deployment runbook + data-model ADRs.
- **Files affected:** `docs/architecture/`, `docs/DECISIONS.md`, new onboarding doc.
- **Status:** ⏳ PENDING.

---

### Already-applied Phase 0 items (for the record)

| Ref | Item | Evidence of completion |
|---|---|---|
| A-01 | Root `.gitignore` (was a directory) → real file | `stat` → `regular file`; `git check-ignore` works |
| A-02 | `frontend/.gitignore` added | file present |
| A-03 | `frontend/.env` untracked + ignored; `.env.example` added | not in `git ls-files`; `git check-ignore` passes |
| A-04 | Corrupted `04_Authentication.md` filename fixed | proper file present; no newline in name |
| A-05 | 9 empty docs populated | `find docs -type f -empty` → none |
| A-06 | README/ENGINEERING/ARCHITECTURE/CODING_STANDARDS/AI_COLLABORATION/CHANGELOG synced | edits applied |
| A-07 | Audit report set generated | files present in `docs/audits/`, `docs/architecture/` |

---

## 2. Dependency-Aware Execution Order (for the PENDING work)

> Phase 0 hygiene/docs (A-01…A-07) are done. The order below sequences the remaining (Phase 1) work.

**Step 1 — Establish the safety net (no behavior change).**
Add ESLint config + `.eslintignore` (F-15); add test framework scaffolding (F-16). *Why first:* every subsequent change is safer with a lint gate and a place to add regression tests. Non-destructive, no runtime impact.

**Step 2 — Make the database reproducible (read-only pull first).**
`supabase db pull` baseline (F-03). *Why here:* almost every DB fix (F-04, F-11, F-12, F-13, F-14) and RLS verification depends on having the true schema in version control. This is *read* from the live DB, not a write, so it is safe and unblocks the rest.

**Step 3 — Fix the Critical security flaws (DB writes, guarded).**
F-01 (role escalation) then F-02 (order integrity). *Why here:* they are launch blockers and now have a committed schema to modify against; doing them right after the baseline avoids re-deriving policies. These are the highest-risk *and* highest-value changes, so they get dedicated focus with tests from Step 1.

**Step 4 — Backend hardening on top of the baseline.**
F-04 indexes, F-13 locking, F-14 constraints/trigger, F-11 categories decision, F-12 casing, F-18 auth/config. *Why here:* all depend on Step 2's schema and benefit from Step 3's security model being settled.

**Step 5 — Frontend correctness & cleanup.**
F-05 layout, F-08 getPublicUrl, F-09 error handling/boundary/env, F-07 placeholder asset, then dead-code/deps removal F-06/F-10/F-19, F-20 console, F-21 service contract. *Why here:* purely client-side; safe once the backend contract is stable. Dead-code deletion goes last within this step so nothing being refactored is accidentally removed early.

**Step 6 — Ops & docs.**
F-17 CI/monitoring/backups, F-25 diagrams/onboarding/ADRs, F-22 brand, F-23 tooling relocation, F-24 empty dirs. *Why last:* CI should encode the now-passing lint/tests/build; docs/diagrams should describe the *stabilized* system, not a moving target.

**Overall rationale:** tooling → truthful schema → critical security → backend hardening → frontend → ops/docs. Each step only depends on earlier steps, destructive actions are deferred until the code around them is finalized, and the two Critical items are fixed early but only after the schema is safely in version control.

---

## 3. Potentially Destructive Changes (DO NOT perform without approval)

| Action | Finding | Why destructive | Safeguard |
|---|---|---|---|
| Delete dead files (`authService.js`, `api.js`, `lib/auth.js`, `hooks/useAuth|useCart|useWishlist.js`, `ProductsPage.jsx`, `OtpInput.jsx`) | F-06, F-10 | Irreversible removal of tracked source; could hide intended future work (OTP) | Confirm no planned use; do in one reviewable commit; recoverable via Git history |
| Remove/replace empty `20260617042152_remote_schema.sql` | F-03 | Deleting a (empty) migration file; migration edits are sensitive | Only after `db pull` produces a real baseline |
| Any new migration touching RLS/`place_order`/columns | F-01, F-02, F-04, F-12, F-13, F-14 | DB schema/policy changes affect the **live** project | Requires backup, staging test, explicit approval; run via reviewed `db push` |
| Rename `"discountPrice"` → `discount_price` | F-12 | Coordinated DB+code rename; breaks if partially applied | Single coordinated PR + tests |
| Remove unused deps + regenerate lockfile | F-19 | Changes `package-lock.json`; transitive resolution shifts | Verify build after removal |
| Move tracked tooling (`.agents/`, `skills-lock.json`) | F-23 | Relocating tracked files | Confirm nothing references them |
| Rewrite `DECISIONS.md` ADR-014 folder list | F-25 | Editing a historical ADR record | Prefer appending a correction note over rewriting history |
| (Optional) Rotate anon key / scrub Git history | Env | History rewrite is irreversible & disruptive | Only if desired; coordinate with all clones |

**Already-performed actions that were destructive-in-nature (prior turn, applied):** removing the empty `.gitignore` directory, deleting the 0-byte malformed `04_Authentication.md\n`, `git rm --cached frontend/.env`, and rewriting `CHANGELOG.md`. All were reversible (Git history / files kept on disk) and are noted here for completeness.

---

## 4. Items Requiring Manual Confirmation Before Proceeding

1. **F-03 `supabase db pull`** — needs someone authenticated to project `qfcygrxrfszcdltangec`; I cannot access the live project. **Confirm who runs it** and that a DB backup exists first.
2. **F-01 / F-02 and all migrations (Step 3–4)** — changes to the **live** database. Confirm: backup taken, staging/test path, and approval to `db push`.
3. **F-06 dead-file deletion** — confirm OTP (`OtpInput`/`authService`) and `ProductsPage` are truly abandoned and not planned.
4. **F-07 placeholder image** — confirm you want a generated/placeholder PNG or a specific asset; I will not create binary assets without approval.
5. **F-19 dependency removal** — confirm `react-image-gallery`/`axios` won't be used soon.
6. **F-22 brand rename** — confirm the canonical name (Babees vs Babis) before touching `package.json`/UI.
7. **F-23 tooling relocation** — confirm whether `.agents/` should stay, move, or be ignored.
8. **Optional anon-key rotation / history scrub** — confirm if desired (public key → low priority).

---

## 5. Estimates

> Scope = the **remaining PENDING** work (F-01…F-25). Prior-turn Phase 0 items are already done.

| Metric | Estimate | Notes |
|---|---|---|
| Files to **modify** | ~22–30 | `App.jsx`, `Checkout.jsx`, `orderService.js`, `adminService.js`, `productService.js`, `supabaseClient.js`, `config.toml`, `package.json`, several `src/` files for `console.*`/service-contract, `DECISIONS.md`, etc. |
| **New** files | ~12–18 | baseline migration + hardening migrations (several), ESLint config, `.eslintignore`, test config + initial tests, `ErrorBoundary.jsx`, `Layout.jsx`, `public/placeholder.png`, `.github/workflows/ci.yml`, diagrams/onboarding docs |
| **Deleted** files | ~8–10 | 8 dead source files (F-06/F-10), empty `remote_schema.sql`, possibly 4 empty `docs/` dirs |
| Estimated time | **~6–9 weeks** (one focused engineer) | Step 1 ~3–4 d · Step 2 ~1–2 d · Step 3 ~3–5 d · Step 4 ~1–1.5 wk · Step 5 ~1 wk · Step 6 ~1.5–2 wk incl. payments/monitoring |
| Overall project risk | **High** (until F-01/F-02/F-03 land), then **Medium** | Live-DB changes and security fixes dominate risk; frontend/docs work is low risk |

### Per-step risk
| Step | Risk | Reason |
|---|---|---|
| 1 Safety net (lint/tests) | Low | Non-runtime |
| 2 `db pull` baseline | Low–Med | Read-only pull, but must match live exactly |
| 3 Critical security | **High** | Live RLS/policy + checkout flow changes |
| 4 Backend hardening | Med | Migrations on live DB |
| 5 Frontend | Low–Med | Client-only; dead-code deletion is the main risk |
| 6 Ops & docs | Low | Additive |

---

## 6. Go/No-Go

**Recommended sequence to begin (after approvals in §4):** Step 1 (safety net) can start immediately with **no destructive actions** and is a safe first move. Steps 2–3 must wait for explicit confirmation on live-DB access and a backup.

**Do not begin Steps 2–6 until:** (a) manual confirmations in §4 are granted, and (b) a database backup / staging path is confirmed for all migration work.

This plan supersedes ad-hoc fixes; implementation should follow the execution order in §2, one reviewable change-set per step.
