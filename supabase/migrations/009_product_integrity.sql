-- =============================================================================
-- 009_product_integrity.sql — Product FKs + UNIQUE + category FK  (Strategy: M5b)
-- Babees Place — Phase 1.7B Workstream 1 forward migration
-- =============================================================================
-- PURPOSE:
--   The integrity constraints that depend on the gated steps:
--     * product-referencing FKs (need products single-column PK from 008);
--     * UNIQUE (user_id, product_id) on cart_items/wishlists (need dedupe from 007);
--     * products.category_id -> categories(id) FK (needs category_id repair in 007).
--
-- DEPENDENCIES:
--   * 008_structural_reconciliation.sql (products PK on (id)).
--   * 007_data_normalization.sql (dedupe + category_id repair).
--
-- RISK: Medium–High. Product FKs are added NOT VALID to avoid failing on orphan
--   product_id values; VALIDATE is a documented manual step. The UNIQUEs will
--   fail if duplicates remain — 007 must have run.
--
-- ROLLBACK:
--   ALTER TABLE ... DROP CONSTRAINT IF EXISTS <name>;  -- for each FK/UNIQUE
--
-- EXPECTED SCHEMA CHANGES (no data change):
--   + FK (NOT VALID): cart_items.product_id, wishlists.product_id -> products(id) CASCADE
--   + FK (NOT VALID): order_items.product_id -> products(id) ON DELETE SET NULL
--   + FK (validated): products.category_id -> categories(id) ON DELETE SET NULL
--   + UNIQUE: cart_items(user_id, product_id), wishlists(user_id, product_id)
--
-- IDEMPOTENCY: DROP CONSTRAINT IF EXISTS before each ADD.
-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Product-referencing FKs (NOT VALID). MANUAL VALIDATE after orphan check:
--   ALTER TABLE public.cart_items  VALIDATE CONSTRAINT cart_items_product_id_fkey;
--   ALTER TABLE public.wishlists   VALIDATE CONSTRAINT wishlists_product_id_fkey;
--   ALTER TABLE public.order_items VALIDATE CONSTRAINT order_items_product_id_fkey;
-- ---------------------------------------------------------------------------
ALTER TABLE public.cart_items  DROP CONSTRAINT IF EXISTS cart_items_product_id_fkey;
ALTER TABLE public.cart_items  ADD  CONSTRAINT cart_items_product_id_fkey
  FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE NOT VALID;

ALTER TABLE public.wishlists   DROP CONSTRAINT IF EXISTS wishlists_product_id_fkey;
ALTER TABLE public.wishlists   ADD  CONSTRAINT wishlists_product_id_fkey
  FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE NOT VALID;

-- order_items keeps its product reference but survives product deletion (snapshot).
ALTER TABLE public.order_items DROP CONSTRAINT IF EXISTS order_items_product_id_fkey;
ALTER TABLE public.order_items ADD  CONSTRAINT order_items_product_id_fkey
  FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL NOT VALID;

-- ---------------------------------------------------------------------------
-- category FK. 007 guarantees category_id is NULL or references a real category,
-- so this can be validated immediately.
-- ---------------------------------------------------------------------------
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_category_id_fkey;
ALTER TABLE public.products ADD  CONSTRAINT products_category_id_fkey
  FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE SET NULL NOT VALID;
ALTER TABLE public.products VALIDATE CONSTRAINT products_category_id_fkey;

-- ---------------------------------------------------------------------------
-- Upsert-enabling UNIQUE constraints (dedupe performed in 007).
-- ---------------------------------------------------------------------------
ALTER TABLE public.cart_items DROP CONSTRAINT IF EXISTS cart_items_user_product_key;
ALTER TABLE public.cart_items ADD  CONSTRAINT cart_items_user_product_key
  UNIQUE (user_id, product_id);

ALTER TABLE public.wishlists  DROP CONSTRAINT IF EXISTS wishlists_user_product_key;
ALTER TABLE public.wishlists  ADD  CONSTRAINT wishlists_user_product_key
  UNIQUE (user_id, product_id);

COMMIT;
