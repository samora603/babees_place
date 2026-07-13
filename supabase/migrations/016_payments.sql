-- 016_payments.sql
-- Workstream 6 — Payments foundation
--
-- Adds payments + payment_events, order payment_method / mpesa_receipt_number,
-- extends place_order with optional payment method (default cod), and
-- SECURITY DEFINER helpers for initiating / finalizing payments.
-- Idempotent where practical. Preserves COD as default.

-- ---------------------------------------------------------------------------
-- 1. Orders: payment method + M-Pesa receipt mirror
-- ---------------------------------------------------------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payment_method text NOT NULL DEFAULT 'cod';

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS mpesa_receipt_number text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'orders_payment_method_check'
  ) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_payment_method_check
      CHECK (payment_method IN ('cod', 'mpesa', 'card', 'paypal', 'bank_transfer'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_orders_payment_method ON public.orders (payment_method);
CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON public.orders (payment_status);

COMMENT ON COLUMN public.orders.payment_method IS
  'WS6 — checkout payment channel (cod default).';
COMMENT ON COLUMN public.orders.mpesa_receipt_number IS
  'WS6 — mirrored from payments.receipt_number when M-Pesa succeeds.';

-- ---------------------------------------------------------------------------
-- 2. payments
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider text NOT NULL DEFAULT 'mpesa',
  method text NOT NULL DEFAULT 'mpesa',
  status text NOT NULL DEFAULT 'pending',
  amount numeric(12,2) NOT NULL,
  currency text NOT NULL DEFAULT 'KES',
  phone_number text,
  transaction_reference text,
  checkout_request_id text,
  merchant_request_id text,
  receipt_number text,
  failure_reason text,
  raw_request jsonb NOT NULL DEFAULT '{}'::jsonb,
  raw_response jsonb NOT NULL DEFAULT '{}'::jsonb,
  raw_callback jsonb NOT NULL DEFAULT '{}'::jsonb,
  expires_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT payments_provider_check
    CHECK (provider IN ('mpesa', 'mock_mpesa', 'card', 'paypal', 'bank', 'cod')),
  CONSTRAINT payments_method_check
    CHECK (method IN ('cod', 'mpesa', 'card', 'paypal', 'bank_transfer')),
  CONSTRAINT payments_status_check
    CHECK (status IN (
      'pending', 'initiated', 'processing', 'paid',
      'failed', 'cancelled', 'expired', 'refunded'
    )),
  CONSTRAINT payments_amount_positive CHECK (amount > 0)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_checkout_request_id_unique
  ON public.payments (checkout_request_id)
  WHERE checkout_request_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_merchant_request_id_unique
  ON public.payments (merchant_request_id)
  WHERE merchant_request_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_receipt_number_unique
  ON public.payments (receipt_number)
  WHERE receipt_number IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_payments_order_id ON public.payments (order_id);
CREATE INDEX IF NOT EXISTS idx_payments_user_id ON public.payments (user_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments (status);
CREATE INDEX IF NOT EXISTS idx_payments_created_at ON public.payments (created_at DESC);

DROP TRIGGER IF EXISTS payments_set_updated_at ON public.payments;
CREATE TRIGGER payments_set_updated_at
  BEFORE UPDATE ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. payment_events (audit / callback log)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payment_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id uuid NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payment_events_payment_id_created
  ON public.payment_events (payment_id, created_at ASC);

-- ---------------------------------------------------------------------------
-- 4. RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS payments_select_own_or_admin ON public.payments;
CREATE POLICY payments_select_own_or_admin ON public.payments
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS payments_insert_own ON public.payments;
CREATE POLICY payments_insert_own ON public.payments
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS payments_update_own_or_admin ON public.payments;
CREATE POLICY payments_update_own_or_admin ON public.payments
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS payment_events_select_own_or_admin ON public.payment_events;
CREATE POLICY payment_events_select_own_or_admin ON public.payment_events
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.payments p
      WHERE p.id = payment_id
        AND (p.user_id = auth.uid() OR public.is_admin())
    )
  );

DROP POLICY IF EXISTS payment_events_insert_own_or_admin ON public.payment_events;
CREATE POLICY payment_events_insert_own_or_admin ON public.payment_events
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.payments p
      WHERE p.id = payment_id
        AND (p.user_id = auth.uid() OR public.is_admin())
    )
  );

GRANT SELECT, INSERT, UPDATE ON public.payments TO authenticated;
GRANT SELECT, INSERT ON public.payment_events TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. Extend place_order with payment_method (default cod)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.place_order(uuid, text, uuid, jsonb, text);

CREATE OR REPLACE FUNCTION public.place_order(
  p_user_id uuid DEFAULT auth.uid(),
  p_delivery_type text DEFAULT NULL,
  p_pickup_location_id uuid DEFAULT NULL,
  p_delivery_address jsonb DEFAULT NULL,
  p_customer_note text DEFAULT NULL,
  p_payment_method text DEFAULT 'cod'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id uuid;
  v_subtotal numeric(12,2) := 0;
  v_delivery_fee numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
  v_payment_method text := COALESCE(NULLIF(trim(p_payment_method), ''), 'cod');
  r RECORD;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() IS DISTINCT FROM p_user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_payment_method NOT IN ('cod', 'mpesa', 'card', 'paypal', 'bank_transfer') THEN
    RAISE EXCEPTION 'Invalid payment method: %', v_payment_method;
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
    user_id, status, total, payment_status, payment_method,
    delivery_type, pickup_location_id, delivery_address,
    delivery_fee, customer_note
  )
  VALUES (
    p_user_id, 'pending', v_total, 'pending', v_payment_method,
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
    'total', v_total,
    'payment_method', v_payment_method
  ));

  RETURN v_order_id;
END;
$$;

REVOKE ALL ON FUNCTION public.place_order(uuid, text, uuid, jsonb, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_order(uuid, text, uuid, jsonb, text, text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 6. create_payment_for_order — owner initiates a payment attempt
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_payment_for_order(
  p_order_id uuid,
  p_method text DEFAULT 'mpesa',
  p_provider text DEFAULT 'mock_mpesa',
  p_phone_number text DEFAULT NULL,
  p_amount numeric DEFAULT NULL
)
RETURNS public.payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders%ROWTYPE;
  v_payment public.payments%ROWTYPE;
  v_amount numeric(12,2);
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_order.user_id IS DISTINCT FROM auth.uid() AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF v_order.status = 'cancelled' THEN
    RAISE EXCEPTION 'Cannot pay a cancelled order';
  END IF;
  IF v_order.payment_status = 'paid' THEN
    RAISE EXCEPTION 'Order is already paid';
  END IF;

  v_amount := COALESCE(p_amount, v_order.total);
  IF v_amount IS NULL OR v_amount <= 0 THEN
    RAISE EXCEPTION 'Invalid payment amount';
  END IF;

  INSERT INTO public.payments (
    order_id, user_id, provider, method, status, amount, currency, phone_number, expires_at
  )
  VALUES (
    p_order_id,
    v_order.user_id,
    COALESCE(NULLIF(trim(p_provider), ''), 'mock_mpesa'),
    COALESCE(NULLIF(trim(p_method), ''), 'mpesa'),
    'pending',
    v_amount,
    'KES',
    NULLIF(trim(p_phone_number), ''),
    now() + interval '5 minutes'
  )
  RETURNING * INTO v_payment;

  INSERT INTO public.payment_events (payment_id, event_type, payload)
  VALUES (
    v_payment.id,
    'payment_created',
    jsonb_build_object('method', v_payment.method, 'provider', v_payment.provider, 'amount', v_amount)
  );

  UPDATE public.orders
  SET payment_method = v_payment.method,
      payment_status = 'pending',
      updated_at = now()
  WHERE id = p_order_id;

  RETURN v_payment;
END;
$$;

REVOKE ALL ON FUNCTION public.create_payment_for_order(uuid, text, text, text, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_payment_for_order(uuid, text, text, text, numeric) TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. mark_payment_initiated — store STK ids after provider call
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_payment_initiated(
  p_payment_id uuid,
  p_checkout_request_id text,
  p_merchant_request_id text DEFAULT NULL,
  p_raw_response jsonb DEFAULT '{}'::jsonb
)
RETURNS public.payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payment public.payments%ROWTYPE;
BEGIN
  SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found';
  END IF;
  IF v_payment.user_id IS DISTINCT FROM auth.uid() AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  UPDATE public.payments
  SET status = 'initiated',
      checkout_request_id = NULLIF(trim(p_checkout_request_id), ''),
      merchant_request_id = NULLIF(trim(p_merchant_request_id), ''),
      raw_response = COALESCE(p_raw_response, '{}'::jsonb),
      updated_at = now()
  WHERE id = p_payment_id
  RETURNING * INTO v_payment;

  INSERT INTO public.payment_events (payment_id, event_type, payload)
  VALUES (
    p_payment_id,
    'stk_initiated',
    jsonb_build_object(
      'checkout_request_id', p_checkout_request_id,
      'merchant_request_id', p_merchant_request_id
    )
  );

  RETURN v_payment;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_payment_initiated(uuid, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_payment_initiated(uuid, text, text, jsonb) TO authenticated;

-- ---------------------------------------------------------------------------
-- 8. finalize_payment — idempotent callback / poll result applicator
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.finalize_payment(
  p_payment_id uuid,
  p_status text,
  p_receipt_number text DEFAULT NULL,
  p_transaction_reference text DEFAULT NULL,
  p_failure_reason text DEFAULT NULL,
  p_raw_callback jsonb DEFAULT '{}'::jsonb
)
RETURNS public.payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payment public.payments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_status text := lower(trim(p_status));
BEGIN
  IF v_status NOT IN ('paid', 'failed', 'cancelled', 'expired', 'processing') THEN
    RAISE EXCEPTION 'Invalid finalize status: %', p_status;
  END IF;

  SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found';
  END IF;

  -- Idempotent success: already paid with same receipt
  IF v_payment.status = 'paid' AND v_status = 'paid' THEN
    INSERT INTO public.payment_events (payment_id, event_type, payload)
    VALUES (
      p_payment_id,
      'duplicate_callback_ignored',
      COALESCE(p_raw_callback, '{}'::jsonb)
    );
    RETURN v_payment;
  END IF;

  -- Do not regress a paid payment
  IF v_payment.status = 'paid' AND v_status <> 'paid' THEN
    INSERT INTO public.payment_events (payment_id, event_type, payload)
    VALUES (
      p_payment_id,
      'stale_callback_ignored',
      jsonb_build_object('attempted_status', v_status)
    );
    RETURN v_payment;
  END IF;

  UPDATE public.payments
  SET status = v_status,
      receipt_number = COALESCE(NULLIF(trim(p_receipt_number), ''), receipt_number),
      transaction_reference = COALESCE(NULLIF(trim(p_transaction_reference), ''), transaction_reference),
      failure_reason = CASE
        WHEN v_status IN ('failed', 'cancelled', 'expired')
          THEN COALESCE(NULLIF(trim(p_failure_reason), ''), failure_reason)
        ELSE NULL
      END,
      raw_callback = COALESCE(p_raw_callback, '{}'::jsonb),
      paid_at = CASE WHEN v_status = 'paid' THEN now() ELSE paid_at END,
      updated_at = now()
  WHERE id = p_payment_id
  RETURNING * INTO v_payment;

  INSERT INTO public.payment_events (payment_id, event_type, payload)
  VALUES (
    p_payment_id,
    'payment_' || v_status,
    COALESCE(p_raw_callback, '{}'::jsonb)
  );

  SELECT * INTO v_order FROM public.orders WHERE id = v_payment.order_id FOR UPDATE;

  IF v_status = 'paid' THEN
    UPDATE public.orders
    SET payment_status = 'paid',
        mpesa_receipt_number = COALESCE(v_payment.receipt_number, mpesa_receipt_number),
        payment_method = COALESCE(v_payment.method, payment_method),
        updated_at = now()
    WHERE id = v_payment.order_id;

    PERFORM public.log_order_event(v_payment.order_id, 'payment_status_changed', jsonb_build_object(
      'from', v_order.payment_status,
      'to', 'paid',
      'payment_id', p_payment_id,
      'receipt_number', v_payment.receipt_number
    ));
  ELSIF v_status IN ('failed', 'cancelled', 'expired') THEN
    -- Keep order payment_status failed only if not already paid
    IF v_order.payment_status IS DISTINCT FROM 'paid' THEN
      UPDATE public.orders
      SET payment_status = 'failed',
          updated_at = now()
      WHERE id = v_payment.order_id;

      PERFORM public.log_order_event(v_payment.order_id, 'payment_status_changed', jsonb_build_object(
        'from', v_order.payment_status,
        'to', 'failed',
        'payment_id', p_payment_id,
        'reason', v_payment.failure_reason
      ));
    END IF;
  END IF;

  RETURN v_payment;
END;
$$;

REVOKE ALL ON FUNCTION public.finalize_payment(uuid, text, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_payment(uuid, text, text, text, text, jsonb) TO authenticated;
