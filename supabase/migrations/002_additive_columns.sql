-- =============================================================================
-- 002_additive_columns.sql — Additive schema columns  (Strategy: M1)
-- Babees Place — Phase 1.7B Workstream 1 forward migration
-- =============================================================================
-- PURPOSE:
--   Add the columns the application already expects but that are missing on the
--   live schema, WITHOUT touching existing data. Unblocks the majority of the
--   frontend/service reconciliation (products stock/pricing/images, order
--   payment status, profile full_name, order-item snapshot fields).
--
-- DEPENDENCIES:
--   * 001_initial_schema.sql (baseline) only.
--
-- RISK: Low. Purely additive (ADD COLUMN IF NOT EXISTS). New NOT NULL columns
--   all carry defaults, so existing rows are backfilled automatically.
--
-- ROLLBACK:
--   Drop only the columns introduced here, e.g.:
--     ALTER TABLE public.products    DROP COLUMN IF EXISTS stock, ... ;
--     ALTER TABLE public.orders      DROP COLUMN IF EXISTS payment_status, ... ;
--     ALTER TABLE public.profiles    DROP COLUMN IF EXISTS full_name, updated_at;
--     ALTER TABLE public.order_items DROP COLUMN IF EXISTS image_url, created_at;
--   No data migration to reverse (defaults only).
--
-- EXPECTED SCHEMA CHANGES:
--   profiles    += full_name, updated_at
--   orders      += payment_status, note, updated_at
--   products    += stock, discount_price, image_url, images, is_active
--   order_items += image_url, created_at
--   (Phase-2 order columns delivery_type/pickup_location/delivery_address/
--    mpesa_receipt_number are intentionally deferred — see authoring report.)
--
-- IDEMPOTENCY: ADD COLUMN IF NOT EXISTS throughout; safe to re-run.
-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.
-- =============================================================================

BEGIN;

-- profiles -------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS full_name  text,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

-- orders ---------------------------------------------------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS note           text,
  ADD COLUMN IF NOT EXISTS updated_at     timestamptz NOT NULL DEFAULT now();

-- products -------------------------------------------------------------------
-- is_active is included per Final_Canonical_Schema §4.3 (D-PROD-11, additive &
-- non-blocking); see authoring report for the note that no frontend read exists
-- yet — the column is introduced ahead of app support and is harmless.
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS stock          integer      NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS discount_price numeric(12,2),
  ADD COLUMN IF NOT EXISTS image_url      text,
  ADD COLUMN IF NOT EXISTS images         jsonb        NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS is_active      boolean      NOT NULL DEFAULT true;

-- order_items ----------------------------------------------------------------
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS image_url  text,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

COMMIT;
