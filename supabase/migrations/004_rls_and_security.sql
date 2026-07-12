-- =============================================================================
-- 004_rls_and_security.sql — RLS policies + role-escalation fix  (Strategy: M2 + M3)
-- Babees Place — Phase 1.7B Workstream 1 forward migration
-- =============================================================================
-- PURPOSE:
--   (M3, CRITICAL) Close C-1: users can currently UPDATE their own profile row
--   and self-escalate role because the live "Users can update their own profile"
--   policy has USING only and NO WITH CHECK. Replace it with a WITH CHECK that
--   forbids changing role, and add a separate admin-only role-change policy.
--   (M2) Make the deny-all live tables (cart_items, wishlists, categories) usable
--   and secure, add admin write on products, and remove the direct INSERT on
--   orders so all order creation flows only through place_order() (D-RLS-4).
--
-- DEPENDENCIES:
--   * 003_functions_and_triggers.sql — policies reference public.is_admin().
--
-- RISK: Low–Medium. Behavioral: blocks profile role self-edit and direct order
--   inserts. Verify normal flows (cart/wishlist read+write, order read) on staging.
--
-- ROLLBACK:
--   Drop the policies created here and, if needed, recreate the prior live
--   policies (profiles USING-only update, orders owner-insert). See per-block notes.
--
-- EXPECTED SCHEMA CHANGES (no data change):
--   profiles   : replace update-own (adds WITH CHECK role-unchanged); add admin update;
--                broaden select to own-or-admin.
--   cart_items : add owner ALL policy.
--   wishlists  : add owner ALL policy.
--   categories : add public SELECT + admin write.
--   products   : keep public SELECT; add admin write.
--   orders     : remove direct owner INSERT (creation via place_order only).
--   order_items: keep INSERT blocked; broaden SELECT to owner-OR-admin (§7).
--
-- IDEMPOTENCY: DROP POLICY IF EXISTS before each CREATE; ENABLE RLS is a no-op if on.
-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.
-- =============================================================================

BEGIN;

-- Ensure RLS is enabled (baseline already enables these; no-op if already on).
ALTER TABLE public.profiles    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wishlists   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- PROFILES (M3 CRITICAL)
-- Replace the live-named policies with canonical, hardened equivalents.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can view their own profile" ON public.profiles;
DROP POLICY IF EXISTS profiles_select_own_or_admin       ON public.profiles;
CREATE POLICY profiles_select_own_or_admin ON public.profiles
  FOR SELECT USING (auth.uid() = id OR public.is_admin());

-- Owner may update their row but MUST NOT change role (compare to stored role).
DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
DROP POLICY IF EXISTS profiles_update_own                  ON public.profiles;
CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND role = (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
  );

-- Admins may change any profile (incl. role).
DROP POLICY IF EXISTS profiles_update_admin ON public.profiles;
CREATE POLICY profiles_update_admin ON public.profiles
  FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Keep the existing insert-own policy semantics (recreate canonically).
DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
DROP POLICY IF EXISTS profiles_insert_own                  ON public.profiles;
CREATE POLICY profiles_insert_own ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

-- ---------------------------------------------------------------------------
-- CART_ITEMS (M2) — owner-scoped full access.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS cart_items_all_own ON public.cart_items;
CREATE POLICY cart_items_all_own ON public.cart_items
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- WISHLISTS (M2) — owner-scoped full access.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS wishlists_all_own ON public.wishlists;
CREATE POLICY wishlists_all_own ON public.wishlists
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- CATEGORIES (M2) — public read, admin write.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS categories_select_public ON public.categories;
CREATE POLICY categories_select_public ON public.categories
  FOR SELECT USING (true);

DROP POLICY IF EXISTS categories_modify_admin ON public.categories;
CREATE POLICY categories_modify_admin ON public.categories
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- PRODUCTS (M2/D-RLS-3) — keep public read (live "Allow public read access"),
-- add admin write. Public SELECT + admin ALL are OR-combined, so anonymous
-- read still works while writes require admin.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS products_write_admin ON public.products;
CREATE POLICY products_write_admin ON public.products
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- ORDERS (D-RLS-4) — remove direct client INSERT; creation only via place_order().
-- SELECT (own / admin) and admin UPDATE policies from the baseline are retained.
-- Rollback: recreate  CREATE POLICY "Users can insert own orders" ON public.orders
--           FOR INSERT WITH CHECK (auth.uid() = user_id);
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can insert own orders" ON public.orders;

-- ---------------------------------------------------------------------------
-- ORDER_ITEMS — keep the baseline INSERT block (WITH CHECK false); writes happen
-- only via place_order() (SECURITY DEFINER). Broaden SELECT from owner-only to
-- owner-OR-admin so admin order views can read line items (Final_Canonical_Schema
-- §7). This is additive for admins and does not widen access for regular users.
-- Rollback: restore the owner-only policy
--   CREATE POLICY "Users can view own order items" ON public.order_items
--     FOR SELECT USING (EXISTS (SELECT 1 FROM public.orders o
--       WHERE o.id = order_items.order_id AND o.user_id = auth.uid()));
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can view own order items"      ON public.order_items;
DROP POLICY IF EXISTS order_items_select_owner_or_admin     ON public.order_items;
CREATE POLICY order_items_select_owner_or_admin ON public.order_items
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id
        AND (o.user_id = auth.uid() OR public.is_admin())
    )
  );

COMMIT;
