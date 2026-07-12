-- =============================================================================
-- 013_order_fulfillment.sql — Order fulfillment, status machine, pickup locations
-- Babees Place — Phase 2 Workstream 3
-- =============================================================================
-- PURPOSE:
--   * pickup_locations table + RLS
--   * Order fulfillment columns (delivery_type, address, fee, etc.)
--   * Extended order status vocabulary + validated CHECK
--   * order_events table (notification architecture hook)
--   * place_order() extended with fulfillment params
--   * cancel_order() hardened (customer vs admin rules)
--   * update_order_status() RPC with transition matrix
--   * update_order_payment_status() RPC (admin COD/manual)
--
-- DEPENDENCIES: 001–012 applied
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Constants (flat delivery fee in KES)
-- ---------------------------------------------------------------------------
-- Delivery fee applied when delivery_type = 'delivery' (enforced in place_order).

-- ---------------------------------------------------------------------------
-- pickup_locations
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pickup_locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  building text NOT NULL DEFAULT '',
  description text,
  operating_hours jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.pickup_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS pickup_locations_select_active ON public.pickup_locations;
CREATE POLICY pickup_locations_select_active ON public.pickup_locations
  FOR SELECT USING (is_active = true OR public.is_admin());

DROP POLICY IF EXISTS pickup_locations_modify_admin ON public.pickup_locations;
CREATE POLICY pickup_locations_modify_admin ON public.pickup_locations
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_pickup_locations_is_active
  ON public.pickup_locations (is_active) WHERE is_active = true;

-- ---------------------------------------------------------------------------
-- orders: fulfillment columns
-- ---------------------------------------------------------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivery_type text,
  ADD COLUMN IF NOT EXISTS pickup_location_id uuid REFERENCES public.pickup_locations(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS delivery_address jsonb,
  ADD COLUMN IF NOT EXISTS delivery_fee numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS customer_note text;

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_delivery_type_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_delivery_type_check
  CHECK (delivery_type IS NULL OR delivery_type IN ('pickup', 'delivery'));

CREATE INDEX IF NOT EXISTS idx_orders_pickup_location_id
  ON public.orders (pickup_location_id) WHERE pickup_location_id IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Extended order status vocabulary
-- ---------------------------------------------------------------------------
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
  CHECK (status IN (
    'pending', 'confirmed', 'processing', 'ready_for_pickup',
    'shipped', 'delivered', 'cancelled'
  )) NOT VALID;
ALTER TABLE public.orders VALIDATE CONSTRAINT orders_status_check;

-- ---------------------------------------------------------------------------
-- order_events (notification architecture — no email/SMS in WS3)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.order_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_order_events_order_id
  ON public.order_events (order_id, created_at DESC);

ALTER TABLE public.order_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS order_events_select_owner_or_admin ON public.order_events;
CREATE POLICY order_events_select_owner_or_admin ON public.order_events
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_events.order_id
        AND (o.user_id = auth.uid() OR public.is_admin())
    )
  );

-- ---------------------------------------------------------------------------
-- log_order_event() — internal helper for RPCs
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_order_event(
  p_order_id uuid,
  p_event_type text,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.order_events (order_id, event_type, payload)
  VALUES (p_order_id, p_event_type, COALESCE(p_payload, '{}'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.log_order_event(uuid, text, jsonb) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- place_order(): fulfillment params + delivery fee in total
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.place_order(uuid);

CREATE OR REPLACE FUNCTION public.place_order(
  p_user_id uuid DEFAULT auth.uid(),
  p_delivery_type text DEFAULT NULL,
  p_pickup_location_id uuid DEFAULT NULL,
  p_delivery_address jsonb DEFAULT NULL,
  p_customer_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order_id uuid;
  v_subtotal numeric(12,2) := 0;
  v_delivery_fee numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
  r RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() IS DISTINCT FROM p_user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_delivery_type IS NULL OR p_delivery_type NOT IN ('pickup', 'delivery') THEN
    RAISE EXCEPTION 'Delivery type is required (pickup or delivery)';
  END IF;

  IF p_delivery_type = 'pickup' THEN
    IF p_pickup_location_id IS NULL THEN
      RAISE EXCEPTION 'Pickup location is required';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.pickup_locations
      WHERE id = p_pickup_location_id AND is_active = true
    ) THEN
      RAISE EXCEPTION 'Invalid or inactive pickup location';
    END IF;
  END IF;

  IF p_delivery_type = 'delivery' THEN
    IF p_delivery_address IS NULL
       OR NULLIF(trim(p_delivery_address->>'line1'), '') IS NULL
       OR NULLIF(trim(p_delivery_address->>'city'), '') IS NULL
       OR NULLIF(trim(p_delivery_address->>'phone'), '') IS NULL THEN
      RAISE EXCEPTION 'Delivery address (line1, city, phone) is required';
    END IF;
    v_delivery_fee := 200;
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
  INTO v_subtotal
  FROM public.cart_items c
  JOIN public.products p ON p.id = c.product_id
  WHERE c.user_id = p_user_id;

  IF v_subtotal = 0 THEN
    RAISE EXCEPTION 'Cart is empty';
  END IF;

  v_total := v_subtotal + v_delivery_fee;

  INSERT INTO public.orders (
    user_id, status, total, payment_status,
    delivery_type, pickup_location_id, delivery_address,
    delivery_fee, customer_note
  )
  VALUES (
    p_user_id, 'pending', v_total, 'pending',
    p_delivery_type, p_pickup_location_id, p_delivery_address,
    v_delivery_fee, NULLIF(trim(p_customer_note), '')
  )
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

  PERFORM public.log_order_event(v_order_id, 'order_placed', jsonb_build_object(
    'delivery_type', p_delivery_type,
    'delivery_fee', v_delivery_fee,
    'subtotal', v_subtotal,
    'total', v_total
  ));

  RETURN v_order_id;
END;
$$;

REVOKE ALL ON FUNCTION public.place_order(uuid, text, uuid, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_order(uuid, text, uuid, jsonb, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- cancel_order(): customer vs admin cancellation rules + payment refund flag
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_is_admin boolean;
BEGIN
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'Order id is required';
  END IF;
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_is_admin := public.is_admin();

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF auth.uid() IS DISTINCT FROM v_order.user_id AND NOT v_is_admin THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_order.status = 'cancelled' THEN
    RETURN;
  END IF;

  IF v_order.status = 'delivered' THEN
    RAISE EXCEPTION 'Delivered orders cannot be cancelled';
  END IF;

  IF NOT v_is_admin AND v_order.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'This order cannot be cancelled at its current status';
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
  SET
    status = 'cancelled',
    payment_status = CASE
      WHEN payment_status = 'paid' THEN 'refunded'
      ELSE payment_status
    END,
    updated_at = now()
  WHERE id = p_order_id;

  PERFORM public.log_order_event(p_order_id, 'order_cancelled', jsonb_build_object(
    'previous_status', v_order.status,
    'cancelled_by', CASE WHEN v_is_admin THEN 'admin' ELSE 'customer' END
  ));
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_order(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- update_order_status(): admin-only transition matrix
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_order_status(
  p_order_id uuid,
  p_status text,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_allowed boolean := false;
BEGIN
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'Order id is required';
  END IF;
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_status = 'cancelled' THEN
    RAISE EXCEPTION 'Use cancel_order() to cancel orders';
  END IF;

  IF p_status NOT IN (
    'pending', 'confirmed', 'processing', 'ready_for_pickup',
    'shipped', 'delivered', 'cancelled'
  ) THEN
    RAISE EXCEPTION 'Invalid status: %', p_status;
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_order.status = 'cancelled' OR v_order.status = 'delivered' THEN
    RAISE EXCEPTION 'Cannot update a % order', v_order.status;
  END IF;

  IF v_order.status = p_status THEN
    IF p_note IS NOT NULL THEN
      UPDATE public.orders SET note = NULLIF(trim(p_note), ''), updated_at = now()
      WHERE id = p_order_id;
    END IF;
    RETURN;
  END IF;

  -- Transition matrix (delivery_type aware)
  v_allowed := CASE
    WHEN v_order.status = 'pending' AND p_status = 'confirmed' THEN true
    WHEN v_order.status = 'confirmed' AND p_status = 'processing'
         AND v_order.delivery_type = 'delivery' THEN true
    WHEN v_order.status = 'confirmed' AND p_status = 'ready_for_pickup'
         AND v_order.delivery_type = 'pickup' THEN true
    WHEN v_order.status = 'processing' AND p_status = 'shipped' THEN true
    WHEN v_order.status = 'ready_for_pickup' AND p_status = 'delivered' THEN true
    WHEN v_order.status = 'shipped' AND p_status = 'delivered' THEN true
    ELSE false
  END;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Transition from % to % is not allowed', v_order.status, p_status;
  END IF;

  UPDATE public.orders
  SET
    status = p_status,
    note = COALESCE(NULLIF(trim(p_note), ''), note),
    updated_at = now()
  WHERE id = p_order_id;

  PERFORM public.log_order_event(p_order_id, 'status_changed', jsonb_build_object(
    'from', v_order.status,
    'to', p_status,
    'note', p_note
  ));
END;
$$;

REVOKE ALL ON FUNCTION public.update_order_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_order_status(uuid, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- update_order_payment_status(): admin manual COD / refund marking
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_order_payment_status(
  p_order_id uuid,
  p_payment_status text,
  p_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order public.orders%ROWTYPE;
BEGIN
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'Order id is required';
  END IF;
  IF auth.uid() IS NULL OR NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_payment_status NOT IN ('pending', 'paid', 'failed', 'refunded') THEN
    RAISE EXCEPTION 'Invalid payment status: %', p_payment_status;
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  UPDATE public.orders
  SET
    payment_status = p_payment_status,
    note = COALESCE(NULLIF(trim(p_note), ''), note),
    updated_at = now()
  WHERE id = p_order_id;

  PERFORM public.log_order_event(p_order_id, 'payment_status_changed', jsonb_build_object(
    'from', v_order.payment_status,
    'to', p_payment_status
  ));
END;
$$;

REVOKE ALL ON FUNCTION public.update_order_payment_status(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_order_payment_status(uuid, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- Seed default pickup location when none exist (enables checkout on fresh deploy)
-- ---------------------------------------------------------------------------
INSERT INTO public.pickup_locations (name, building, description, operating_hours)
SELECT
  'Babees Place Main',
  'Primary Boutique',
  'Default pickup hub',
  '{"weekdays":{"open":"08:00","close":"18:00"},"weekends":{"open":"09:00","close":"15:00"}}'::jsonb
WHERE NOT EXISTS (SELECT 1 FROM public.pickup_locations);

COMMIT;
