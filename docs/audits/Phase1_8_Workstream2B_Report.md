# Phase 1.8 — Workstream 2B: Execute Safe Forward Reconciliation Migrations

**Status:** ✅ COMPLETE — all approved migrations applied and validated
**Date:** 2026-07-12
**Branch:** `phase-1.7-reconciliation`
**Tag at start/end:** `v0.3.1-phase-1.7b-complete` (unchanged; no new tag created)
**Linked Supabase project:** live (via `--linked` / Management API)
**Scope of this workstream:** Apply **only** migrations `002`–`006` to the live database, one at a time, validating after each. `007`–`010` explicitly **not** executed.

---

## 1. Executive Summary

This was the **first workstream to perform live schema changes**. The five approved, non-destructive forward migrations (`002_additive_columns`, `003_functions_and_triggers`, `004_rls_and_security`, `005_integrity_constraints`, `006_storage_policies`) were applied to the linked Supabase project in order, each followed by immediate targeted validation. **Every migration succeeded on first attempt with zero errors and zero rollbacks.**

Key outcomes:

- **12 application columns** added (`002`) — products stock/pricing/images, order payment status, profile `full_name`, order-item snapshot fields.
- **4 server functions + 4 triggers** created (`003`); `place_order` locked down to `authenticated`/`service_role` only (anon/PUBLIC revoked — I-3 fix confirmed live).
- **Role-escalation vulnerability C-1 CLOSED** (`004`): `profiles_update_own` now enforces `WITH CHECK` that pins `role` to the stored value; deny-all tables (`cart_items`, `wishlists`, `categories`) made usable and secure; direct client `INSERT` on `orders` removed.
- **Erroneous defaults removed** (`005`): `gen_random_uuid()` on FK/id columns and the `+254…` phone literal cleared; `created_at` defaults set to `now()` on all six tables; user FKs added `NOT VALID`; quantity CHECKs added and validated.
- **`products` storage bucket created** (public) with 4 admin-scoped policies (`006`) — the bucket was entirely absent on live before this workstream.

Repository, frontend, and backend code are **unchanged**. Application gates all pass (**0 lint errors, 18/18 tests, successful build**).

**Migration history is now: `001`–`006` applied, `007`–`010` pending.**

---

## 2. Environment

| Item | Value |
|---|---|
| Repo path | `/home/samora/Desktop/babees_place` |
| Frontend path | `/home/samora/Desktop/babees_place/frontend` |
| Git branch | `phase-1.7-reconciliation` |
| Git tag @ HEAD | `v0.3.1-phase-1.7b-complete` |
| Working tree | Clean (only untracked prior-WS audit reports) |
| Supabase CLI | migrations applied via `supabase db query -f … --linked` + `supabase migration repair --status applied` |
| Execution method | Per-migration: execute file → record in history → validate (deliberately avoids `db push`, which would have applied `007`–`010` too) |

**Why not `supabase db push`?** `db push` applies *all* pending migrations (`002`–`010`) in one shot. To honor the strict "apply only `002`–`006`, one at a time" requirement, each migration file was executed individually via the Management API (`db query -f`, atomic `BEGIN…COMMIT`) and then recorded with `migration repair --status applied <n>`. This gives per-migration control and a validation gate between each step.

---

## 3. Backup Information

A complete logical backup of the `public` schema was taken **before any changes**.

| Property | Value |
|---|---|
| **Backup identifier** | **`pre_ws2b_20260712_183453`** |
| Location | `/tmp/babees_backups/` |
| Schema dump | `pre_ws2b_20260712_183453_schema.sql` (8,921 B) — `supabase db dump --linked -s public` |
| Data dump | `pre_ws2b_20260712_183453_data.sql` (2,140 B) — `supabase db dump --linked -s public --data-only` |
| Roles dump | `pre_ws2b_20260712_183453_roles.sql` (358 B) — `supabase db dump --linked --role-only` |
| Pre-change git commit | HEAD @ tag `v0.3.1-phase-1.7b-complete` |

> Note: All five migrations are non-destructive and individually reversible (each file documents its own `ROLLBACK` block). The tables are tiny/empty (max 4 rows), so this logical dump is a sufficient restore point. For production-grade recovery, the Supabase dashboard PITR/snapshot remains the authoritative mechanism.

---

## 4. Migration Timeline

| Order | Migration | Apply exit code | Execution time | Recorded (`repair`) | Validation | Rollback |
|---|---|---|---|---|---|---|
| 1 | `002_additive_columns.sql` | 0 | 5.59 s | ✅ `[002] => applied` | ✅ PASS | none |
| 2 | `003_functions_and_triggers.sql` | 0 | 11.14 s | ✅ `[003] => applied` | ✅ PASS | none |
| 3 | `004_rls_and_security.sql` | 0 | 9.80 s | ✅ `[004] => applied` | ✅ PASS | none |
| 4 | `005_integrity_constraints.sql` | 0 | 11.26 s | ✅ `[005] => applied` | ✅ PASS | none |
| 5 | `006_storage_policies.sql` | 0 | 7.32 s | ✅ `[006] => applied` | ✅ PASS | none |

All executions returned empty result sets (DDL success) with **no warnings and no errors**.

---

## 5. Validation After Each Migration

### 002 — Additive columns
Verified via `information_schema.columns`. All **12** expected columns present with correct defaults/nullability:

| Table | Columns |
|---|---|
| `profiles` | `full_name` (null), `updated_at` (NOT NULL, `now()`) |
| `orders` | `payment_status` (NOT NULL, `'pending'`), `note` (null), `updated_at` (NOT NULL, `now()`) |
| `products` | `stock` (NOT NULL, `0`), `discount_price` (null), `image_url` (null), `images` (NOT NULL, `'[]'::jsonb`), `is_active` (NOT NULL, `true`) |
| `order_items` | `image_url` (null), `created_at` (NOT NULL, `now()`) |

No unexpected objects created. Application still connects (validated at end via build/tests).

### 003 — Functions & triggers
- **Functions (4/4):** `is_admin` (SECURITY DEFINER), `handle_new_user` (SECURITY DEFINER), `place_order` (SECURITY DEFINER), `set_updated_at` (not definer — correct).
- **`place_order` ACL:** `{postgres=X, authenticated=X, service_role=X}` — **no `anon`, no PUBLIC `=X` entry**. Confirms I-3 fix (anon EXECUTE revoked) is live.
- **Triggers (4/4):** `on_auth_user_created` (auth.users), `set_orders_updated_at` (orders), `set_products_updated_at` (products), `set_profiles_updated_at` (profiles).

### 004 — RLS & security
- `profiles`: `profiles_select_own_or_admin` (SELECT), `profiles_update_own` (UPDATE, **WITH CHECK present**), `profiles_update_admin` (UPDATE, WITH CHECK), `profiles_insert_own` (INSERT).
- **C-1 closed** — `profiles_update_own` WITH CHECK body:
  `((auth.uid() = id) AND (role = ( SELECT p.role FROM profiles p WHERE (p.id = auth.uid()))))` → a user cannot change their own `role`.
- `cart_items`: `cart_items_all_own` (ALL, using+check). `wishlists`: `wishlists_all_own` (ALL, using+check).
- `categories`: `categories_select_public` (SELECT), `categories_modify_admin` (ALL).
- `products`: `products_write_admin` (ALL) + baseline `Allow public read access` retained.
- `orders`: direct owner `INSERT` policy removed (creation only via `place_order`); `Users can view own orders`, `Admins can view all orders`, `Admins can update orders` retained.
- `order_items`: `order_items_select_owner_or_admin` (SELECT owner-OR-admin) + baseline INSERT block retained.
- **RLS enabled = true on all 7 public tables.**

### 005 — Integrity constraints
- **Defaults removed** (now `null`): `cart_items.user_id/product_id`, `wishlists.user_id/product_id`, `orders.user_id`, `order_items.order_id/product_id`, `products.category_id`, `profiles.phone`.
- **`created_at` = `now()`** on `cart_items`, `orders`, `products`, `profiles`, `categories`, `wishlists`.
- **User FKs (NOT VALID)** — `convalidated=false` as designed: `orders_user_id_fkey`, `cart_items_user_id_fkey`, `wishlists_user_id_fkey` → `auth.users`.
- **Quantity CHECKs (validated)** — `convalidated=true`: `cart_items_quantity_check`, `order_items_quantity_check` (`quantity > 0`). VALIDATE succeeded because both tables are empty.

### 006 — Storage policies
- **Bucket `products` created** — `id=products`, `name=products`, `public=true` (was entirely absent on live).
- **4 storage.objects policies:** `products_public_read` (SELECT), `products_admin_insert` (INSERT, WITH CHECK), `products_admin_update` (UPDATE, using+check), `products_admin_delete` (DELETE).

---

## 6. Objects Created

**Columns (12):** see §5/002.
**Functions (4):** `public.is_admin()`, `public.handle_new_user()`, `public.set_updated_at()`, `public.place_order(uuid)`.
**Triggers (4):** `on_auth_user_created`, `set_profiles_updated_at`, `set_products_updated_at`, `set_orders_updated_at`.
**Policies (public, net-new/replaced):** `profiles_select_own_or_admin`, `profiles_update_own`, `profiles_update_admin`, `profiles_insert_own`, `cart_items_all_own`, `wishlists_all_own`, `categories_select_public`, `categories_modify_admin`, `products_write_admin`, `order_items_select_owner_or_admin`.
**Storage:** bucket `products` + policies `products_public_read`, `products_admin_insert`, `products_admin_update`, `products_admin_delete`.
**Constraints:** `orders_user_id_fkey`, `cart_items_user_id_fkey`, `wishlists_user_id_fkey` (FK, NOT VALID); `cart_items_quantity_check`, `order_items_quantity_check` (CHECK, validated).

## 7. Objects Modified

- **Column defaults changed** (see §5/005): FK/id defaults dropped; `phone` default dropped; six `created_at` defaults set to `now()`.
- **Policies replaced** (dropped old live-named policies, created canonical): profiles `Users can view/update/insert their own profile` → canonical `profiles_*`; `order_items` owner-only SELECT → owner-or-admin.
- **Policy removed:** `orders` `Users can insert own orders`.

## 8. RLS Changes

| Table | Before (live) | After |
|---|---|---|
| `profiles` | USING-only update (role escalation open) | WITH CHECK role-pinned; admin update; own-or-admin select |
| `cart_items` | deny-all (0 policies) | owner ALL |
| `wishlists` | deny-all (0 policies) | owner ALL |
| `categories` | deny-all (0 policies) | public SELECT + admin ALL |
| `products` | public read only | public read + admin write |
| `orders` | owner insert allowed | owner insert removed (place_order only) |
| `order_items` | owner-only SELECT | owner-or-admin SELECT; insert blocked |
| `storage.objects` | 0 policies | 4 `products_*` policies |

RLS remains **enabled** on all 7 public tables (and on `storage.objects`, which was already enabled).

## 9. Function Inventory (post-2B)

| Function | Language | Security | Notable ACL |
|---|---|---|---|
| `is_admin()` | sql STABLE | DEFINER | default (anon/auth/service) |
| `handle_new_user()` | plpgsql | DEFINER | default |
| `set_updated_at()` | plpgsql | INVOKER | default |
| `place_order(uuid)` | plpgsql | DEFINER | **authenticated + service_role only** (anon/PUBLIC revoked) |

## 10. Trigger Inventory (post-2B)

| Trigger | Table | Timing/Event | Function |
|---|---|---|---|
| `on_auth_user_created` | `auth.users` | AFTER INSERT | `handle_new_user()` |
| `set_profiles_updated_at` | `public.profiles` | BEFORE UPDATE | `set_updated_at()` |
| `set_products_updated_at` | `public.products` | BEFORE UPDATE | `set_updated_at()` |
| `set_orders_updated_at` | `public.orders` | BEFORE UPDATE | `set_updated_at()` |

## 11. Storage Inventory (post-2B)

| Item | Value |
|---|---|
| Bucket | `products` (public = true) |
| Policies | `products_public_read` (SELECT), `products_admin_insert` (INSERT), `products_admin_update` (UPDATE), `products_admin_delete` (DELETE) |

## 12. Constraint Inventory (added by 2B)

| Constraint | Type | Validated | Table |
|---|---|---|---|
| `orders_user_id_fkey` | FK → auth.users | ❌ (NOT VALID, by design) | orders |
| `cart_items_user_id_fkey` | FK → auth.users | ❌ (NOT VALID, by design) | cart_items |
| `wishlists_user_id_fkey` | FK → auth.users | ❌ (NOT VALID, by design) | wishlists |
| `cart_items_quantity_check` | CHECK (quantity>0) | ✅ | cart_items |
| `order_items_quantity_check` | CHECK (quantity>0) | ✅ | order_items |

Policy counts (post-2B): profiles 4, orders 3, categories 2, order_items 2, products 2, cart_items 1, wishlists 1, storage.objects 4.

---

## 13. Risks

- **NOT VALID FKs are not yet enforced against existing rows.** They enforce new/updated rows immediately. A manual `VALIDATE CONSTRAINT` step remains (after confirming zero orphans) — documented in `005` and the Phase 1.5 readiness report. WS2A confirmed 1 `auth.users` row without a profile, but that does not affect these three user FKs (which point *to* `auth.users`).
- **`handle_new_user()` inserts `role='customer'`**, while existing live data uses `admin`/`user`. This is harmless at apply time (function creation only) but role-vocabulary normalization is deferred to `007` (gated). New signups until `007` runs will create `customer`-role profiles; the app should be verified to tolerate this or `007` scheduled promptly.
- **`010` remains blocked by K-1** (its FTS index references `products.description`, which only exists after `008` renames `"Description"`). `010` must not be applied before `008`.
- **Gated migrations `007`–`009`** perform data mutation and structural changes (products PK change, column rename, dedupe) and require their own backup + validation workstream.

## 14. Remaining Work

- **Workstream 3+:** apply gated migrations in order — `007_data_normalization`, `008_structural_reconciliation`, `009_product_integrity`, then `010_performance_optimizations` (after `008`). Each requires a fresh backup and dedicated validation.
- **Manual post-step:** validate the three `NOT VALID` user FKs once orphan-free.
- **Optional:** resolve the pre-existing orphaned `category_id` on the single product (0 categories exist) as part of `007`/`009`.

## 15. Evidence

- Migration list (post-2B): `001`–`006` show version in both local and remote columns; `007`–`010` local-only.
- Function count query → 4; trigger count query → 4.
- Policy count query → public {profiles:4, orders:3, categories:2, order_items:2, products:2, cart_items:1, wishlists:1}, storage.objects:4.
- `pg_constraint` query → FKs `convalidated=false`, CHECKs `convalidated=true`.
- `storage.buckets` → `products`/public=true.
- Application gates (in `frontend/`): lint 0 issues; `vitest run` → 18/18 passed; `vite build` → built in 8.10 s.
- `git status` → no tracked file modifications; `git diff --stat` empty.

## 16. Commands Executed (representative)

```bash
# Pre-flight
git branch --show-current; git tag --points-at HEAD; git status --short
supabase migration list --linked

# Backup
supabase db dump --linked -s public            -f /tmp/babees_backups/pre_ws2b_<ts>_schema.sql
supabase db dump --linked -s public --data-only -f /tmp/babees_backups/pre_ws2b_<ts>_data.sql
supabase db dump --linked --role-only           -f /tmp/babees_backups/pre_ws2b_<ts>_roles.sql

# Per migration (002..006)
supabase db query -f supabase/migrations/00X_*.sql --linked
supabase migration repair --status applied 00X --linked
supabase db query --linked -o json "<targeted validation query>"

# Post
supabase migration list --linked
cd frontend && npm run lint && npm test && npm run build
git status --short && git diff --stat
```

---

## 17. Engineering Assessment

Execution was clean and deterministic: five migrations, five successes, zero errors, zero rollbacks, no unexpected objects. Each migration's stated intent was verified against live catalog state rather than assumed. The two most security-relevant outcomes are confirmed **live**:

1. **C-1 (role self-escalation) is closed** — `profiles_update_own` now carries a `WITH CHECK` that binds `role` to the stored value.
2. **`place_order` is no longer anon-executable** — ACL restricted to `authenticated`/`service_role`.

The live schema now matches the canonical target for everything achievable without data mutation or structural change. Deferred items (`007`–`010`) are correctly gated and their blockers (K-1, role vocabulary) are documented. The repository, frontend, and backend are untouched and all application gates pass.

## 18. GO / NO-GO for Workstream 3

**Recommendation: GO** — with the standard gated-migration precautions.

- ✅ `002`–`006` applied and validated; migration history consistent (local == remote for `001`–`006`).
- ✅ Live security posture materially improved (C-1 closed, place_order hardened, storage secured).
- ✅ Application still builds, lints clean, all tests pass; repo unchanged.
- ⚠️ Workstream 3 (gated `007`–`009`) **must** take a fresh backup, run pre-flight orphan/dedupe checks, and validate after each migration.
- ⚠️ `010` remains **blocked until `008`** (K-1) — do not reorder.

---

## Final Validation Checklist

- ✅ Live schema updated (`002`–`006`)
- ✅ Migration history updated (`001`–`006` applied)
- ✅ `002`–`006` applied
- ✅ `007`–`010` still pending
- ✅ Repository unchanged (no tracked diffs)
- ✅ Frontend untouched
- ✅ Backend untouched
- ✅ Lint passes (0 errors)
- ✅ Tests pass (18/18)
- ✅ Build succeeds

**STOP.** Workstream 3 is **not** started automatically.
