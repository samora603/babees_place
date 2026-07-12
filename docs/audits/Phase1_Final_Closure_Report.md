# Phase 1 — Final Closure Report (Stabilization Hand-off)

**Project:** Babees Place (code/brand renders as "Babis Place")
**Live Supabase project:** `qfcygrxrfszcdltangec` ("Babis-place", eu-central-1, Postgres 17.6, ACTIVE_HEALTHY)
**Date:** 2026-07-12
**Author:** Lead Software Architect / Principal Engineer (AI-assisted)
**Guardrails honored:** No new features. No redesign. **No changes applied to the live database.** No commits. No deploys.

---

## Executive Summary

Repository-side stabilization is complete and all local quality gates pass
(`npm ci`, `lint`, `test`, `build`). However, **live verification during this
closure surfaced a blocking, previously-hidden finding**: the live Supabase
database does **not** match the repository migrations or several of the
frontend's schema assumptions. The live DB was built manually and has **no
migration history**.

Because of this, the two Phase 1 database migrations (`002`, `003`) **cannot be
applied to the live project as written**, and the Critical role-escalation
vulnerability (C-1) **remains live**. A live-compatible fix is provided in
[Manual Steps](#manual-steps).

**Verdict:** Phase 1 is **CLOSED at the repository level** but **NOT production-ready**.
A short **database reconciliation gate** must be completed (by a human with prod
access) before Phase 2 feature work begins. This report documents exactly what
was verified, what could not be, and the precise manual commands to finish.

---

## Security Status

| Control | Repo (verified) | Live (verified 2026-07-12) |
|---|---|---|
| Anon-key only in frontend | ✅ | ✅ (management API confirms project) |
| Role escalation (C-1) | Client strips `role`; DB fix authored | 🛑 **OPEN** — `profiles` UPDATE policy has USING, **no `WITH CHECK`** |
| Order-total forgery (H-1) | ✅ client fallback removed; RPC-only | ⚠️ Live has **no `place_order()`**; `order_items` INSERT is blocked by policy `WITH CHECK (false)`; `orders` INSERT allowed to owner |
| Admin authorization | `AdminRoute` + intended `is_admin()` | ⚠️ Live policies inline `role = 'admin'`; **`is_admin()` absent**; `profiles.role` default is `'customer'` |
| Customer authorization (own rows) | ✅ | ✅ orders/order_items/profiles scoped to owner |
| RLS on all tables | ✅ (idealized) | ✅ enabled on all 7 tables — but `cart_items`, `categories`, `wishlists` have **no policies → deny-all** |
| Storage policies | n/a in repo | ❓ **Could not verify** (not in dump; needs dashboard) |
| Auth config (password/confirm/captcha) | n/a | ❓ **Could not verify** (needs dashboard) |

**Conclusion:** The critical live risk is C-1 (role self-escalation). It is
fixable with a small, live-compatible policy change (see Manual Steps). Frontend
defense-in-depth (never send `role`) is already merged, which mitigates the
common exploit path but is **not** a substitute for the DB `WITH CHECK`.

---

## Database Status

Live schema captured read-only via `supabase db dump --linked -s public`
(evidence retained locally at `/tmp/remote_public_schema.sql`; not committed).

**The live schema was built manually and diverges heavily from the repo.** Summary
(full table in `docs/technical/02_Database.md`):

- Tables: `cart_items` (not `cart`), `categories`, `order_items`, `orders`,
  `products`, `profiles`, `wishlists` (not `wishlist`).
- `orders.total` (repo/code expect `total_amount`); no `payment_status`, `note`, `updated_at`.
- `order_items`: no `image_url`, no `created_at`; direct INSERT blocked (`WITH CHECK false`).
- `products`: **composite PK `(id, name)`**, column `"Description"` (capital D), and
  **no** `stock` / `discountPrice` / `image_url` / `images` / `is_active`.
- `profiles`: **no `full_name`** (frontend writes it), `role` default `'customer'`,
  no `role` CHECK, no `updated_at`.
- **No functions** (`place_order`, `is_admin`, `handle_new_user` absent).
- **No triggers**, **no non-PK indexes**.

**Impact:** Multiple app flows cannot succeed against this DB unchanged (checkout
RPC missing; cart table name/columns differ; `products.stock`/`discountPrice`
missing; `profiles.full_name` missing). This is the highest-priority item for the
reconciliation gate.

---

## Migration Status

**Local migration files:** `001_schema_rls_place_order.sql` (idealized, hand-written),
`002_phase1_security_hardening.sql` (Phase 1), `003_phase1_indexes_constraints.sql`
(Phase 1), and `20260617042152_remote_schema.sql` (**0 bytes / empty**).

**Remote migration history:** **EMPTY** (`supabase migration list` shows no Remote
entries for 001/002/003). Nothing has been tracked/applied via migrations.

### Migration review (Workstream B)
| File | Ordering | Naming | Idempotency | RLS/Constraints/Triggers/RPC | Applies to live? |
|---|---|---|---|---|---|
| `001` | 1st | prefix `001_` ok | Partial (`IF NOT EXISTS`, guarded `DO` blocks) | Defines profiles/cart/orders/order_items RLS + `place_order`/`is_admin`/`handle_new_user` | 🛑 No — describes a schema the live DB never adopted |
| `002` | 2nd | ok | Uses `DROP POLICY IF EXISTS` / `CREATE OR REPLACE` (idempotent) | Fixes profiles `WITH CHECK`, drops order INSERT policies, adds `FOR UPDATE` to `place_order` | 🛑 No — references policies/columns/function not present live |
| `003` | 3rd | ok | `IF NOT EXISTS` / `NOT VALID` (idempotent) | Indexes, status CHECKs, `set_updated_at` triggers | 🛑 No — references `public.cart`, `orders.payment_status`, `profiles.updated_at` (absent live) |
| `20260617042152_remote_schema.sql` | 4th | timestamp | Empty | none | Empty artifact — should be removed or replaced by a real baseline |

**Rollback considerations:** none of the Phase 1 migrations include explicit
`DOWN` scripts (Supabase migrations are forward-only by default). For 002/003 the
practical rollback is to re-create the prior policy / drop the added index/constraint;
this is acceptable given they are not yet applied.

**Both 002 and 003 now carry a `🛑 DO NOT APPLY AS-IS` header** pointing here.

### Baseline strategy (documented, not executed)
Two viable paths — this is a **human decision**, so no baseline was fabricated:

- **Path A (recommended): adopt live as the source of truth.**
  1. `supabase db pull` → generates a real baseline from live.
  2. Delete/retire the fictional `001` and the empty `20260617042152` file.
  3. Re-author forward migrations (security + schema-completion) **against the real
     schema** (rename to `cart`/`wishlist` or adapt code; add `full_name`, `stock`,
     `discountPrice`, `payment_status`, `place_order()`, etc.).
- **Path B (destructive, NOT recommended): reshape live to match `001`.** Would drop/rename
  live tables and risk data loss. Only viable if the live data is disposable.

---

## Repository Status

- Structure matches intended architecture (frontend app + `supabase/` + `docs/`).
- Dead code removed; unused deps removed; ESLint/Prettier/EditorConfig/Husky configured.
- `.gitignore` correct; `.env` untracked; `.env.example` present.
- Residual: empty `20260617042152_remote_schema.sql`; `usePagination` retained-but-unused;
  site-wide layout bug (Navbar/Footer only on `/`) deferred (documented).

---

## Documentation Status

Synchronized to reflect verified reality this closure:
- `docs/technical/02_Database.md` — added the **verified live schema** table.
- `docs/03_Security.md` — corrected C-1 to **OPEN ON LIVE**; noted missing `place_order`.
- `supabase/migrations/002` & `003` — added `DO NOT APPLY AS-IS` headers.
- `README.md`, `docs/13_CODING_STANDARDS.md`, `docs/technical/09_Testing.md`,
  `docs/audits/Phase1_Stabilization_Report.md` — up to date from prior Phase 1 step.
- This report added.

Remaining doc debt: architecture diagrams, onboarding runbook, deployment runbook.

---

## Testing Status

`npm test` → **18 passed** (helpers, Button, and app-startup/routing/auth-entry smoke).
Playwright configured as opt-in e2e (not in the required gate). No service-layer or
RLS/policy tests yet (highest-value next target, blocked on the schema reconciliation).

---

## CI/CD Status

`.github/workflows/ci.yml` runs `npm ci → lint → test → build` on push/PR to
main/master and fails on any stage. Verified locally end-to-end:

| Stage | Result |
|---|---|
| `npm ci` | ✅ |
| `npm run lint` | ✅ 0 errors |
| `npm test` | ✅ 18 passed |
| `npm run build` | ✅ |

---

## Remaining Risks

| ID | Severity | Risk |
|---|---|---|
| C-1 | **Critical** | Role self-escalation **live** (profiles UPDATE has no `WITH CHECK`) |
| DB-DRIFT | **Critical** | Live schema ≠ repo/code; app flows broken; migrations not applicable |
| H-1 | High | No `place_order()` live + `order_items` INSERT blocked → checkout cannot complete server-side |
| H-3 | High | Storage bucket policies unverified |
| M-2 | Medium | Auth config (password policy, email confirmation, captcha) unverified |
| M-1/M-3 | Medium | No input/env validation |
| F-05 | Medium | Site-wide layout bug (Navbar/Footer only on `/`) |
| — | Low | Empty `20260617042152_remote_schema.sql`; brand naming Babis/Babees |

---

## Manual Steps

> These require a human with prod access. **Take a backup first** (Dashboard →
> Database → Backups, or `supabase db dump --linked -f backup.sql`).

### 1. Immediate, live-compatible Critical fix (C-1 role escalation)
Matches the **actual** live policy name and schema (safe to apply today):

```sql
-- Prevent users from changing their own role via the profiles UPDATE policy.
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile" ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND role = (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
  );

-- Optional: constrain role values (live currently allows any text; default 'customer').
-- ALTER TABLE public.profiles
--   ADD CONSTRAINT profiles_role_check CHECK (role IN ('customer','admin')) NOT VALID;
```

### 2. Reconcile migrations to reality (unblocks Phase 2)
```bash
supabase db pull                 # generate real baseline from live
# review the generated file; retire the fictional 001 and the empty 20260617042152
supabase migration list --linked # confirm history
supabase db diff --linked        # confirm no unexpected drift after reconciliation
```
Expected after reconciliation: `migration list` shows the baseline as applied on
Remote, and `db diff` reports no changes.

### 3. Dashboard verifications (cannot be checked from the repo)
- Storage: confirm the `products` bucket exists and its policies are least-privilege.
- Auth: set password min length/complexity, enable email confirmation, enable captcha.

---

## Technical Debt (Workstream F)

### Completed in Phase 1
- TD-8 ESLint config restored; lint passes.
- TD-19 Unused deps removed (`axios`, `react-image-gallery`).
- TD-9/TD-10 Dead files removed (authService, api.js, lib/auth, unused hooks, ProductsPage, OtpInput).
- TD-23 Test framework + smoke tests (Vitest/RTL/Playwright).
- TD-28 CI pipeline added.
- TD-2 (partial) Client-side order path removed (frontend); RPC-only checkout.
- Git hygiene / `.env` / `.gitignore` (Phase 0) confirmed.

### Remaining (re-prioritized with live evidence)
| ID | Item | Severity | Impact | Recommended phase | Effort |
|---|---|---|---|---|---|
| DB-DRIFT | Live schema ≠ repo/code | Critical | App flows broken; blocks everything | **Phase 1.5 gate (now)** | 3–5 d |
| TD-1 | C-1 role escalation live | Critical | Privilege escalation | **Now** (SQL above) | 15 min |
| TD-2 | Server-only order totals + `place_order()` on live | High | Integrity / broken checkout | Phase 1.5 | 1–2 d |
| TD-12 | Storage policy review | High | Data exposure | Phase 1.5 | 0.5 d |
| TD-21/22 | Auth config + `config.toml` (`project_id="frontend"`) | Medium | Account security | Phase 1.5 | 0.5 d |
| TD-13 | Input + env validation | Medium | Robustness | Phase 2 | 1–2 d |
| TD-7 | Site-wide layout bug | Medium | UX broken on most pages | Phase 2 | 0.5 d |
| TD-15/16 | Categories model / `discountPrice` casing | Medium | Consistency | Phase 2 | 1 d |
| TD-24 | Brand naming Babis/Babees | Low | Polish | Phase 2 | 0.5 d |

---

## Phase 2 Readiness Assessment (Workstream G)

Phase 2 = Core Commerce Completion. **Blocked** until the DB reconciliation gate is done.

| Domain | Ready? | Blocker |
|---|---|---|
| Products | ❌ | Live `products` lacks `stock`/`discountPrice`/`image_url`; composite PK `(id,name)` |
| Categories | 🟡 | Table exists; `products.category` (text) vs `category_id` (uuid) dual model unresolved |
| Search | ❌ | No FTS/index; depends on reconciled `products` |
| Wishlist | ❌ | Live `wishlists` has **no RLS policies** (deny-all); code expects `wishlist` |
| Cart | ❌ | Live `cart_items` has **no RLS policies** (deny-all) + name/column mismatch |
| Checkout | ❌ | **No `place_order()` on live**; `order_items` INSERT blocked; client fallback removed |
| Orders | 🟡 | Table + owner RLS exist; column names differ (`total` vs `total_amount`) |
| Inventory | ❌ | No `stock` column live |
| Admin | 🟡 | Guard + admin read/update policies exist; `is_admin()` absent; product-write RLS missing |

**Gate to enter Phase 2:** complete Manual Steps §1–§3, reconcile migrations
(Path A), align frontend services to the reconciled schema, and add RLS policies
for `cart_items`, `wishlists`, `categories`, and `products` writes.

---

## Final Engineering Score

| Category | Score | Justification |
|---|---:|---|
| Security | 4/10 | Frontend defense-in-depth done; **C-1 live-open**; storage/auth unverified |
| Database | 3/10 | Live built manually; heavy drift; no functions/indexes/triggers; app-incompatible |
| Migrations | 3/10 | Files exist but none applied; 001 fictional; 002/003 not live-applicable; empty baseline artifact |
| Repository | 8/10 | Clean structure, dead code/deps removed, tooling configured |
| Documentation | 8/10 | Synced to verified reality; diagrams/runbooks still missing |
| Testing | 6/10 | Smoke suite green; no service/RLS tests |
| CI/CD | 8/10 | Full lint/test/build gate; e2e opt-in only |
| Code Quality | 7/10 | Lint passes; 13 warnings; layout bug deferred |
| Production Readiness | 3/10 | Blocked by DB drift + live C-1 |
| **Overall (Phase 1 goals)** | **5/10** | Repo stabilized; **live not production-ready** pending reconciliation gate |

---

## Completion Criteria — Final Check

| Criterion | Status |
|---|---|
| No unresolved Critical findings | ❌ **C-1 open on live** + DB-DRIFT (both have exact manual fixes documented) |
| Repository builds | ✅ |
| Tests pass | ✅ (18) |
| Lint passes | ✅ |
| Documentation synchronized | ✅ |
| Migration strategy documented | ✅ (Path A/B, no fabrication) |
| Remaining live actions have exact manual commands | ✅ (Manual Steps §1–§3) |
| Phase 2 readiness documented | ✅ |

**Formal status:** Phase 1 **repository stabilization is COMPLETE**. Phase 1 is
**NOT fully closed for production** because two Critical items depend on live-DB
actions that (per the guardrails) must be executed by a human and were not guessed
or applied here. Completing the three Manual Steps closes Phase 1 and unblocks Phase 2.
