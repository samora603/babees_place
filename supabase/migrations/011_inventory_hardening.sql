-- =============================================================================
-- 011_inventory_hardening.sql — Inventory constraints + checkout hardening
-- Babees Place — Phase 2 Workstream 1
-- =============================================================================
-- PURPOSE:
--   * Enforce non-negative stock at the database level
--   * Reject inactive products in place_order()
--   * Add cancel_order() to restore stock atomically on cancellation
--
-- DEPENDENCIES:
--   * 002_additive_columns.sql (stock, is_active)
--   * 003_functions_and_triggers.sql (place_order baseline)
--   * 007_data_normalization.sql (orders.status CHECK vocabulary)
--
-- RISK: Low. Additive constraint + function replacements. cancel_order is new.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Non-negative stock (products.stock >= 0)
-- ---------------------------------------------------------------------------
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_stock_nonneg_check;
ALTER TABLE public.products ADD CONSTRAINT products_stock_nonneg_check
  CHECK (stock >= 0) NOT VALID;
ALTER TABLE public.products VALIDATE CONSTRAINT products_stock_nonneg_check;

-- ---------------------------------------------------------------------------
-- place_order(): reject inactive products before stock deduction
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.place_order(p_user_id uuid DEFAULT auth.uid())
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order_id uuid;
  v_total    numeric(12,2) := 0;
  r          RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() IS DISTINCT FROM p_user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  PERFORM 1
  FROM public.products p
  JOIN public.cart_items c ON c.product_id = p.id
  WHERE c.user_id = p_user_id
  FOR UPDATE OF p;

  FOR r IN
    SELECT c.product_id, c.quantity, p.stock, p.name, p.is_active
    FROM public.cart_items c
    JOIN public.products p ON p.id = c.product_id
    WHERE c.user_id = p_user_id
  LOOP
    IF NOT COALESCE(r.is_active, true) THEN
      RAISE EXCEPTION 'Product % is no longer available', r.name;
    END IF;
    IF r.stock < r.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for %', r.name;
    END IF;
  END LOOP;

  SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)
  INTO v_total
  FROM public.cart_items c
  JOIN public.products p ON p.id = c.product_id
  WHERE c.user_id = p_user_id;

  IF v_total = 0 THEN
    RAISE EXCEPTION 'Cart is empty';
  END IF;

  INSERT INTO public.orders (user_id, status, total, payment_status)
  VALUES (p_user_id, 'pending', v_total, 'pending')
  RETURNING id INTO v_order_id;

  INSERT INTO public.order_items (order_id, product_id, name, price, quantity, image_url)
  SELECT
    v_order_id,
    c.product_id,
    p.name,
    COALESCE(p.discount_price, p.price),
    c.quantity,
    COALESCE(
      p.image_url,
      CASE WHEN jsonb_typeof(p.images) = 'array'
           THEN p.images->0->>'url'
           ELSE NULL END
    )
  FROM public.cart_items c
  JOIN public.products p ON p.id = c.product_id
  WHERE c.user_id = p_user_id;

  UPDATE public.products p
  SET stock = p.stock - c.quantity
  FROM public.cart_items c
  WHERE c.user_id = p_user_id AND c.product_id = p.id;

  DELETE FROM public.cart_items WHERE user_id = p_user_id;

  RETURN v_order_id;
END;
$$;

REVOKE ALL ON FUNCTION public.place_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_order(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- cancel_order(): atomic cancel + stock restore (idempotent)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'Order id is required';
  END IF;
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF auth.uid() IS DISTINCT FROM v_order.user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Idempotent: already cancelled — no double restore
  IF v_order.status = 'cancelled' THEN
    RETURN;
  END IF;

  IF v_order.status = 'delivered' THEN
    RAISE EXCEPTION 'Delivered orders cannot be cancelled';
  END IF;

  PERFORM 1
  FROM public.products p
  JOIN public.order_items oi ON oi.product_id = p.id
  WHERE oi.order_id = p_order_id
    AND oi.product_id IS NOT NULL
  FOR UPDATE OF p;

  UPDATE public.products p
  SET stock = p.stock + oi.quantity
  FROM public.order_items oi
  WHERE oi.order_id = p_order_id
    AND oi.product_id = p.id
    AND oi.product_id IS NOT NULL;

  UPDATE public.orders
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_order_id;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_order(uuid) TO authenticated;

COMMIT;
