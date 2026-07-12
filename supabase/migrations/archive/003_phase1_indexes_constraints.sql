-- =============================================================================
-- Babis Place — Phase 1 Indexes, Constraints & Triggers
-- =============================================================================
-- 🛑 DO NOT APPLY AS-IS. Verified 2026-07-12 against the live project: the LIVE
-- schema differs from migration 001. This file references `public.cart` (live has
-- `cart_items`), `orders.payment_status` and `orders.updated_at` and
-- `profiles.updated_at` (none exist live), so several statements will ERROR.
-- Reconcile the migration strategy first — see
-- docs/audits/Phase1_Final_Closure_Report.md (Migration Status).
--
-- STATUS: MANUAL-APPLY ONLY. Authored during Phase 1; NOT applied to any live
-- database by tooling. Apply only after taking a backup and after generating
-- the baseline migration (`supabase db pull`). Review each statement first.
--
-- Addresses:
--   * F-04 (MEDIUM) — missing indexes on foreign-key / filter columns.
--   * F-14 (MEDIUM) — missing CHECK constraints on order status columns and a
--                     shared updated_at trigger.
--
-- Scope note: only tables that exist in version-controlled migrations (orders,
-- order_items, cart, profiles) are covered here. Indexes and full-text search
-- for `products` are intentionally left OUT because the products table is not
-- yet in the repo (see docs/audits/Database_Audit.md and the "products" block
-- at the bottom of this file, which is commented out until the baseline exists).
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- F-04: Indexes for common access paths.
-- CREATE INDEX IF NOT EXISTS is safe to re-run. Consider CONCURRENTLY on large
-- production tables (must be run OUTSIDE a transaction — see note below).
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON public.orders (user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders (status);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON public.order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON public.order_items (product_id);
CREATE INDEX IF NOT EXISTS idx_cart_product_id ON public.cart (product_id);
-- cart already has UNIQUE (user_id, product_id); that composite covers user_id.

-- -----------------------------------------------------------------------------
-- F-14: Status / payment_status CHECK constraints.
-- Added as NOT VALID so the statement will not fail on pre-existing rows that
-- may contain out-of-range values. After confirming/cleaning existing data,
-- run the VALIDATE CONSTRAINT statements (kept commented) to enforce fully.
-- Adjust the allowed value lists to match the application's real states.
-- -----------------------------------------------------------------------------
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
  CHECK (status IN ('pending', 'processing', 'paid', 'shipped', 'delivered', 'cancelled'))
  NOT VALID;

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_payment_status_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_payment_status_check
  CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded'))
  NOT VALID;

-- After verifying existing rows conform, enforce on all rows:
-- ALTER TABLE public.orders VALIDATE CONSTRAINT orders_status_check;
-- ALTER TABLE public.orders VALIDATE CONSTRAINT orders_payment_status_check;

-- -----------------------------------------------------------------------------
-- F-14: Shared updated_at trigger.
-- orders and profiles both have an updated_at column that is never maintained.
-- This trigger sets it on every UPDATE.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_orders_updated_at ON public.orders;
CREATE TRIGGER set_orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
CREATE TRIGGER set_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

COMMIT;

-- =============================================================================
-- PRODUCTS (deferred — requires the baseline migration first)
-- =============================================================================
-- Once `supabase db pull` has captured the products table, add these OUTSIDE a
-- transaction (CONCURRENTLY cannot run inside BEGIN/COMMIT):
--
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_category
--     ON public.products (category_id);
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_active
--     ON public.products (is_active);
--
--   -- Full-text search for the storefront search box (F-04):
--   ALTER TABLE public.products ADD COLUMN IF NOT EXISTS search_tsv tsvector
--     GENERATED ALWAYS AS (
--       to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(description,''))
--     ) STORED;
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_search_tsv
--     ON public.products USING gin (search_tsv);
-- =============================================================================
