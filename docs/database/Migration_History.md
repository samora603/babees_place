# Migration History

**Last updated:** 2026-07-12 (Phase 1.7B WS4 — Final Validation; forward migrations 002–010 recorded)
**Live project:** `qfcygrxrfszcdltangec` ("Babis-place")
**Live migration history:** **empty** — the live database was built manually; no migration
has ever been recorded on the remote `supabase_migrations.schema_migrations` table.

This document is the authoritative record of the repository's migration files and their
status. Classification values: **Active** (part of the forward sequence), **Archived**
(preserved for history, never applied), **Deprecated** (superseded/fictional; do not apply).

---

## Active migration sequence

Forward migrations `002`–`010` were authored in Phase 1.7B Workstream 1, reviewed in WS1
Review, and validated in WS3/WS4. They are **authored and locally validated only** — none has
been applied to live (live migration history is still empty; see below). The `Strategy ID`
column maps each file to the `M0..M8` plan in `Migration_Strategy.md`.

| Order | Version / File | Strategy ID | Purpose | Applied on live? |
|---|---|---|---|---|
| 1 | `001_initial_schema.sql` | M0 | Official baseline — faithful snapshot of the live `public` schema (7 tables, `order_status` enum, PKs, 2 FKs, RLS enable, 10 policies, grants). Only a provenance header was added. | **No** (requires `migration repair`) |
| 2 | `002_additive_columns.sql` | M1 | Add app-expected columns (profiles `full_name`/`updated_at`; orders `payment_status`/`note`/`updated_at`; products `stock`/`discount_price`/`image_url`/`images`/`is_active`; order_items `image_url`/`created_at`). | No |
| 3 | `003_functions_and_triggers.sql` | M4 | `is_admin()`, `handle_new_user()`+trigger, `set_updated_at()`+triggers, `place_order()`; revoke anon EXECUTE on `place_order`. | No |
| 4 | `004_rls_and_security.sql` | M2 + M3 | Profiles role-escalation fix (`WITH CHECK` + admin policy); owner policies for cart_items/wishlists; public/admin for categories/products; remove direct order INSERT; broaden order_items SELECT to owner-or-admin. | No |
| 5 | `005_integrity_constraints.sql` | M5a | Drop bad defaults; `created_at DEFAULT now()`; user_id FKs → auth.users (NOT VALID); `CHECK (quantity > 0)`. | No |
| 6 | `006_storage_policies.sql` | M8 | Ensure `products` bucket; storage.objects policies (public read / admin write). | No |
| 7 | `007_data_normalization.sql` 🛑 | M6 | **Gated.** Backfill full_name; normalize role + CHECK; repair category_id; dedupe cart/wishlist; status/payment_status CHECKs. | No |
| 8 | `008_structural_reconciliation.sql` 🛑 | M7 | **Gated.** products PK `(id,name)`→`(id)`; rename `"Description"`→`description`; drop unused `order_status` enum. | No |
| 9 | `009_product_integrity.sql` | M5b | Product-referencing FKs (NOT VALID); category_id FK (validated); `UNIQUE(user_id, product_id)` on cart_items/wishlists. | No |
| 10 | `010_performance_optimizations.sql` | (M5 indexes / §5) | Indexes for FK/filter/sort paths + GIN full-text search on products. | No |

🛑 = approval-gated (backup + maintenance window; mutates data / structure).

> **Execution order note:** the file order `001→010` is the authoritative linear apply order
> (validated: no circular dependencies). It linearizes the `Migration_Strategy.md` group
> narrative (`M0→M1→M3→M2→M4→M5→M8→M6→M7`); `003` (M4) precedes `004` (M2+M3) because the
> canonical M3 admin-role policy depends on `is_admin()` (M4). The Critical role-escalation
> fix still lands at `004`, before any gated/data migration.

---

## Archived / deprecated migrations

Located in `supabase/migrations/archive/` (see its `README.md`). **None were ever applied to
live** and none may be applied.

| File | Classification | Reason | Intent carried forward as |
|---|---|---|---|
| `001_schema_rls_place_order.sql` | Deprecated (fictional) | Never-applied idealized schema; diverges from live on tables, columns, PKs, and functions | Baseline (`001_initial_schema.sql`) + `M1`/`M4` |
| `002_phase1_security_hardening.sql` | Deprecated | Forward-fix targeting the fictional `001`; objects absent on live; `DO NOT APPLY AS-IS` header | `M3` (profiles role escalation) + `M2` (RLS) |
| `003_phase1_indexes_constraints.sql` | Deprecated | Forward-fix targeting the fictional `001`; references non-existent live columns/tables | `M5` (FK/UNIQUE/CHECK/index) |
| `20260617042152_remote_schema.sql` | Archived (empty placeholder) | 0-byte artifact of an earlier empty `db pull` | Replaced by the baseline |

---

## Provenance

- The baseline was generated read-only in Phase 1.6 Workstream A via
  `supabase db dump --linked -s public` and verified in
  `docs/database/Baseline_Migration_Verification.md`.
- The pristine generated artifact remains at
  `docs/database/generated_baseline/001_initial_schema.sql` (unmodified source of truth).
- The adopted copy at `supabase/migrations/001_initial_schema.sql` is byte-identical to that
  artifact except for an added provenance comment header.

---

## Naming convention

- Baseline and the Phase 1.7B forward migrations use the numeric `NNN_` prefix
  (`001`–`010`) to match all approved planning documents and to keep a single, obvious
  linear apply order. This scheme is the adopted convention for this project.
- `snake_case`, descriptive names; one logical change set per migration.
- Any **future** migrations authored after this set may either continue the numeric scheme
  (`011_…`) or use Supabase timestamped versions (`<YYYYMMDDHHMMSS>_<description>.sql`) — but
  must sort **after** `010`.

---

## Remaining work before the forward migrations can be applied to live

Forward migrations `002`–`010` are **authored and validated**; the following steps gate their
**application** (all deferred to Phase 1.8 — Staging Database Reconciliation):

1. **Adopt baseline on live** (reconciliation, not done here): run
   `supabase migration repair --status applied 001` so the live history records the baseline,
   then confirm `supabase db diff --linked` is clean. (Runbook Stage 2 / `M0`.)
2. Run the four read-only verifications (product `id` uniqueness, cart/wishlist duplicates,
   storage bucket existence/visibility, distinct `orders.status` + `profiles.role`) — these
   gate the high-risk migrations `007`/`008`/`009`.
3. Obtain approvals + backup + maintenance window for `007` (M6) and `008` (M7)
   (see `Phase1_6_Execution_Readiness.md`).
4. Apply on staging first, run the post-apply `VALIDATE CONSTRAINT` steps and smoke tests,
   then push to production per the Runbook order.

---

## Phase 2 forward migrations (authored)

| Order | File | Purpose | Applied on live? |
|---|---|---|---|
| 11 | `011_product_management.sql` | Product admin enhancements | No |
| 12 | `012_inventory.sql` | Inventory tracking | No |
| 13 | `013_order_fulfillment.sql` | Pickup locations, delivery JSONB, order events | No |
| 14 | `014_customer_profile.sql` | Saved addresses + account preferences (WS5 M5.1) | No |
| 15 | `015_recommendations.sql` | `get_bestseller_product_ids` RPC for storefront trending (WS5 M5.3) | No |
| 16 | `016_payments.sql` | Payments + payment_events, order payment_method/receipt, finalize RPCs (WS6) | No |
| 17 | `017_notifications.sql` | Notifications inbox, templates, deliveries, preferences, admin fan-out RPCs (WS7) | No |
| 18 | `018_promotions_loyalty.sql` | Promotions, coupons, loyalty, gift cards, referrals; extended place_order (WS8) | No |
| 19 | `019_operations.sql` | Admin audit logs + write_admin_audit RPC (WS9) | No |

> **WS5 Milestone 5.2 (Faster Checkout)** — no new migration; uses `014` profile tables plus existing cart/order schema.
