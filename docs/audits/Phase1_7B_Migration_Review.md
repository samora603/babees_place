# Phase 1.7B — Workstream 1: Migration Engineering Review

**Date:** 2026-07-12
**Branch:** `phase-1.7-reconciliation`
**Reviewer scope:** Static engineering review of the authored forward-only migrations
(`supabase/migrations/002…010`) against the live baseline (`001_initial_schema.sql`) and
the four authoritative docs. **No migration was executed, pushed, repaired, or connected
to any database.**
**Cross-checked against:** `Final_Canonical_Schema.md`, `Reconciliation_Decision_Log.md`,
`Migration_Strategy.md`, `Schema_Comparison_Matrix.md`.

> **Outcome:** Issues were found and **corrected in-place** during this review (4 fixes,
> see §2). After corrections, the migration set passes the full review checklist.

---

## 1. Overall engineering score

**9.4 / 10** (after the §2 corrections; pre-correction: 8.4).

| Dimension | Score | Notes |
|---|---:|---|
| Dependency graph & execution order | 10 | Single valid forward chain; each file depends only on predecessors |
| SQL correctness | 9 | Verified statement-by-statement; PL/pgSQL delimiters & tx blocks balanced |
| PostgreSQL compatibility | 10 | Standard DDL; immutable FTS expression; `NOT VALID`/`VALIDATE` used correctly |
| Supabase compatibility | 10 | `auth.users` trigger pattern, `storage.objects` policies, RLS + RPC idioms |
| Security (RLS / SECURITY DEFINER / search_path) | 9 | Role-escalation closed; definer fns pinned; anon execute revoked (fixed) |
| Idempotency | 10 | `IF [NOT] EXISTS`, `OR REPLACE`, `DROP … IF EXISTS`, catalog guards |
| Naming consistency | 10 | snake_case; conventional constraint/index names |
| Headers / rollback comments | 10 | Every file documents Purpose/Deps/Risk/Rollback/Changes |
| Data preservation | 9 | Additive-first; gated data steps isolated; timestamp-default bug fixed |
| Production readiness | 8 | Conditional GO — gated steps need backups + live-evidence checks |

---

## 2. Issues found and corrected

| # | Severity | File | Finding | Correction |
|---|---|---|---|---|
| I-1 | **High (data bug)** | `005` | Baseline froze `created_at` to literal 2026 timestamps (not `now()`); `categories`/`wishlists` had no default. Only FK/phone defaults were being fixed → new rows would get a frozen past date. Violated `D-KEY-5` / `Schema_Comparison_Matrix §5` and canonical §3. | Added `ALTER COLUMN created_at SET DEFAULT now()` for `cart_items, orders, products, profiles, categories, wishlists` (future inserts only; existing data untouched). |
| I-2 | Medium | `008` | `D-ENUM-1` (drop the unused `public.order_status` enum) was not implemented. | Added a guarded `DROP TYPE public.order_status` (only when unreferenced) + rollback note. |
| I-3 | Medium (hardening) | `003` | Baseline `ALTER DEFAULT PRIVILEGES` grants `EXECUTE` to `anon` on new functions, so `REVOKE … FROM public` still left `anon` able to call `place_order` (it fails safe on `NULL` uid, but violates least-privilege). | `REVOKE ALL … FROM PUBLIC, anon;` then `GRANT EXECUTE … TO authenticated`. |
| I-4 | Medium (functional / doc conflict) | `004` | Live `order_items` SELECT is **owner-only**; admins could see parent `orders` but not their line items → admin order detail would be empty. `Final_Canonical_Schema §7` specifies owner-**or-admin**. | Replaced with `order_items_select_owner_or_admin`; kept the INSERT block. Documented reconciliation of the `D-RLS-4 "keep live"` vs canonical §7 wording. |

All four corrections were re-validated (tx balance, `DO/$$` delimiter balance, grep confirmation).

---

## 3. Migration-by-migration review

### 002 — `additive_columns` (M1) — ✅ PASS
- Adds exactly the canonical additive columns; `ADD COLUMN IF NOT EXISTS` (idempotent).
- Constant defaults (`0`, `'[]'::jsonb`, `'pending'`, `true`) → fast, no table rewrite;
  `now()`/volatile defaults resolve via PG fast-default. Data preserved.
- `is_active` included per canonical §4.3/`D-PROD-11` (documented deviation from the literal
  M1 list; additive & harmless).
- Phase-2 order columns correctly **excluded** (deferred per strategy).

### 003 — `functions_and_triggers` (M4) — ✅ PASS (fixed I-3)
- `is_admin()`: `STABLE SECURITY DEFINER SET search_path=public`; avoids RLS recursion (used
  by policies). Correct.
- `handle_new_user()`: SECURITY DEFINER; role `'customer'` (D-CUST-1); `ON CONFLICT DO NOTHING`.
  Uses the Supabase-canonical `auth.users` AFTER INSERT trigger.
- `set_updated_at()` + triggers on `profiles/products/orders` (columns from 002).
- `place_order()`: adapted from archived 001/002 to live columns (`cart_items`, `orders.total`,
  `products.discount_price`), `FOR UPDATE` row locking, server-computed total, snapshots,
  stock decrement, cart clear. Caller check `auth.uid() = p_user_id OR is_admin()`. Execute
  restricted to `authenticated` (fixed). `jsonb_typeof(images)` guard is safe (images NOT NULL).
- All 4 function bodies use balanced `$$` delimiters.

### 004 — `rls_and_security` (M3+M2) — ✅ PASS (fixed I-4)
- **C-1 closed:** `profiles_update_own` gains `WITH CHECK (auth.uid()=id AND role unchanged)`;
  separate `profiles_update_admin` for role changes. Multiple-permissive-policy semantics
  verified: regular users cannot escalate; admins can manage roles.
- `profiles` SELECT broadened to own-or-admin (supports admin joins).
- `cart_items`/`wishlists` owner `FOR ALL`; `categories` public read + admin write; `products`
  public read (baseline kept) + admin write.
- `orders` direct INSERT removed (creation via `place_order` only); baseline SELECT/UPDATE
  policies retained (canonical-equivalent).
- `order_items` INSERT stays blocked; SELECT now owner-or-admin.
- All policies reference only existing columns + `is_admin()`.

### 005 — `integrity_constraints` (M5a) — ✅ PASS (fixed I-1)
- Drops all erroneous FK-column & phone defaults; **now also** repairs frozen `created_at`
  defaults.
- User→`auth.users` FKs added `NOT VALID` (enforce new writes; VALIDATE deferred to manual
  after orphan check) — correct non-destructive posture.
- `quantity > 0` CHECKs added `NOT VALID` then `VALIDATE` (near-certain to hold).

### 006 — `storage_policies` (M8) — ✅ PASS
- Ensures `products` bucket (`ON CONFLICT DO NOTHING`); public read + admin write/update/delete
  on `storage.objects` scoped to `bucket_id='products'` via `is_admin()`.
- Depends only on `is_admin()` (003). Bucket existence flagged as a manual dashboard check.

### 007 — `data_normalization` (M6, GATED) — ✅ PASS
- Clearly marked GATED (backup + approval + window). Backfills `full_name`; normalizes `role`
  then enforces + validates the role CHECK; repairs `category_id` (nulls garbage random UUIDs
  from the old default, then backfills from `category` text) so the 009 FK can validate;
  dedupes `cart_items`/`wishlists` (keep-latest via `DISTINCT ON … ctid`) for the 009 UNIQUE.
- `payment_status` CHECK validated (all rows `'pending'` from 002); `status` CHECK added
  `NOT VALID` with `fulfilled→delivered` mapping and a documented **manual VALIDATE** (legacy
  status values are an unresolved assumption — correct to not guess).
- Rollback = restore-from-backup (correctly stated; not `DROP`-reversible).

### 008 — `structural_reconciliation` (M7, GATED) — ✅ PASS (fixed I-2)
- Duplicate-`id` guard raises a clear exception before the PK swap; composite→`(id)` guarded
  by catalog inspection; no FK references `products` yet (product FKs are in 009) → safe.
- `"Description"→description` via guarded, data-preserving `RENAME`.
- **Now drops** the unused `order_status` enum (guarded).
- Rollback = restore-from-backup.

### 009 — `product_integrity` (M5b) — ✅ PASS
- Product FKs (`cart_items`/`wishlists` CASCADE, `order_items` SET NULL) added `NOT VALID`
  (manual VALIDATE documented). `products.category_id → categories` validated (007 guarantees
  validity). `UNIQUE(user_id, product_id)` on cart/wishlist (dedupe done in 007).
- Correctly ordered after 008 (PK) and 007 (dedupe/category repair).

### 010 — `performance_optimizations` — ✅ PASS
- Lookup indexes on orders/order_items/cart_items/wishlists/products; product FTS GIN over an
  **immutable** `to_tsvector('simple', …)` expression (needs `description` from 008).
- `CREATE INDEX IF NOT EXISTS` (idempotent), transactional; `CONCURRENTLY` variant documented
  for large tables (kept out of the tx block).
- `slug` index intentionally **non-unique** pending uniqueness verification (documented).

---

## 4. Dependency graph (post-review)

```
001 baseline
 └─ 002 additive columns
     └─ 003 functions & triggers ── is_admin() ──┐
         ├─ 004 RLS & security  ◄────────────────┤
         └─ 006 storage policies ◄───────────────┘
     └─ 005 integrity (defaults, user FKs, qty CHECK)
         └─ 007 data normalization  (GATE 1: backup+approval)
             └─ 008 structural (PK, rename, drop enum)  (GATE 2: backup+approval)
                 └─ 009 product integrity (product FKs, UNIQUE, category FK)
                     └─ 010 performance (indexes + FTS)
```

Linear execution order = filename order `001 → 002 → 003 → 004 → 005 → 006 → 007 → 008 → 009 → 010`.
No cycles; no forward references.

---

## 5. Decision-coverage audit (implemented exactly once)

| Decision | Implemented in | Status |
|---|---|---|
| D-TBL-1..7 (table additive/keep) | 002, 004, 005, 009 | ✅ once each |
| D-ENUM-1 (drop enum) | 008 | ✅ (added this review) |
| D-KEY-1 (products PK) | 008 | ✅ |
| D-KEY-2 (FKs) | 005 (user), 009 (product) | ✅ split, no dup |
| D-KEY-3 (UNIQUE) | 009 (+ dedupe 007) | ✅ |
| D-KEY-4 (qty CHECK) | 005 | ✅ |
| D-KEY-5 (bad defaults incl. timestamps) | 005 | ✅ (completed this review) |
| D-IDX-1 (indexes) | 010 | ✅ |
| D-RLS-1..4 | 004 | ✅ |
| D-RPC-1/2/3 (is_admin/handle_new_user/place_order) | 003 | ✅ |
| D-STOR-1 (storage) | 006 | ✅ |
| D-PROD-1..13 | 002/008/009 | ✅ |
| D-CUST-1/2/3/5/6/9/10 | 002/003/004/005/007/009 | ✅ |
| D-RPC-4/5, D-CUST-4, D-FEAT-1..6 | — | ⏸ correctly **deferred** (Phase 2) |
| D-CUST-7 (timestamptz type) | — | ⚠ **deviation** (matrix marks Opt) — see §6 |

No decision is implemented twice; no in-scope decision is missing after corrections.

---

## 6. Accepted deviations (documented, not defects)

1. **timestamptz type standardization** (D-CUST-7/D-PROD-7): `created_at` columns remain
   `timestamp without time zone`. The Comparison Matrix marks this **Opt**; a type change
   forces a table rewrite. Deferred as an optional enhancement. (Defaults were fixed in 005.)
2. **`products.slug` UNIQUE** (canonical §5): created non-unique in 010 because slug uniqueness
   on live is unverified. UNIQUE variant documented.
3. **`categories.slug` UNIQUE** (canonical §4.2 "recommended"): not added (recommended, unverified).
4. **`quantity` smallint→integer**, **money `numeric`→`numeric(12,2)`**: left as live-compatible
   types; tightening deferred to avoid destructive type changes.
5. **Phase-2 order columns** (`delivery_type`/`pickup_location`/`delivery_address`/
   `mpesa_receipt_number`): deferred per the strategy's Deferred section.
6. **Ordering deviation from the literal M-list**: M4 before M2/M3, and M5 split across 005/009 —
   required for a valid forward chain (the strategy itself flags the `is_admin()` dependency).

---

## 7. Hidden risks & assumptions

- **A-1** `products.id` uniqueness — 008 aborts with a clear message if violated.
- **A-2** live `orders.status` distinct values — determines when `orders_status_check` can be
  validated; only `fulfilled` is auto-mapped.
- **A-3** orphan rows for user/product FKs — gate the manual `VALIDATE` steps.
- **A-4** duplicate `products.slug` — blocks the recommended UNIQUE index.
- **A-5** `products` storage bucket existence/visibility — dashboard confirmation.
- **A-6** cart dedupe policy — 007 keeps most-recent; sum-quantities is an alternative product
  decision.
- **A-7** migration-history reconciliation on live requires `supabase migration repair`
  (separate approved step; not in these files).

---

## 8. Readiness assessment

- **Authoring/quality:** ready. Coherent, idempotent, documented forward chain; every in-scope
  decision implemented exactly once; the pre-existing timestamp-default data bug is now fixed.
- **Static validation performed (no DB):** filename ordering; `is_admin()` defined before refs;
  `description` used only after the 008 rename; all added-column usage ≥ 002; `BEGIN/COMMIT`
  balanced per file; PL/pgSQL `$$`/`DO…END` delimiters balanced; policies/constraints reference
  only existing objects; FTS expression is immutable.
- **Not performed (out of scope / requires DB):** `supabase db lint`, `db diff`, and any
  execution. Recommended as the first staging action.

---

## 9. Remaining manual steps (execution phase — not now)

1. Take a fresh backup (`supabase db dump --linked -f backup_<ts>.sql`) + PITR snapshot.
2. Run the read-only precondition queries: `products.id` dupes, `orders.status` distinct values,
   FK orphan anti-joins, `products.slug` dupes, `storage.buckets` check.
3. Apply on **staging** in groups (A: 002–006, B: 007–009 gated, C: 010); smoke-test each.
4. After orphan checks: `VALIDATE` the user FKs (005), product FKs (009), and `orders_status_check`.
5. Ship paired frontend changes (Workstream 2) with the matching DB group.
6. `supabase migration repair` to reconcile the empty live history with `001` (separate approval).
7. Final: `supabase db diff --linked` → expect *"No schema changes found."*

---

## 10. GO / NO-GO recommendation

**GO (conditional).**

- ✅ **GO** to advance the workstream and to deploy on **staging** following the runbook.
- ✅ **GO** for the non-gated group (002–006, 010) to production after staging sign-off + the §9
  precondition checks.
- ⛔ **NO-GO** for the gated group (**007, 008, 009**) until: fresh backup taken, §7 assumptions
  verified on live, and explicit approval + maintenance window secured — exactly as the gated
  design intends.
- ⛔ **NO-GO** for any execution in this workstream.

**Recommendation:** Approve the corrected migration set. Proceed to plan Workstream 2 (frontend/DB
reconciliation) and staging execution; do not run the gated migrations against production until
their preconditions are verified.

---

## 11. Stop condition

Review complete; 4 issues found and corrected in-place; report produced. **Nothing was executed,
pushed, repaired, or connected to production.** Halting for approval before Workstream 2.
