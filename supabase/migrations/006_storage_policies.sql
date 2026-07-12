-- =============================================================================
-- 006_storage_policies.sql — Product image storage security  (Strategy: M8)
-- Babees Place — Phase 1.7B Workstream 1 forward migration
-- =============================================================================
-- PURPOSE:
--   Secure the product image bucket. Live has no user-defined storage policies.
--   Ensure the `products` bucket exists (public) and add storage.objects policies:
--   public read, admin-only write/update/delete (via is_admin()).
--
-- DEPENDENCIES:
--   * 003_functions_and_triggers.sql — policies reference public.is_admin().
--   * MANUAL: confirm in the dashboard whether a `products` bucket already exists
--     and its intended visibility (Reconciliation Decision Log — unresolved Q2).
--     The INSERT below is idempotent and will not clobber an existing bucket.
--
-- RISK: Medium. Misconfigured policies can break admin uploads or public image
--   reads; verify upload + public URL fetch on staging.
--
-- ROLLBACK:
--   DROP POLICY IF EXISTS "products_public_read"   ON storage.objects;
--   DROP POLICY IF EXISTS "products_admin_insert"  ON storage.objects;
--   DROP POLICY IF EXISTS "products_admin_update"  ON storage.objects;
--   DROP POLICY IF EXISTS "products_admin_delete"  ON storage.objects;
--   (Leave the bucket in place; removing a bucket with objects is destructive.)
--
-- EXPECTED SCHEMA CHANGES:
--   + storage.buckets row 'products' (if missing)
--   + 4 policies on storage.objects scoped to bucket_id = 'products'
--
-- IDEMPOTENCY: ON CONFLICT DO NOTHING for the bucket; DROP POLICY IF EXISTS before CREATE.
-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.
-- =============================================================================

BEGIN;

-- Ensure the bucket exists (public read bucket for product imagery).
INSERT INTO storage.buckets (id, name, public)
VALUES ('products', 'products', true)
ON CONFLICT (id) DO NOTHING;

-- Public read of product images.
DROP POLICY IF EXISTS "products_public_read" ON storage.objects;
CREATE POLICY "products_public_read" ON storage.objects
  FOR SELECT USING (bucket_id = 'products');

-- Admin-only writes.
DROP POLICY IF EXISTS "products_admin_insert" ON storage.objects;
CREATE POLICY "products_admin_insert" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'products' AND public.is_admin());

DROP POLICY IF EXISTS "products_admin_update" ON storage.objects;
CREATE POLICY "products_admin_update" ON storage.objects
  FOR UPDATE USING (bucket_id = 'products' AND public.is_admin())
             WITH CHECK (bucket_id = 'products' AND public.is_admin());

DROP POLICY IF EXISTS "products_admin_delete" ON storage.objects;
CREATE POLICY "products_admin_delete" ON storage.objects
  FOR DELETE USING (bucket_id = 'products' AND public.is_admin());

COMMIT;
