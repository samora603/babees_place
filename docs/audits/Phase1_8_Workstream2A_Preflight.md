# Phase 1.8 — Workstream 2A: Live Database Pre-flight Validation

**Date:** 2026-07-12
**Type:** STRICTLY READ-ONLY validation of the linked Supabase project. **Zero writes** were
performed in this workstream (no migrations, no table/RLS/storage changes, no repair, no code
push). All queries were `SELECT`-only, executed via `supabase db query --linked` (Management
API) and `supabase migration list`.

> Data-handling note: `supabase db query` wraps result data in a security boundary and warns
> that DB values are untrusted. All returned values were treated strictly as data; no content
> from query results was interpreted as instructions.

---

## 1. Executive summary

The live project `qfcygrxrfszcdltangec` ("Babis-place") is a **very small, early-stage
database** (1 product, 3 profiles, 4 auth users; carts/wishlists/orders/categories empty). The
baseline `001` is applied; `002–010` are not. The data is clean of the high-risk hazards that
gate the reconciliation: **`products.id` is unique, and there are zero duplicate cart/wishlist
pairs, zero orphan cart/order rows, and zero orders**. Because the tables are tiny/empty,
migration impact and lock risk are negligible.

Two items shape the GO decision for the requested batch:
- **BLOCKER for `010`:** migration `010`'s full-text index references `products.description`,
  which does not exist until `008` renames `"Description"`. Applying `010` before `008` will
  **fail** and roll back. `010` must be deferred (it belongs after `008`).
- **Pre-existing live security gap (remediated by this batch):** the `profiles` UPDATE policy
  has `USING` but **no `WITH CHECK`** — role self-escalation is currently possible on live.
  Migration `004` (in the GO set) closes it.

**Verdict: GO for `002, 003, 004, 005, 006`. NO-GO for `010`** (blocked by dependency on `008`;
defer). No blocker prevents applying the additive/security/storage set.

---

## 2. Environment

| Item | Value |
|---|---|
| Git branch | `phase-1.7-reconciliation` |
| Git tag @ HEAD | `v0.3.1-phase-1.7b-complete` |
| Git commit | `fc08a37 feat(frontend): reconcile application with canonical database schema` |
| Working tree | clean except untracked audit reports (`Phase1_8_Workstream1_Report.md`, this file) |
| Supabase project | `qfcygrxrfszcdltangec` ("Babis-place"), org `skkcjbcqsfmrksbvzeiq` |
| Postgres | `17.6.1.127` |
| Supabase CLI | `2.106.0` (newer `2.109.1` available — informational) |

---

## 3. Migration status

`supabase migration list --linked`:

| Local | Remote | Applied? |
|---|---|---|
| 001 | 001 | ✅ applied |
| 002–010 | *(blank)* | ❌ not applied |

✅ `001` marked applied; `002–010` not applied; local file order `001→010` intact.

---

## 4. Product audit

| Metric | Value | Note |
|---|---:|---|
| Total products | **1** | |
| Duplicate `id` | **0** | ✅ `products.id` is unique (D-KEY-1 precondition for `008` satisfied) |
| Duplicate `slug` | 0 | |
| Null `id` | 0 | |
| Null `name` | 0 | |
| Orphan `category_id` | **1** | the single product's `category_id` points to no category (there are 0 categories); artifact of the bad `gen_random_uuid()` default — repaired by `007` |
| Null `category_id` | 0 | |
| PK | `PRIMARY KEY (id, name)` | composite (baseline); `008` narrows to `(id)` |

No duplicates → **no STOP condition triggered.**

## 5. Cart audit (`cart_items`)

| Metric | Value |
|---|---:|
| Total rows | **0** |
| Duplicate `(user_id, product_id)` | 0 |
| Orphan `product_id` | 0 |
| Orphan `user_id` | 0 |
| `quantity <= 0` or null | 0 |

Empty and clean.

## 6. Wishlist audit (`wishlists`)

| Metric | Value |
|---|---:|
| Total rows | **0** |
| Duplicate `(user_id, product_id)` | 0 |
| Orphan `product_id` | 0 |
| Orphan `user_id` | 0 |

Empty and clean.

## 7. Orders audit

| Metric | Value |
|---|---:|
| Total orders | **0** |
| Distinct status values | *(none — table empty)* |
| Null totals | 0 |
| Negative totals | 0 |
| Orders without items | 0 |
| Total order_items | 0 |
| Items without orders | 0 |
| Legacy status values (`paid`/`fulfilled`) | none (no rows) |

No orders exist → the `orders.status` VALIDATE concern (Backend Reconciliation M-5) has **no
current data exposure**; the CHECK in `007` will apply cleanly.

## 8. Profiles audit

| Metric | Value | Note |
|---|---:|---|
| Total profiles | **3** | |
| Distinct roles | `admin` (2), `user` (1) | ⚠️ legacy `user` present; **no `customer`** yet — normalized by `007` |
| Null roles | 0 | |
| Duplicate `id` | 0 | |
| Total auth users | **4** | |
| Users without a profile | **1** | one `auth.users` row has no `profiles` row; `handle_new_user` only fires on new signups (no backfill) |
| Profiles without an auth user | 0 | |
| Profiles with `phone = '+254...'` default | 2 | literal default; cleared going forward by `005` (drops default) |

## 9. Categories audit

| Metric | Value |
|---|---:|
| Total categories | **0** |
| Duplicate names | 0 |
| Unused categories | 0 |
| Products without category | 0 (but the 1 product's `category_id` is orphaned — see §4) |

There are **no categories**; the single product references a non-existent category id. The
`products → categories` FK (`009`) and the category repair (`007`) address this — both outside
this batch.

## 10. Storage audit

| Metric | Value |
|---|---:|
| Total buckets | **0** |
| `products` bucket exists | **No** |
| Objects in `products` | 0 |
| `storage.objects` RLS enabled | true |
| `storage.objects` policies | 0 |

**Finding:** no storage bucket exists on live (resolves Decision Log "Unresolved Q2"). Product
image columns (`image_url`, `images`) also do not exist yet (added by `002`). "Missing images /
broken public URLs" is therefore **N/A today** — there is no image infrastructure. Migration
`006` creates the public `products` bucket + policies (idempotent). **Do not modify storage in
this workstream** — not modified.

## 11. Auth configuration

Live GoTrue auth settings are not readable via SQL; the repository config (`supabase/config.toml`)
declares:

| Setting | Repo config | Production note |
|---|---|---|
| Email confirmations | disabled (`enable_confirmations=false`) | consider enabling for prod |
| Min password length | 6 | raise to ≥8 recommended |
| `site_url` | `http://127.0.0.1:3000` | **must** be set to prod domain |
| Redirect URLs | localhost | **must** add prod URLs |

⚠️ These are the repo-declared values; **live dashboard auth settings must be confirmed
manually** (not verifiable through read-only SQL). Documented as a production-readiness item;
does not block the `002–006` batch.

## 12. RLS audit

RLS is **enabled on all 7 public tables**. Policy inventory:

| Table | RLS | Policies | Assessment |
|---|---|---:|---|
| `profiles` | ✅ | 3 | SELECT own; INSERT own; **UPDATE own has `USING` only, NO `WITH CHECK`** → role escalation OPEN (fixed by `004`) |
| `orders` | ✅ | 4 | owner+admin SELECT, owner INSERT, admin UPDATE (owner INSERT removed by `004`) |
| `order_items` | ✅ | 2 | INSERT blocked; owner SELECT (broadened to owner-or-admin by `004`) |
| `products` | ✅ | 1 | public SELECT only (admin write added by `004`) |
| `cart_items` | ✅ | **0** | deny-all (unusable until `004`) |
| `categories` | ✅ | **0** | deny-all (public read + admin write added by `004`) |
| `wishlists` | ✅ | **0** | deny-all (unusable until `004`) |

## 13. Phase 1.7 findings verification

| Finding | Live verification | Status |
|---|---|---|
| **F-1** `orders → profiles` embed | No `orders↔profiles` FK on live (orders has no `user_id` FK at all yet); orders table empty → no current data impact, but embed will fail once orders exist | **Still Pending** (design decision; not fixed by `002–006`) |
| **R-1** duplicate-cart assumption in `place_order` | `cart_items` empty; 0 duplicate pairs | **Verified — no current exposure** (defense-in-depth still advised) |
| **Orphan enum** `order_status` | Exists; **0 columns use it** | **Verified present/unused** (dropped by `008`, not this batch) |
| **Frozen/bad defaults** | Confirmed: `gen_random_uuid()` on all id/FK columns; `created_at` frozen to 2026 literals; `phone='+254...'` | **Verified present** — FK-column + `created_at` defaults fixed by `005` (in batch); category repair by `007` |
| **Role normalization** | `role='user'` present (1 row); no `customer` value | **Still Pending** (normalized by `007`, not this batch) |
| **Product uniqueness** | `products.id` unique (0 dup ids), PK still composite | **Verified unique** (PK narrowed by `008`) |
| **C-1 / D-RLS-1 role escalation** | `profiles` UPDATE policy has no `WITH CHECK` | **Verified OPEN** — remediated by `004` (in batch) |

## 14. Performance summary

Actual row counts (`count(*)`; `pg_stat_user_tables.n_live_tup` reports stale zeros — never
analyzed):

| Table | Rows |
|---|---:|
| products | 1 |
| profiles | 3 |
| auth.users | 4 |
| categories / cart_items / wishlists / orders / order_items | 0 |

- **Indexes:** only the 7 primary keys exist; **no secondary indexes** (added by `010`).
- **Largest table:** none material (max 4 rows).
- **Estimated migration impact:** negligible — every migration (including the `008` PK change
  and `010` indexes) is effectively instantaneous at this scale; no lock/downtime concern.

## 15. Risk register

| ID | Risk | Severity | Blocks batch? | Note |
|---|---|---|---|---|
| K-1 | `010` FTS index references `products.description` (exists only after `008`) → `010` fails pre-`008` | **High** | **Yes — for `010` only** | Defer `010` to after `008`; apply `002–006` without it |
| K-2 | Live role self-escalation (`profiles` UPDATE, no `WITH CHECK`) | **Critical (pre-existing)** | No — batch **fixes** it | Applying `004` closes it; a reason to proceed |
| K-3 | F-1 `orders→profiles` embed unbacked by FK | High | No | functional (order views); resolve as design decision; orders empty now |
| K-4 | Legacy `role='user'` not normalized until `007` | Medium | No | frontend treats non-`admin` as customer; harmless until `007` |
| K-5 | 1 auth user without a profile row | Medium | No | `handle_new_user` won't backfill; manual/`007` follow-up |
| K-6 | Orphan `products.category_id`; 0 categories | Medium | No | category FK/repair are `007`/`009` (not this batch) |
| K-7 | Bad `gen_random_uuid()` FK-column + frozen `created_at` defaults | Medium | No | fixed by `005` (in batch) |
| K-8 | No `products` storage bucket | Medium | No | created by `006` (in batch) |
| K-9 | `phone='+254...'` default on 2 profiles; no secondary indexes; prod auth config localhost | Low | No | cosmetic / handled later (`005`, `010`, dashboard) |

**Blocker preventing full Workstream 2B batch:** only **K-1** — remove `010` from this batch.

## 16. Preconditions for Workstream 2B (this batch)

1. Take a fresh backup / PITR snapshot before applying (good practice even for additive steps).
2. Apply **in order: `002 → 003 → 004 → 005 → 006`** (dependencies satisfied: `004`/`006` need
   `is_admin()` from `003`; `003` needs columns from `002`).
3. **Exclude `010`** (blocked by `008` — see K-1). Apply `010` only after `008`.
4. Post-apply verification: functions/triggers present; policies as canonical; `products`
   bucket created; since `orders`/`cart_items`/`wishlists` are empty, the `005` user-FKs can be
   `VALIDATE`d immediately (no orphans).
5. Note residual (expected) post-batch state: `role='user'` persists, 1 profile-less user,
   orphan `category_id`, no category/product FK embeds — all addressed by `007–009` (later).
6. Decide F-1 (`orders→profiles`) direction before it matters (orders currently empty).

## 17. Evidence (key results)

- Migration list: `001` remote-applied; `002–010` blank.
- Products: total 1, dup_ids 0, dup_slugs 0, null 0, orphan_category 1, PK `(id,name)`.
- Cart/Wishlist/Orders/Order_items/Categories: 0 rows, all integrity metrics 0.
- Profiles: 3 rows (roles admin×2, user×1), 0 null/dup, 2 phone-default, 1 auth user without profile; auth.users 4.
- RLS on all 7 tables; deny-all on cart_items/categories/wishlists; profiles UPDATE lacks `WITH CHECK`.
- Enum `order_status` present, 0 columns using it.
- Defaults: `gen_random_uuid()` on id/FK columns; 2026 `created_at` literals; `phone='+254...'`.
- Indexes: 7 PKs only.
- Storage: 0 buckets, no `products` bucket, `storage.objects` RLS on, 0 policies.

## 18. Commands executed (all read-only)

```bash
# Environment / migration state
git branch --show-current ; git tag --points-at HEAD ; git log -1 --oneline ; git status --short
supabase migration list --linked

# Integrity aggregates (single json_build_object query)
supabase db query --linked -o json "SELECT json_build_object(... products/cart/wishlist/orders/profiles/categories counts ...)"
# Distinct status/role
supabase db query --linked -o table "SELECT 'order_status', status, count(*) FROM orders GROUP BY status UNION ALL SELECT 'role', role, count(*) FROM profiles GROUP BY role"

# Structural
supabase db query --linked "SELECT relname, relrowsecurity, <policy count> FROM pg_class ..."           # RLS + policy counts
supabase db query --linked "SELECT policyname, cmd, qual IS NOT NULL, with_check IS NOT NULL FROM pg_policies WHERE tablename='profiles'"
supabase db query --linked "SELECT tablename, policyname, cmd FROM pg_policies WHERE schemaname='public'"
supabase db query --linked "SELECT typname, <cols using> FROM pg_type WHERE typname='order_status'"
supabase db query --linked "SELECT table_name, column_name, column_default FROM information_schema.columns WHERE column_default LIKE '%gen_random_uuid%' OR column_default LIKE '%2026%' OR column_name='phone'"
supabase db query --linked "SELECT tablename, indexname FROM pg_indexes WHERE schemaname='public'"
supabase db query --linked "SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='public.products'::regclass AND contype='p'"
supabase db query --linked -o json "SELECT ... storage.buckets / storage.objects / storage policies / RLS ..."
supabase db query --linked -o json "SELECT relname, n_live_tup FROM pg_stat_user_tables WHERE schemaname='public'"
```

(All Supabase commands run with `< /dev/null` for non-interactive execution.)

## 19. Final GO / NO-GO

| Migration | Decision | Reason |
|---|---|---|
| `002` additive columns | **GO** | additive; tiny tables; unblocks app columns |
| `003` functions/triggers | **GO** | needs `002` (in order); safe |
| `004` RLS + role fix | **GO** | **closes live role-escalation**; needs `003` |
| `005` integrity/defaults/user-FK/CHECK | **GO** | empty user tables → FKs/CHECKs clean; fixes bad defaults |
| `006` storage policies | **GO** | creates absent `products` bucket + policies; needs `003` |
| `010` performance/indexes/FTS | **NO-GO (defer)** | FTS index needs `products.description`, created only by `008`; would fail pre-`008` |

**Overall: GO WITH ONE CONDITION — apply `002–006` (in order); do NOT apply `010` in this
batch.** (`007–009` intentionally not discussed here.)

---

## Final validation

- ✅ repository unchanged (no code/migration edits; only this report added)
- ✅ live schema unchanged (read-only queries only in 2A)
- ✅ no migrations executed
- ✅ no repairs executed
- ✅ no writes performed
- ✅ pre-flight validation complete
- ✅ Workstream 2B readiness determined (GO `002–006`; defer `010`)

**STOP — not proceeding to Workstream 2B. Awaiting explicit approval.**
