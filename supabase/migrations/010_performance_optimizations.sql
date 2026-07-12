-- =============================================================================
-- 010_performance_optimizations.sql — Indexes + full-text search
-- Babees Place — Phase 1.7B Workstream 1 forward migration
-- =============================================================================
-- PURPOSE:
--   Add indexes for the common access paths (FK columns, filters, sorts) and a
--   GIN full-text index for product search. Completes Final_Canonical_Schema §5.
--
-- DEPENDENCIES:
--   * 002_additive_columns.sql (products.is_active),
--   * 008_structural_reconciliation.sql (products.description — used by the FTS index).
--
-- RISK: Low. Index creation only. Plain CREATE INDEX briefly locks writes; for
--   LARGE production tables prefer CONCURRENTLY (see the manual block at the end,
--   which MUST be run OUTSIDE a transaction). At current MVP scale plain creation
--   is acceptable.
--
-- ROLLBACK: DROP INDEX IF EXISTS <name>;  (for each index below)
--
-- EXPECTED SCHEMA CHANGES (no data change): indexes only.
--
-- IDEMPOTENCY: CREATE INDEX IF NOT EXISTS throughout; safe to re-run.
-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.
-- =============================================================================

BEGIN;

-- orders ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_orders_user_id     ON public.orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at  ON public.orders (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_status      ON public.orders (status);

-- order_items ----------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_order_items_order_id   ON public.order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON public.order_items (product_id);

-- cart_items / wishlists (composite UNIQUE already covers user_id) ------------
CREATE INDEX IF NOT EXISTS idx_cart_items_product_id ON public.cart_items (product_id);
CREATE INDEX IF NOT EXISTS idx_wishlists_product_id  ON public.wishlists (product_id);

-- products -------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_products_category_id ON public.products (category_id);
CREATE INDEX IF NOT EXISTS idx_products_is_active   ON public.products (is_active);
-- slug lookup (productService.getProduct slug fallback). Canonical recommends a
-- UNIQUE index; created as NON-unique here because slug uniqueness on live is
-- unverified. After confirming no duplicate slugs, replace with:
--   CREATE UNIQUE INDEX CONCURRENTLY idx_products_slug ON public.products (slug) WHERE slug IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_products_slug ON public.products (slug);

-- Full-text search over name + description (storefront search box).
CREATE INDEX IF NOT EXISTS idx_products_search ON public.products
  USING gin (to_tsvector('simple', coalesce(name, '') || ' ' || coalesce(description, '')));

COMMIT;

-- =============================================================================
-- LARGE-TABLE VARIANT (manual). CONCURRENTLY cannot run inside a transaction;
-- run these statements individually instead of the transactional block above if
-- the tables are large enough that a brief write lock is unacceptable:
--
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_user_id ON public.orders (user_id);
--   ... (repeat for each index) ...
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_search ON public.products
--     USING gin (to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(description,'')));
-- =============================================================================
