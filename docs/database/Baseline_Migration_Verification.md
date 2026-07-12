# Baseline Migration Verification — Phase 1.6 Workstream A

**Date:** 2026-07-12
**Live project:** `qfcygrxrfszcdltangec` ("Babis-place", eu-central-1, Postgres 17.6)
**Scope:** Workstream A only — generate + verify the baseline from live. **No migrations applied. Live DB not modified. Frontend not touched. No later migrations modified.**

---

## Summary

A read-only baseline of the live `public` schema was generated to
`docs/database/generated_baseline/001_initial_schema.sql`. It faithfully captures the
current live schema (7 tables, 1 enum type, all primary/foreign keys, RLS enablement, and
all 10 RLS policies). The live database has **no functions, no triggers, and no non-PK
indexes**, so none are present in the baseline (nothing was lost).

The file is a complete, schema-only representation of the live public schema and **can be
adopted as `001_initial_schema.sql` without loss of information**. Actual adoption (moving it
into `supabase/migrations/`, retiring the fictional `001_schema_rls_place_order.sql`, and
repairing migration history) is a **reconciliation** step and was intentionally **not**
performed in this workstream.

---

## Commands executed (all read-only)

```bash
# 1. Inspect pull behavior (no side effects)
supabase db pull --help

# 2. Generate baseline via read-only schema dump (pure pg_dump of remote; no shadow DB,
#    no diff against local migrations, no write to the remote migration-history table)
mkdir -p docs/database/generated_baseline
supabase db dump --linked -s public -f docs/database/generated_baseline/001_initial_schema.sql
```

### Why `db dump` instead of `db pull`
`supabase db pull` (v2.106) computes a **diff** by applying the existing local migrations
(`001`/`002`/`003`, which describe a *fictional* schema) to a shadow database and comparing
against remote. Because the local migrations do not match live, that diff would be noisy and
misleading, and `db pull` can additionally prompt to **write to the remote migration-history
table** — which would modify the live database. `supabase db dump -s public` is the
read-only, side-effect-free way to obtain a faithful snapshot of the *current live* schema,
which is exactly what a baseline requires. This choice honors "read-only" and "do not modify
the live database."

---

## Files generated

| File | Bytes | Contents |
|---|---:|---|
| `docs/database/generated_baseline/001_initial_schema.sql` | 8921 | Schema-only DDL for the live `public` schema (tables, types, PKs, FKs, RLS enable, policies, grants) |

Staged **outside** `supabase/migrations/` on purpose: placing a second `001_`-prefixed file
next to the existing `001_schema_rls_place_order.sql` would create a duplicate migration
version and break `supabase migration list`/`push`. Adoption is a reconciliation task.

---

## Object inventory (verification)

| Object class | Count in baseline | Detail |
|---|---:|---|
| Tables | 7 | `cart_items`, `categories`, `order_items`, `orders`, `products`, `profiles`, `wishlists` |
| Types (enum) | 1 | `public.order_status` (`pending`,`paid`,`fulfilled`,`cancelled`) — **defined but unused** (orders.status is `text`) |
| Columns | all | Captured verbatim (incl. `products."Description"`, `orders.total`, `profiles.role default 'customer'`) |
| Primary keys | 7 | incl. **composite `products (id, name)`** |
| Foreign keys | 2 | `order_items.order_id`→orders (CASCADE), `profiles.id`→auth.users (CASCADE) |
| Indexes (non-PK) | 0 | none on live |
| Triggers | 0 | none on live |
| Functions | 0 | `place_order`/`is_admin`/`handle_new_user` **absent on live** |
| RLS enabled | 7 tables | all public tables |
| RLS policies | 10 | orders (4), order_items (2), profiles (3), products (1); **none** for `cart_items`/`categories`/`wishlists` → deny-all |

Verification method: the file is a `pg_dump` of the live schema, so it is accurate by
construction; counts above were confirmed with `grep` against the generated file and match
the independent Phase 1.5 dump (identical 8921 bytes).

---

## Differences from repository migrations

Comparing the generated live baseline against `supabase/migrations/`:

| Repository migration | Relationship to live baseline |
|---|---|
| `001_schema_rls_place_order.sql` | **Fictional / never applied.** Describes a *different* schema: tables `cart`/`wishlist` (live: `cart_items`/`wishlists`), `orders.total_amount` (live: `total`), `profiles.full_name` + role CHECK (`user`/`admin`) (live: no `full_name`, role default `customer`), `products.stock`/`discountPrice`/images (live: none; live PK is `(id,name)`), and functions `place_order`/`is_admin`/`handle_new_user` (**absent on live**). Baseline should supersede it. |
| `002_phase1_security_hardening.sql` | Targets the fictional `001` schema (policy names, `place_order`, columns not on live). **Not applicable to the live baseline as-is.** Already carries a `DO NOT APPLY AS-IS` header. |
| `003_phase1_indexes_constraints.sql` | References `public.cart`, `orders.payment_status`, `profiles.updated_at` — none exist in the live baseline. **Not applicable as-is.** Header warns accordingly. |
| `20260617042152_remote_schema.sql` | **Empty (0 bytes)** — artifact of an earlier empty pull. The new baseline is its correct, populated replacement. |

Net: the live baseline diverges from **all** repository migrations. The baseline is the
authoritative starting point; `001` is fiction, `002`/`003` are forward-fixes that must be
re-authored against the baseline during reconciliation (out of scope here).

---

## Unexpected findings

1. **Orphan enum type** `public.order_status` exists but `orders.status` is plain `text` —
   the enum is unused. (Consider using or dropping it during reconciliation.)
2. **Composite primary key** `products (id, name)` — unusual; blocks clean FK references and
   single-row `.eq('id')` guarantees.
3. **Bad column defaults on live** — FK columns (`user_id`, `product_id`) default to
   `gen_random_uuid()`, and `profiles.phone` defaults to the literal `'+254...'`; several
   `created_at` columns use hard-coded timestamp literals instead of `now()`.
4. **Three tables are deny-all** (`cart_items`, `categories`, `wishlists`: RLS on, no policy).
5. **No server logic on live** — 0 functions/triggers; the app's `place_order` RPC does not
   exist (checkout cannot complete server-side).
6. **Baseline excludes managed schemas** — extensions, `auth`, and `storage` are managed by
   Supabase and are not part of a `public` schema dump (expected; noted for completeness).

---

## Manual review items (require human / dashboard; not guessable)

- Confirm whether the `order_status` enum should be kept (and applied to `orders.status`) or
  dropped.
- Decide the `products` primary-key strategy (verify `id` uniqueness before any PK change).
- Storage: verify the `products` bucket exists and its visibility
  (`select id, name, public from storage.buckets;`) — not in a schema dump.
- Confirm no additional objects live in non-`public` schemas that the app relies on
  (none observed; app uses `public` + `auth` + `storage` only).
- Row counts / data volume (for future data-migration window sizing).

---

## Risks

| Risk | Severity | Note |
|---|---|---|
| Adopting baseline as `001` while fictional `001` still present | Med | Duplicate migration version would break tooling — retire the old `001` **during reconciliation**, not now |
| Baseline lacks functions the app needs (`place_order`) | High | Correct reflection of live; functions are added later (reconciliation M4), not fabricated here |
| Composite PK / bad defaults carried into baseline | Med | Baseline must mirror live faithfully; cleanups are gated reconciliation steps |
| Baseline is schema-only (no data) | Low | Intended — no data loss; data stays in live |
| CLI version slightly behind (2.106 vs 2.109) | Low | Dump succeeded; no impact on schema fidelity |

---

## Validation result

**Confirmed:** `docs/database/generated_baseline/001_initial_schema.sql` is a complete,
schema-only snapshot of the live `public` schema and **can become
`supabase/migrations/001_initial_schema.sql` without losing information** (all live tables,
columns, keys, constraints, RLS enablement, and policies are present; live has no
functions/triggers/indexes to lose). Adoption + retiring the fictional `001` + migration-history
repair are **reconciliation** actions and were **not** performed.

**Stop:** Workstream A complete. No reconciliation performed. No later migrations modified.
No live database or frontend changes.
