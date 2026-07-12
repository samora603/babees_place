-- =============================================================================
-- 008_structural_reconciliation.sql — Products PK + column rename (APPROVAL-GATED)  (Strategy: M7)
-- Babees Place — Phase 1.7B Workstream 1 forward migration
-- =============================================================================
-- 🛑 GATED: requires a fresh backup + explicit approval + a maintenance window.
--    Structural/destructive-class change on `products`. Rollback is
--    restore-from-backup.
--
-- PURPOSE:
--   * Change products PK from composite (id, name) to (id) so single-column FKs
--     (009) and single-row .eq('id') guarantees work. PRECONDITION: id is unique.
--   * Rename products."Description" -> description (canonical snake_case).
--
-- DEPENDENCIES:
--   * 007_data_normalization.sql (ordered after gated data cleanup).
--   * No FK references products yet (product FKs are added in 009), so the PK can
--     be swapped safely here.
--
-- RISK: High. Briefly locks products. The id-uniqueness guard below aborts the
--   migration with a clear message if duplicates exist (verify beforehand:
--   SELECT id, count(*) FROM public.products GROUP BY id HAVING count(*) > 1;).
--
-- ROLLBACK: restore from the pre-migration backup. (Reversing a PK change +
--   rename in place is error-prone and intentionally not scripted.)
--
-- EXPECTED SCHEMA CHANGES:
--   ~ products PK (id, name) -> (id)
--   ~ products."Description" renamed to description
--   - drop unused enum type public.order_status (D-ENUM-1)
--
-- IDEMPOTENCY: guarded by catalog checks; safe to re-run (no-op once applied).
-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Guard: abort if products.id is not unique (composite PK could have masked dups).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_dups bigint;
BEGIN
  SELECT count(*) INTO v_dups
  FROM (SELECT id FROM public.products GROUP BY id HAVING count(*) > 1) d;
  IF v_dups > 0 THEN
    RAISE EXCEPTION
      'Cannot set products PK to (id): % duplicate id value(s) found. Resolve duplicates first.',
      v_dups;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Swap the primary key to (id). No FK currently references products_pkey.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.products'::regclass
      AND contype  = 'p'
      AND array_length(conkey, 1) > 1      -- current PK is composite
  ) THEN
    ALTER TABLE public.products DROP CONSTRAINT products_pkey;
    ALTER TABLE public.products ADD  CONSTRAINT products_pkey PRIMARY KEY (id);
  ELSIF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.products'::regclass AND contype = 'p'
  ) THEN
    ALTER TABLE public.products ADD CONSTRAINT products_pkey PRIMARY KEY (id);
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Rename "Description" -> description (data-preserving RENAME, guarded).
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'Description'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'description'
  ) THEN
    ALTER TABLE public.products RENAME COLUMN "Description" TO description;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- D-ENUM-1: drop the unused public.order_status enum. The baseline created it
-- but orders.status is text (+ CHECK in 007); no column references the type.
-- Guarded so it only drops when genuinely unreferenced.
-- Rollback: CREATE TYPE public.order_status AS ENUM ('pending','paid','fulfilled','cancelled');
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'order_status' AND n.nspname = 'public'
  ) AND NOT EXISTS (
    SELECT 1
    FROM pg_attribute a
    JOIN pg_type t     ON a.atttypid = t.oid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE t.typname = 'order_status' AND n.nspname = 'public'
      AND a.attnum > 0 AND NOT a.attisdropped
  ) THEN
    DROP TYPE public.order_status;
  END IF;
END $$;

COMMIT;
