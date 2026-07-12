-- =============================================================================
-- Babis Place — Phase 1 Security Hardening
-- =============================================================================
-- 🛑 DO NOT APPLY AS-IS. Verified 2026-07-12 against the live project
-- (ref qfcygrxrfszcdltangec): the LIVE schema does NOT match migration 001.
-- This file targets the *idealized* schema in 001 (tables `cart`, `orders.total_amount`,
-- `place_order()` RPC, policies named `orders_insert_own`, etc.). The live DB
-- instead has `cart_items`, `orders.total`, NO `place_order()` function, and
-- differently-named RLS policies. Running this against live will error or no-op.
-- The migration strategy must be reconciled first — see
-- docs/audits/Phase1_Final_Closure_Report.md (Migration Status). For the immediate,
-- live-compatible role-escalation fix, use the SQL in that report's "Manual Steps".
--
-- STATUS: MANUAL-APPLY ONLY. This migration was authored during Phase 1 but has
-- NOT been applied to any live database by the tooling. Before applying:
--   1. Take a backup / snapshot of the Supabase project (Dashboard > Database >
--      Backups, or `supabase db dump`).
--   2. Generate the baseline migration first (`supabase db pull`) so the local
--      history matches production (the `products` table and others are not yet
--      in version control — see docs/audits/Supabase_Health_Report.md).
--   3. Review, then apply via the Supabase SQL Editor or `supabase db push`.
--
-- Addresses:
--   * F-01 (CRITICAL) — profiles role self-escalation (missing WITH CHECK).
--   * F-02 (HIGH)     — client can insert orders/order_items with forged totals.
--   * F-13 (HIGH)     — place_order stock check/decrement race (no row locking).
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- F-01: Prevent role self-escalation on profiles.
-- The original policy had only USING (auth.uid() = id) and no WITH CHECK, so a
-- user could UPDATE their own row and set role = 'admin'. We add a WITH CHECK
-- that (a) keeps ownership and (b) forbids changing the role column: the new
-- role must equal the caller's current stored role.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS profiles_update_own ON public.profiles;
CREATE POLICY profiles_update_own ON public.profiles
  FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND role = (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())
  );

-- Admins still need to be able to change roles. Keep this explicit and separate
-- so privilege changes are only ever performed by an existing admin.
DROP POLICY IF EXISTS profiles_update_admin ON public.profiles;
CREATE POLICY profiles_update_admin ON public.profiles
  FOR UPDATE
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- -----------------------------------------------------------------------------
-- F-02: Force all order creation through the atomic place_order() RPC.
-- Removing the direct INSERT policies means authenticated clients can no longer
-- insert rows into orders / order_items directly with attacker-controlled
-- totals. place_order() is SECURITY DEFINER and bypasses RLS, so legitimate
-- checkout continues to work while forged-total inserts are rejected.
-- SELECT policies are intentionally left in place.
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS orders_insert_own ON public.orders;
DROP POLICY IF EXISTS order_items_insert_own ON public.order_items;

-- -----------------------------------------------------------------------------
-- F-13: Lock product rows during checkout to remove the stock TOCTOU race.
-- Two concurrent checkouts could both pass the stock check and oversell. We add
-- SELECT ... FOR UPDATE to lock the relevant product rows for the duration of
-- the transaction before validating and decrementing stock.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.place_order(p_user_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order_id UUID;
  v_total NUMERIC(12,2) := 0;
  r RECORD;
BEGIN
  IF auth.uid() IS DISTINCT FROM p_user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Lock the product rows referenced by this user's cart for the transaction.
  PERFORM 1
  FROM public.products p
  JOIN public.cart c ON c.product_id = p.id
  WHERE c.user_id = p_user_id
  FOR UPDATE OF p;

  FOR r IN
    SELECT c.product_id, c.quantity, p.stock, p.name
    FROM public.cart c
    JOIN public.products p ON p.id = c.product_id
    WHERE c.user_id = p_user_id
  LOOP
    IF r.stock < r.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for %', r.name;
    END IF;
  END LOOP;

  SELECT COALESCE(SUM(
    COALESCE(p."discountPrice", p.price) * c.quantity
  ), 0)
  INTO v_total
  FROM public.cart c
  JOIN public.products p ON p.id = c.product_id
  WHERE c.user_id = p_user_id;

  IF v_total = 0 THEN
    RAISE EXCEPTION 'Cart is empty';
  END IF;

  INSERT INTO public.orders (user_id, status, total_amount, payment_status)
  VALUES (p_user_id, 'pending', v_total, 'pending')
  RETURNING id INTO v_order_id;

  INSERT INTO public.order_items (order_id, product_id, name, price, quantity, image_url)
  SELECT
    v_order_id,
    c.product_id,
    p.name,
    COALESCE(p."discountPrice", p.price),
    c.quantity,
    COALESCE(
      p.image_url,
      CASE
        WHEN p.images IS NOT NULL AND jsonb_typeof(p.images::jsonb) = 'array'
        THEN p.images::jsonb->0->>'url'
        ELSE NULL
      END
    )
  FROM public.cart c
  JOIN public.products p ON p.id = c.product_id
  WHERE c.user_id = p_user_id;

  UPDATE public.products p
  SET stock = p.stock - c.quantity
  FROM public.cart c
  WHERE c.user_id = p_user_id AND c.product_id = p.id;

  DELETE FROM public.cart WHERE user_id = p_user_id;

  RETURN v_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.place_order(UUID) TO authenticated;

COMMIT;
