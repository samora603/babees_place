-- =============================================================================
-- 005_integrity_constraints.sql — Defaults, user FKs, quantity CHECKs  (Strategy: M5a)
-- Babees Place — Phase 1.7B Workstream 1 forward migration
-- =============================================================================
-- PURPOSE:
--   Restore data integrity for the parts that DO NOT depend on the gated
--   structural changes (M7 PK) or the gated data normalization (M6 dedupe):
--     * remove the erroneous live defaults (gen_random_uuid() on FK columns,
--       the literal phone default) so future inserts cannot fabricate bad keys;
--     * add foreign keys from user_id columns to auth.users (NOT VALID — enforced
--       for new/updated rows immediately, existing rows checked later);
--     * add CHECK (quantity > 0) to cart_items and order_items.
--   Product-referencing FKs, the (user_id, product_id) UNIQUEs, and the
--   category FK live in 009_product_integrity.sql because they depend on the
--   products PK change (008) and the dedupe (007).
--
-- DEPENDENCIES:
--   * 002_additive_columns.sql (no direct column dependency, but ordered after it).
--
-- RISK: Medium. FKs are added NOT VALID to avoid failing on any pre-existing
--   orphan rows; VALIDATE is left as a documented manual step (run after the
--   orphan check in Phase1_5_Readiness_Report.md §Manual Steps). Dropping a
--   default never touches stored data.
--
-- ROLLBACK:
--   ALTER TABLE ... DROP CONSTRAINT IF EXISTS <name>;   -- for each FK/CHECK
--   (Re-adding the old bad defaults is intentionally NOT provided.)
--
-- EXPECTED SCHEMA CHANGES (no data change):
--   - drop DEFAULT on: cart_items.user_id/product_id, wishlists.user_id/product_id,
--     orders.user_id, order_items.order_id/product_id, products.category_id,
--     profiles.phone
--   ~ set created_at DEFAULT now() on cart_items/orders/products/profiles/
--     categories/wishlists (replaces frozen literal defaults)
--   + FK (NOT VALID): orders.user_id, cart_items.user_id, wishlists.user_id -> auth.users
--   + CHECK (quantity > 0): cart_items, order_items
--
-- IDEMPOTENCY: DROP DEFAULT is a no-op if absent; DROP CONSTRAINT IF EXISTS before ADD.
-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Remove erroneous live defaults (D-KEY-5). FK/identity columns must never
-- auto-generate a random value; phone must not default to a literal.
-- ---------------------------------------------------------------------------
ALTER TABLE public.cart_items  ALTER COLUMN user_id    DROP DEFAULT;
ALTER TABLE public.cart_items  ALTER COLUMN product_id DROP DEFAULT;
ALTER TABLE public.wishlists   ALTER COLUMN user_id    DROP DEFAULT;
ALTER TABLE public.wishlists   ALTER COLUMN product_id DROP DEFAULT;
ALTER TABLE public.orders      ALTER COLUMN user_id    DROP DEFAULT;
ALTER TABLE public.order_items ALTER COLUMN order_id   DROP DEFAULT;
ALTER TABLE public.order_items ALTER COLUMN product_id DROP DEFAULT;
ALTER TABLE public.products    ALTER COLUMN category_id DROP DEFAULT;
ALTER TABLE public.profiles    ALTER COLUMN phone      DROP DEFAULT;

-- ---------------------------------------------------------------------------
-- Fix hard-coded timestamp defaults (D-KEY-5 / Schema_Comparison_Matrix §5).
-- The baseline froze created_at to literal 2026 values, so new rows would all
-- receive the same past timestamp; categories/wishlists had no default at all.
-- Set them to now() per Final_Canonical_Schema §3. Existing rows are NOT touched
-- (defaults only affect future inserts) — data is preserved. Column TYPE is left
-- as-is (timestamptz standardization is an optional follow-up per the matrix).
-- ---------------------------------------------------------------------------
ALTER TABLE public.cart_items ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.orders     ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.products   ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.profiles   ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.categories ALTER COLUMN created_at SET DEFAULT now();
ALTER TABLE public.wishlists  ALTER COLUMN created_at SET DEFAULT now();

-- ---------------------------------------------------------------------------
-- User foreign keys -> auth.users (D-KEY-2). Added NOT VALID so the migration
-- cannot fail on legacy orphan rows; new/updated rows are enforced immediately.
--
-- MANUAL (post-check, after confirming zero orphans on staging/prod):
--   ALTER TABLE public.orders     VALIDATE CONSTRAINT orders_user_id_fkey;
--   ALTER TABLE public.cart_items VALIDATE CONSTRAINT cart_items_user_id_fkey;
--   ALTER TABLE public.wishlists  VALIDATE CONSTRAINT wishlists_user_id_fkey;
-- ---------------------------------------------------------------------------
ALTER TABLE public.orders     DROP CONSTRAINT IF EXISTS orders_user_id_fkey;
ALTER TABLE public.orders     ADD  CONSTRAINT orders_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;

ALTER TABLE public.cart_items DROP CONSTRAINT IF EXISTS cart_items_user_id_fkey;
ALTER TABLE public.cart_items ADD  CONSTRAINT cart_items_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;

ALTER TABLE public.wishlists  DROP CONSTRAINT IF EXISTS wishlists_user_id_fkey;
ALTER TABLE public.wishlists  ADD  CONSTRAINT wishlists_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;

-- ---------------------------------------------------------------------------
-- Quantity CHECKs (D-KEY-4). quantity > 0 is expected to already hold, so we
-- add NOT VALID then VALIDATE within this migration.
-- ---------------------------------------------------------------------------
ALTER TABLE public.cart_items  DROP CONSTRAINT IF EXISTS cart_items_quantity_check;
ALTER TABLE public.cart_items  ADD  CONSTRAINT cart_items_quantity_check
  CHECK (quantity > 0) NOT VALID;
ALTER TABLE public.cart_items  VALIDATE CONSTRAINT cart_items_quantity_check;

ALTER TABLE public.order_items DROP CONSTRAINT IF EXISTS order_items_quantity_check;
ALTER TABLE public.order_items ADD  CONSTRAINT order_items_quantity_check
  CHECK (quantity > 0) NOT VALID;
ALTER TABLE public.order_items VALIDATE CONSTRAINT order_items_quantity_check;

COMMIT;
