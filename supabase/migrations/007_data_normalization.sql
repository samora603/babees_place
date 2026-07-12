-- =============================================================================
-- 007_data_normalization.sql — Data cleanup (APPROVAL-GATED)  (Strategy: M6)
-- Babees Place — Phase 1.7B Workstream 1 forward migration
-- =============================================================================
-- 🛑 GATED: requires a fresh backup + explicit approval + a maintenance window.
--    This migration MUTATES existing production rows. Unlike additive steps it
--    is NOT reversible with DROP — rollback is restore-from-backup.
--
-- PURPOSE:
--   Normalize live data so the canonical constraints can be enforced:
--     * backfill profiles.full_name from auth.users metadata;
--     * normalize profiles.role to ('customer','admin') and enforce a CHECK;
--     * clean/repair products.category_id (drop garbage random UUIDs from the old
--       bad default, then backfill from the products.category text) so the FK in
--       009 can validate;
--     * dedupe cart_items / wishlists on (user_id, product_id) so the UNIQUE in
--       009 can be created;
--     * add orders.status / orders.payment_status CHECKs.
--
-- DEPENDENCIES:
--   * 002_additive_columns.sql (full_name column), 005 (defaults already dropped).
--
-- RISK: Medium–High. Data mutation. Take a backup first. Run the read-only
--   verification queries in Phase1_5_Readiness_Report.md §Manual Steps beforehand.
--
-- ROLLBACK: restore from the pre-migration backup (no in-place reversal).
--
-- EXPECTED SCHEMA/DATA CHANGES:
--   ~ profiles.full_name backfilled; profiles.role normalized
--   ~ products.category_id cleaned + backfilled from products.category
--   ~ duplicate cart_items/wishlists rows removed (latest kept)
--   + CHECK profiles.role, orders.status, orders.payment_status
--
-- IDEMPOTENCY: updates are guarded by WHERE clauses and safe to re-run; DROP
--   CONSTRAINT IF EXISTS before ADD.
-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Backfill profiles.full_name from auth metadata where missing.
-- ---------------------------------------------------------------------------
UPDATE public.profiles p
SET full_name = COALESCE(NULLIF(u.raw_user_meta_data->>'full_name', ''), p.full_name)
FROM auth.users u
WHERE u.id = p.id
  AND (p.full_name IS NULL OR p.full_name = '');

-- ---------------------------------------------------------------------------
-- Normalize profiles.role to the canonical vocabulary, then enforce CHECK.
-- Any legacy value (e.g. 'user') that is not 'admin' collapses to 'customer'.
-- ---------------------------------------------------------------------------
UPDATE public.profiles
SET role = 'customer'
WHERE role IS NULL OR role NOT IN ('customer', 'admin');

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles ADD  CONSTRAINT profiles_role_check
  CHECK (role IN ('customer', 'admin')) NOT VALID;
ALTER TABLE public.profiles VALIDATE CONSTRAINT profiles_role_check;

-- ---------------------------------------------------------------------------
-- Repair products.category_id: the old bad default (gen_random_uuid()) may have
-- left values that reference no category. Null those out, then backfill from the
-- denormalized products.category text by case-insensitive name match. This makes
-- the FK in 009 validatable.
-- ---------------------------------------------------------------------------
UPDATE public.products
SET category_id = NULL
WHERE category_id IS NOT NULL
  AND category_id NOT IN (SELECT id FROM public.categories);

UPDATE public.products p
SET category_id = c.id
FROM public.categories c
WHERE p.category_id IS NULL
  AND p.category IS NOT NULL
  AND lower(p.category) = lower(c.name);

-- ---------------------------------------------------------------------------
-- Dedupe cart_items / wishlists on (user_id, product_id) — keep the most recent
-- row so the UNIQUE constraint in 009 can be added.
-- ---------------------------------------------------------------------------
DELETE FROM public.cart_items
WHERE ctid NOT IN (
  SELECT DISTINCT ON (user_id, product_id) ctid
  FROM public.cart_items
  ORDER BY user_id, product_id, created_at DESC NULLS LAST, ctid
);

DELETE FROM public.wishlists
WHERE ctid NOT IN (
  SELECT DISTINCT ON (user_id, product_id) ctid
  FROM public.wishlists
  ORDER BY user_id, product_id, created_at DESC NULLS LAST, ctid
);

-- ---------------------------------------------------------------------------
-- orders.payment_status CHECK. All rows were defaulted to 'pending' in 002, so
-- VALIDATE is safe here.
-- ---------------------------------------------------------------------------
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_payment_status_check;
ALTER TABLE public.orders ADD  CONSTRAINT orders_payment_status_check
  CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')) NOT VALID;
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_payment_status_check;

-- ---------------------------------------------------------------------------
-- orders.status CHECK. Map the one known legacy enum value; add NOT VALID.
-- VALIDATE is left MANUAL because the full set of historical status values on
-- live is an unresolved assumption (see authoring report). Confirm the live
-- distinct values, map any strays, then:
--   ALTER TABLE public.orders VALIDATE CONSTRAINT orders_status_check;
-- ---------------------------------------------------------------------------
UPDATE public.orders SET status = 'delivered'  WHERE status = 'fulfilled';
-- (No automatic mapping for 'paid' -> keep as data decision; see report.)
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD  CONSTRAINT orders_status_check
  CHECK (status IN ('pending', 'processing', 'shipped', 'delivered', 'cancelled')) NOT VALID;

COMMIT;
