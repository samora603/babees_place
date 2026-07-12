-- =============================================================================
-- 012_product_management.sql — Product management hardening
-- Babees Place — Phase 2 Workstream 2
-- =============================================================================
-- PURPOSE:
--   * Backfill product/category slugs and enforce uniqueness
--   * Add price validation CHECK constraints
--   * Ensure products.updated_at exists (migration-chain reconciliation)
--
-- DEPENDENCIES: 001–011 applied
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Migration-chain reconciliation: products.updated_at (trigger exists in 003)
-- ---------------------------------------------------------------------------
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- ---------------------------------------------------------------------------
-- Backfill product slugs from name where missing
-- ---------------------------------------------------------------------------
UPDATE public.products
SET slug = lower(
  regexp_replace(
    regexp_replace(trim(name), '[^a-zA-Z0-9]+', '-', 'g'),
    '(^-+|-+$)', '', 'g'
  )
)
WHERE slug IS NULL OR trim(slug) = '';

-- Resolve duplicate product slugs by appending short id suffix
WITH ranked AS (
  SELECT id, slug,
         row_number() OVER (PARTITION BY slug ORDER BY created_at NULLS LAST, id) AS rn
  FROM public.products
  WHERE slug IS NOT NULL AND trim(slug) <> ''
)
UPDATE public.products p
SET slug = p.slug || '-' || left(replace(p.id::text, '-', ''), 8)
FROM ranked r
WHERE p.id = r.id AND r.rn > 1;

-- ---------------------------------------------------------------------------
-- Backfill category slugs from name where missing
-- ---------------------------------------------------------------------------
UPDATE public.categories
SET slug = lower(
  regexp_replace(
    regexp_replace(trim(name), '[^a-zA-Z0-9]+', '-', 'g'),
    '(^-+|-+$)', '', 'g'
  )
)
WHERE slug IS NULL OR trim(slug) = '';

WITH ranked AS (
  SELECT id, slug,
         row_number() OVER (PARTITION BY slug ORDER BY created_at NULLS LAST, id) AS rn
  FROM public.categories
  WHERE slug IS NOT NULL AND trim(slug) <> ''
)
UPDATE public.categories c
SET slug = c.slug || '-' || left(replace(c.id::text, '-', ''), 8)
FROM ranked r
WHERE c.id = r.id AND r.rn > 1;

-- ---------------------------------------------------------------------------
-- UNIQUE slugs (partial index allows legacy nulls during transition)
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS idx_products_slug;
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_slug_unique
  ON public.products (slug) WHERE slug IS NOT NULL AND trim(slug) <> '';

CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_slug_unique
  ON public.categories (slug) WHERE slug IS NOT NULL AND trim(slug) <> '';

-- ---------------------------------------------------------------------------
-- Price validation
-- ---------------------------------------------------------------------------
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_price_nonneg_check;
ALTER TABLE public.products ADD CONSTRAINT products_price_nonneg_check
  CHECK (price IS NULL OR price >= 0) NOT VALID;
ALTER TABLE public.products VALIDATE CONSTRAINT products_price_nonneg_check;

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_discount_lte_price_check;
ALTER TABLE public.products ADD CONSTRAINT products_discount_lte_price_check
  CHECK (
    discount_price IS NULL
    OR price IS NULL
    OR discount_price <= price
  ) NOT VALID;
ALTER TABLE public.products VALIDATE CONSTRAINT products_discount_lte_price_check;

COMMIT;
