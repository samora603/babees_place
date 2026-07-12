# Migration Strategy — Live Database Reconciliation

**Date:** 2026-07-12
**Status:** STRATEGY ONLY. **No migrations are generated or applied in this phase.**
**Basis:** `Schema_Comparison_Matrix.md`, `Canonical_Schema_Proposal.md`, `Frontend_Database_Compatibility.md`.

**Principles:** additive-first, non-destructive by default, destructive steps gated on
explicit approval + verified preconditions, every step independently reversible.

---

## Ordering rationale

1. **Baseline first** — capture reality before changing anything (`db pull`).
2. **Additive schema** next — safe `ADD COLUMN`/`ADD TABLE`; unblocks most code.
3. **Access (RLS/policies)** — make the additive schema usable and secure.
4. **Functions/triggers** — depend on the columns from step 2.
5. **Constraints/indexes** — depend on data being clean (dedupe checks).
6. **Destructive/normalization** — PK change, renames, role normalization — LAST, gated.

Each numbered migration below is a *plan*, not a file. Names use timestamp-prefix
convention (`<ts>_<slug>.sql`) that `supabase migration new` will generate.

---

## M0 — Baseline capture (no schema change)
- **Purpose:** Record the true current live schema in version control.
- **Command (human):** `supabase db pull` → creates `<ts>_remote_schema.sql`; delete the
  empty `20260617042152_remote_schema.sql`; retire the fictional `001` (or keep as history
  with a note — see ADR-001).
- **Dependencies:** none.
- **Rollback:** delete the generated file (no DB effect; pull is read-only).
- **Data migration:** No. **Risk:** Low.

## M1 — Additive columns (non-destructive)
- **Purpose:** Add columns the app needs without touching existing data.
- **Contents:**
  - `profiles`: `full_name text`, `updated_at timestamptz default now()`.
  - `orders`: `payment_status text default 'pending'`, `note text`, `updated_at timestamptz default now()`.
  - `products`: `stock int not null default 0`, `discount_price numeric`, `image_url text`, `images jsonb`.
  - `order_items`: `image_url text`, `created_at timestamptz default now()`.
- **Dependencies:** M0.
- **Rollback:** `ALTER TABLE ... DROP COLUMN ...` (only newly added columns).
- **Data migration:** backfill defaults (automatic); optional `full_name` backfill from
  `auth.users.raw_user_meta_data` (see M6). **Risk:** Low.

## M2 — RLS policies for deny-all / missing tables
- **Purpose:** Make `cart_items`, `wishlists`, `categories` usable and secure; allow admin
  product writes.
- **Contents:**
  - `cart_items`: `FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id)`.
  - `wishlists`: same owner policy.
  - `categories`: `FOR SELECT USING (true)`; admin write via `is_admin()` (needs M4).
  - `products`: keep public SELECT; add admin write policy via `is_admin()`.
- **Dependencies:** M4 for `is_admin()` in admin policies (or inline the role check first,
  then swap to `is_admin()`).
- **Rollback:** `DROP POLICY ...`.
- **Data migration:** No. **Risk:** Low–Med (verify no legitimate access is broken).

## M3 — Security hardening: profiles role escalation (CRITICAL, live-compatible)
- **Purpose:** Close C-1 (self-escalation). Matches the **actual** live policy name.
- **Contents:**
  - Drop/recreate `"Users can update their own profile"` with
    `WITH CHECK (auth.uid() = id AND role = (SELECT role FROM profiles WHERE id = auth.uid()))`.
  - Add `"Admins can update any profile"` via `is_admin()` (needs M4) for role changes.
- **Dependencies:** M4 (for the admin variant); the user-restriction part is standalone and
  can ship immediately.
- **Rollback:** restore prior policy (USING-only).
- **Data migration:** No. **Risk:** Low (behavioral: blocks role self-edit).

## M4 — Functions + triggers
- **Purpose:** Recreate known server logic against the canonical schema.
- **Contents:**
  - `is_admin()` (SECURITY DEFINER, reads `profiles.role`).
  - `handle_new_user()` + `on_auth_user_created` trigger (autocreate profile; set role
    `'customer'`).
  - `place_order(uuid)` — rewritten for live columns (`orders.total`, `products.stock`/
    `discount_price`, `order_items` snapshot columns, `cart_items`), with `FOR UPDATE`
    row locking. **Derived from repo 001 — not fabricated.**
  - `set_updated_at()` + triggers on `orders`, `profiles`.
- **Dependencies:** M1 (columns must exist).
- **Rollback:** `DROP FUNCTION/TRIGGER ...`.
- **Data migration:** No. **Risk:** Med (checkout depends on `place_order`; test on staging).

## M5 — Foreign keys, UNIQUE, CHECK, indexes (data-dependent)
- **Purpose:** Restore integrity + performance.
- **Contents:**
  - FKs: `orders.user_id`→auth.users, `cart_items.user_id/product_id`,
    `order_items.product_id`, `wishlists.user_id/product_id` (all after PK fix M7 for
    product references).
  - `UNIQUE(user_id, product_id)` on `cart_items`, `wishlists` (**dedupe first**).
  - `CHECK (quantity > 0)` on `cart_items`, `order_items`.
  - Indexes: `orders(user_id)`, `orders(created_at)`, `order_items(order_id)`,
    `order_items(product_id)`, `cart_items(product_id)`.
  - Remove bad `DEFAULT gen_random_uuid()` on FK columns.
- **Dependencies:** M1, M7 (for product FKs).
- **Rollback:** drop constraints/indexes.
- **Data migration:** **Dedupe** cart/wishlist duplicates before UNIQUE. **Risk:** Med
  (constraint adds fail on dirty data — run validation queries first).

## M6 — Data normalization (APPROVAL-GATED)
- **Purpose:** Clean values so constraints validate and data is consistent.
- **Contents:**
  - Backfill `profiles.full_name` from auth metadata.
  - Normalize `profiles.role` to `('customer','admin')`; then `VALIDATE` the role CHECK.
  - Backfill `products.category_id` from `products.category` text (name match) — then treat
    text column as deprecated.
- **Dependencies:** M1, categories model decision.
- **Rollback:** data-restore from backup (normalization is not trivially reversible).
- **Data migration:** **Yes.** **Risk:** Med–High → requires backup + approval.

## M7 — Structural changes (APPROVAL-GATED, DESTRUCTIVE-CLASS)
- **Purpose:** Fix the composite PK and rename anomalies.
- **Contents:**
  - `products` PK `(id, name)` → `(id)` — **precondition:** verify `id` uniqueness
    (`SELECT id, count(*) FROM products GROUP BY id HAVING count(*)>1`).
  - Rename `products."Description"` → `description` (add `description`, copy, drop old).
  - (Optional, only if Path B chosen) rename tables `cart_items`→`cart`, `wishlists`→`wishlist`.
- **Dependencies:** all prior; a maintenance window.
- **Rollback:** restore from backup; PK/rename reversals are complex.
- **Data migration:** Possibly. **Risk:** **High.** Do last, with backup + approval.

## M8 — Storage
- **Purpose:** Secure the image bucket.
- **Contents:** verify/create `products` bucket; add `storage.objects` policies (public read
  for `products`, admin-only write). Fix client `getPublicUrl` usage (code side).
- **Dependencies:** M4 (`is_admin()`), dashboard verification of bucket.
- **Rollback:** drop the added storage policies.
- **Data migration:** No. **Risk:** Med.

---

## Deferred (feature decisions, NOT stabilization)
- `payments` table + real payment integration.
- `pickup_locations` table.
- `addresses` table (referenced by `userService`).
Until decided, the corresponding **code paths must be guarded/disabled** (see compat audit).

---

## Cross-cutting: frontend changes paired with each DB step
The reconciliation should ship DB + code together per area to avoid a broken window:
- M1/M4 ↔ order/admin/product code reads new columns + RPC.
- M2/M3 ↔ cart/wishlist services renamed to `cart_items`/`wishlists`.
- M8 ↔ `adminService.uploadImages` `getPublicUrl` fix.

## Validation after each migration
- `supabase db diff --linked` → expect "no changes" once repo == live.
- `supabase migration list --linked` → local and Remote columns aligned.
- Smoke test: signup→profile, browse→cart→checkout, admin order update, image upload.

## Production deployment order

Per migration group, deploy in this exact order (never prod-first):

1. **Backup** prod (`db dump` + dashboard PITR snapshot).
2. Apply the migration on **staging** (or a `db branch`) → run smoke + RLS checks.
3. `supabase db diff --linked` on staging → confirm intended delta only.
4. Ship the **paired frontend change** to staging; verify the affected flow.
5. Apply to **production** via `supabase db push` during the agreed window.
6. Deploy the frontend change to production.
7. Post-deploy smoke test on production; monitor logs.

Group sequence across the whole reconciliation:
`M0 (baseline) → M1 (additive cols) → M3 (critical security) → M2 (RLS) → M4 (functions/triggers) → M5 (FK/UNIQUE/index) → M8 (storage) → M6 (normalization, window) → M7 (structural, window)`.

> M3 is intentionally pulled early (right after additive columns) so the Critical
> role-escalation gap closes before the larger changes land. M6/M7 (the only
> non-`DROP`-reversible steps) come last, each in a maintenance window with a fresh backup.

## Validation checklist (per migration group)

- [ ] Fresh backup taken and location recorded.
- [ ] Applied on staging first; no errors.
- [ ] `supabase db diff --linked` shows only the intended change.
- [ ] `supabase migration list --linked` shows the migration on Local **and** Remote.
- [ ] Paired frontend change deployed; affected flow works (signup / cart / checkout / admin / upload).
- [ ] RLS spot-checks as a normal user: cannot set own `role`; cannot read others' orders; cannot insert `order_items` directly.
- [ ] CI green (`npm ci && lint && test && build`).
- [ ] After full reconciliation: `db diff` returns *"No schema changes found"*.

## Global rollback posture
- **Every step preceded by a backup** (`supabase db dump --linked -f backup_<ts>.sql`).
- Additive steps (M1–M5, M8) reverse via `DROP`.
- Normalization/structural (M6, M7) reverse only via **restore from backup** → these are the
  steps that most require a maintenance window and sign-off.
