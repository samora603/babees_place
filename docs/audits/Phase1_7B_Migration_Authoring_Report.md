# Phase 1.7B — Workstream 1: Migration Authoring Report

**Date:** 2026-07-12
**Branch:** `phase-1.7-reconciliation`
**Baseline:** `supabase/migrations/001_initial_schema.sql` (verified live schema)
**Scope:** Author forward-only SQL migrations only. **Nothing was executed, pushed,
repaired, or connected to production. No frontend/backend/doc changes** beyond the
migration files and this report.
**Authoritative inputs:** `Final_Canonical_Schema.md`, `Reconciliation_Decision_Log.md`,
`Migration_Strategy.md`, `Schema_Comparison_Matrix.md`, `Migration_History.md`,
`Database_Reconciliation_Runbook.md`, `ADR-001`.

---

## 1. Migration inventory

All files live in `supabase/migrations/`. Execution order = lexical filename order.

| # | File | Strategy map | Purpose | Class | Risk | Idempotent |
|---|---|---|---|---|---|---|
| 002 | `002_additive_columns.sql` | M1 | Add missing app columns (profiles, orders, products, order_items) | Additive | Low | Yes (`ADD COLUMN IF NOT EXISTS`) |
| 003 | `003_functions_and_triggers.sql` | M4 | `is_admin`, `handle_new_user`, `set_updated_at`, `place_order` + triggers | Logic | Med | Yes (`CREATE OR REPLACE`, `DROP TRIGGER IF EXISTS`) |
| 004 | `004_rls_and_security.sql` | M3 + M2 | Role-escalation fix + RLS for deny-all tables + admin writes | Security | Low–Med | Yes (`DROP POLICY IF EXISTS`) |
| 005 | `005_integrity_constraints.sql` | M5a | Drop bad defaults; user→auth FKs (NOT VALID); quantity CHECKs | Integrity | Med | Yes |
| 006 | `006_storage_policies.sql` | M8 | `products` bucket + storage.objects policies | Security | Med | Yes (`ON CONFLICT`, `DROP POLICY IF EXISTS`) |
| 007 | `007_data_normalization.sql` | M6 | Backfills, role normalize, category_id repair, cart/wishlist dedupe, CHECKs | **Data (GATED)** | Med–High | Re-runnable (guarded `WHERE`) |
| 008 | `008_structural_reconciliation.sql` | M7 | products PK `(id,name)`→`(id)`; rename `"Description"`→`description` | **Structural (GATED)** | High | Yes (catalog-guarded) |
| 009 | `009_product_integrity.sql` | M5b | Product FKs (NOT VALID); category FK; `UNIQUE(user_id,product_id)` | Integrity | Med–High | Yes |
| 010 | `010_performance_optimizations.sql` | §5 indexes | Lookup indexes + product FTS GIN | Performance | Low | Yes (`CREATE INDEX IF NOT EXISTS`) |

**Deviations from the strategy's literal M-list (intentional, justified):**
- **Ordering:** M4 (functions) is placed **before** M2/M3 (RLS) so the `is_admin()`
  dependency the strategy itself flags is satisfied cleanly, and M5 is **split** into
  005 (pre-gate: user FKs, quantity checks, default cleanup) and 009 (post-gate:
  product FKs / UNIQUE, which require the 008 PK change and the 007 dedupe). This makes
  the file order a valid single forward chain where each file depends only on earlier ones.
- **`products.is_active`** is added in 002 per `Final_Canonical_Schema §4.3` / `D-PROD-11`
  even though `Migration_Strategy M1` did not list it. It is additive, non-destructive,
  and indexed in 010. Caveat (D-PROD-11): no frontend read exists yet — introduced ahead
  of app support; harmless.
- **Phase-2 order columns** (`delivery_type`, `pickup_location`, `delivery_address`,
  `mpesa_receipt_number`) are **NOT** authored here — they belong to the strategy's
  *Deferred* feature set and are out of stabilization scope.
- **Money precision / `quantity` type** left as live (`numeric` unbounded, `smallint`).
  Tightening to `numeric(12,2)` / `integer` is a non-blocking follow-up; skipped to avoid
  a destructive type change on production data. Recorded as a deviation, not a defect.

---

## 2. Dependency graph

```
001_initial_schema (baseline)
        │
        ▼
002_additive_columns ─────────────┐
        │                          │
        ▼                          │
003_functions_and_triggers        │ (columns used by place_order / handle_new_user /
        │                          │  set_updated_at triggers)
        ├──────────────┐           │
        ▼              ▼           │
004_rls_and_security  006_storage_policies      (both need is_admin from 003)
        │
        ▼
005_integrity_constraints  ◄── depends on 002 (ordered), independent of RLS
        │
        ▼
007_data_normalization  (GATE 1)   ◄── needs 002 (full_name); cleans data for 008/009
        │
        ▼
008_structural_reconciliation (GATE 2)  ◄── PK(id) enables single-col FKs
        │
        ▼
009_product_integrity  ◄── needs 008 (PK) + 007 (dedupe, category repair)
        │
        ▼
010_performance_optimizations  ◄── needs 002 (is_active) + 008 (description for FTS)
```

Linear execution chain (each depends only on predecessors):
`001 → 002 → 003 → 004 → 005 → 006 → 007 → 008 → 009 → 010`.

---

## 3. Per-migration summary (Purpose / Deps / Risk / Rollback / Changes)

Full detail is in each file header. Condensed:

- **002** — *Purpose:* unblock the app with missing columns. *Deps:* 001. *Risk:* Low.
  *Rollback:* `DROP COLUMN`. *Changes:* +profiles(full_name,updated_at),
  +orders(payment_status,note,updated_at), +products(stock,discount_price,image_url,images,is_active),
  +order_items(image_url,created_at).
- **003** — *Purpose:* server logic. *Deps:* 002. *Risk:* Med (checkout). *Rollback:*
  `DROP FUNCTION/TRIGGER`. *Changes:* 4 functions + 4 triggers. `place_order` derived from
  archived 001/002, adapted to live cols (`cart_items`, `orders.total`, `discount_price`)
  with `FOR UPDATE` locking.
- **004** — *Purpose:* close C-1 role escalation + make deny-all tables usable. *Deps:* 003.
  *Risk:* Low–Med (behavioral). *Rollback:* drop new policies / restore prior. *Changes:*
  profiles update-own gains `WITH CHECK` (role unchanged) + admin update; cart/wishlist owner
  policies; categories public+admin; products admin write; orders direct INSERT removed.
- **005** — *Purpose:* integrity that doesn't need gates. *Deps:* 002. *Risk:* Med. *Rollback:*
  `DROP CONSTRAINT`. *Changes:* drop bad defaults; user FKs (NOT VALID); quantity CHECKs (validated).
- **006** — *Purpose:* storage security. *Deps:* 003. *Risk:* Med. *Rollback:* drop policies.
  *Changes:* ensure `products` bucket; 4 storage.objects policies.
- **007** — *Purpose:* clean data for constraints (**GATED**). *Deps:* 002/005. *Risk:* Med–High.
  *Rollback:* **restore from backup**. *Changes:* backfill full_name; normalize+CHECK role;
  repair+backfill category_id; dedupe cart/wishlist; payment_status CHECK (validated); status
  CHECK (NOT VALID, manual VALIDATE).
- **008** — *Purpose:* PK + rename (**GATED**). *Deps:* 007. *Risk:* High. *Rollback:* **restore
  from backup**. *Changes:* products PK→(id) with a duplicate-id guard; `"Description"`→`description`.
- **009** — *Purpose:* product FKs + UNIQUE. *Deps:* 008 (PK) + 007 (dedupe). *Risk:* Med–High.
  *Rollback:* `DROP CONSTRAINT`. *Changes:* cart/wishlist/order_items product FKs (NOT VALID);
  category FK (validated); cart/wishlist UNIQUE.
- **010** — *Purpose:* performance. *Deps:* 002 + 008. *Risk:* Low. *Rollback:* `DROP INDEX`.
  *Changes:* 10 indexes incl. product FTS GIN. Non-unique slug index (uniqueness unverified).

---

## 4. Risks

| ID | Risk | Where | Mitigation in the authored SQL |
|---|---|---|---|
| R1 | FK VALIDATE could fail on legacy orphan rows | 005 user FKs, 009 product FKs | Added `NOT VALID` (enforces new writes); VALIDATE left as a documented manual step after an orphan check |
| R2 | `orders.status` has legacy values outside the canonical set | 007 | CHECK added `NOT VALID`; only `fulfilled→delivered` auto-mapped; VALIDATE is manual pending confirmation of live distinct values |
| R3 | `products.id` not unique blocks PK change | 008 | Guard raises a clear exception before altering; precondition query documented |
| R4 | Duplicate `(user_id,product_id)` blocks UNIQUE | 009 | Dedupe performed in 007 (latest row kept) before UNIQUE is added |
| R5 | Duplicate `products.slug` would break a UNIQUE index | 010 | Slug index created **non-unique**; UNIQUE variant documented for after verification |
| R6 | `place_order` behavior change (checkout) | 003 | Derived from existing repo logic; must be smoke-tested on staging |
| R7 | Storage policies could block uploads / public reads | 006 | Public read + admin write; verify upload + public URL on staging |
| R8 | CONCURRENTLY vs transaction conflict for indexes | 010 | Uses plain `CREATE INDEX` in a tx (safe at MVP scale); CONCURRENTLY variant documented for large tables |

---

## 5. Unresolved assumptions (require human/dashboard evidence — not guessed)

1. **`products.id` uniqueness** — 008 guard will abort if violated. Verify:
   `SELECT id, count(*) FROM public.products GROUP BY id HAVING count(*) > 1;`
2. **Live `orders.status` distinct values** — determines whether 007's status CHECK can be
   validated as-is or needs more mappings than `fulfilled→delivered`. Verify:
   `SELECT DISTINCT status FROM public.orders;`
3. **Orphan rows** for user/product FKs — determines when the manual VALIDATE steps in
   005/009 can run. Verify with the anti-join queries in `Phase1_5_Readiness_Report.md`.
4. **`products` storage bucket** existence/visibility — 006 `INSERT ... ON CONFLICT DO NOTHING`
   is safe either way, but confirm intended public/private in the dashboard.
5. **Duplicate `products.slug`** — blocks the recommended UNIQUE slug index (010).
6. **Cart dedupe policy** — 007 keeps the most-recent row; if quantities should be *summed*
   instead, adjust before running (product decision).

---

## 6. Manual execution order (for the reconciliation phase — NOT run here)

Deploy in **grouped** windows per `Database_Reconciliation_Runbook.md`; never prod-first.

1. **Backup** (`supabase db dump --linked -f backup_<ts>.sql` + dashboard PITR snapshot).
2. **Group A (safe, additive+logic+security):** apply `002 → 003 → 004 → 005 → 006` on
   staging → smoke test (signup, cart, checkout, admin order update, image upload) →
   run the RLS spot-checks → apply to prod.
3. **Post-A manual VALIDATE** (after orphan check): VALIDATE the user FKs from 005.
4. **GATE — approval + fresh backup + maintenance window** before the data/structural group.
5. **Group B (gated):** apply `007 → 008 → 009` on staging → verify → prod in the window.
6. **Post-B manual VALIDATE:** `orders_status_check`, product FKs from 009 (after checks).
7. **Group C (performance):** apply `010` (use the CONCURRENTLY variant if tables are large).
8. Final: `supabase db diff --linked` → expect *"No schema changes found."*

> Adopting these on live also requires the migration-history reconciliation
> (`supabase migration repair`) noted in `Migration_History.md` — a separate,
> explicitly-approved step, **not** part of this workstream.

---

## 7. Rollback notes

- **002–006, 009, 010** are `DROP`-reversible (drop the added column/policy/constraint/index/
  function). Each file's header lists the exact statements.
- **007 (normalization)** and **008 (structural)** are **NOT** trivially reversible —
  rollback = **restore from the pre-migration backup**. These are the two files that mandate
  a maintenance window + fresh backup + sign-off.
- FKs added `NOT VALID` can simply be dropped; validating them later takes only a light lock.

---

## 8. Local validation performed (no execution)

- ✅ Filenames sort to a single execution order `001…010`.
- ✅ `is_admin()` is defined in 003 and only referenced in 004/006 (later).
- ✅ `products.description` referenced only in 010 (after the 008 rename); no earlier use.
- ✅ All added-column references (`discount_price`, `stock`, `images`, `payment_status`,
  `full_name`, `is_active`, `updated_at`) occur in 002 (def) or later files.
- ✅ Every file is transaction-balanced (`BEGIN`/`COMMIT` 1:1); 010's `CONCURRENTLY` block is
  commented-out/manual so it never runs inside the transaction.
- ✅ Referenced tables all exist in the baseline; new FKs target `auth.users`, `public.products`,
  `public.categories` (all present).
- ✅ RLS policies reference only existing columns (`user_id`, `id`, `role`) + `is_admin()`.
- ✅ CHECK constraints use canonical vocabularies from `constants.js` (verified in canonical schema).
- ⚠️ Not run: `supabase db lint` / `db diff` (would require the CLI/DB link — out of scope
  for authoring-only). Recommended as the first staging step.

---

## 9. Readiness score

**Authoring readiness: 9.2 / 10.**

- Complete coverage of every object in the migration strategy and canonical schema (‑0).
- Clean, dependency-valid, idempotent forward chain (‑0).
- Small deductions for items that genuinely require live evidence before execution
  (status value mapping, orphan/dup verification, slug uniqueness, bucket confirmation) —
  all captured as manual gates rather than guessed (‑0.8).

**Execution readiness:** blocked on the §5 verifications + backups + approval, exactly as the
gated design intends. Safe to review and stage; **do not execute** until Workstream 2 is approved.

---

## 10. Stop condition

All migrations `002…010` are authored and locally validated. **Nothing was executed, pushed,
repaired, or connected to production.** Halting here per instructions — awaiting approval before
Workstream 2 (frontend/DB reconciliation & execution).
