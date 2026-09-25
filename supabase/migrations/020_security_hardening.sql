-- 020_security_hardening.sql
-- Production security / integrity hardening (v1.0 acceptance audit).
--
-- 1. place_order() — server-authoritative discounts (ignore client p_discount_amount / p_free_delivery)
-- 2. finalize_payment() — caller must own payment or be admin
-- 3. payments RLS — revoke direct customer UPDATE
-- 4. orders — block direct PostgREST updates to sensitive columns (RPC bypass via definer role)
-- 5. award_loyalty_for_order() — caller must own order or be admin

-- ---------------------------------------------------------------------------
-- 1. Server-side promotion computation for checkout
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.compute_checkout_promotions(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_subtotal numeric(12,2) := 0;
  v_merch_discount numeric(12,2) := 0;
  v_free_delivery boolean := false;
  v_used_non_stackable boolean := false;
  v_promo public.promotions%ROWTYPE;
  v_line_discount numeric(12,2) := 0;
  v_eligible_subtotal numeric(12,2) := 0;
  v_applied jsonb := '[]'::jsonb;
  v_qty integer := 0;
  v_unit numeric(12,2) := 0;
  v_sets integer := 0;
  v_applicable boolean := false;
BEGIN
  SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)
  INTO v_subtotal
  FROM public.cart_items c
  JOIN public.products p ON p.id = c.product_id
  WHERE c.user_id = p_user_id;

  FOR v_promo IN
    SELECT *
    FROM public.promotions
    WHERE status = 'active'
      AND (starts_at IS NULL OR starts_at <= now())
      AND (ends_at IS NULL OR ends_at >= now())
    ORDER BY priority DESC, created_at ASC
  LOOP
    IF NOT v_promo.stackable AND v_used_non_stackable THEN
      CONTINUE;
    END IF;

    IF v_subtotal < COALESCE(v_promo.min_order_amount, 0) THEN
      CONTINUE;
    END IF;

    IF v_promo.usage_limit IS NOT NULL AND v_promo.usage_count >= v_promo.usage_limit THEN
      CONTINUE;
    END IF;

    v_line_discount := 0;
    v_eligible_subtotal := v_subtotal;
    v_applicable := false;

    IF v_promo.promo_type = 'category' AND v_promo.category_id IS NOT NULL THEN
      SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)
      INTO v_eligible_subtotal
      FROM public.cart_items c
      JOIN public.products p ON p.id = c.product_id
      WHERE c.user_id = p_user_id
        AND p.category_id = v_promo.category_id;
    ELSIF v_promo.promo_type = 'product' AND v_promo.product_id IS NOT NULL THEN
      SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)
      INTO v_eligible_subtotal
      FROM public.cart_items c
      JOIN public.products p ON p.id = c.product_id
      WHERE c.user_id = p_user_id
        AND p.id = v_promo.product_id;
    END IF;

    IF v_promo.promo_type = 'free_delivery' THEN
      v_free_delivery := true;
      v_applicable := true;
    ELSIF v_promo.promo_type IN ('percentage', 'storewide', 'category', 'product') THEN
      v_line_discount := round(v_eligible_subtotal * COALESCE(v_promo.percent_off, 0) / 100.0, 2);
      v_applicable := v_line_discount > 0;
    ELSIF v_promo.promo_type = 'fixed' THEN
      v_line_discount := COALESCE(v_promo.amount_off, 0);
      v_applicable := v_line_discount > 0;
    ELSIF v_promo.promo_type = 'buy_x_get_y'
      AND COALESCE(v_promo.buy_quantity, 0) > 0
      AND COALESCE(v_promo.get_quantity, 0) > 0 THEN
      SELECT COALESCE(SUM(c.quantity), 0)
      INTO v_qty
      FROM public.cart_items c
      WHERE c.user_id = p_user_id
        AND (v_promo.product_id IS NULL OR c.product_id = v_promo.product_id);

      v_sets := v_qty / (v_promo.buy_quantity + v_promo.get_quantity);
      IF v_sets > 0 THEN
        SELECT MIN(COALESCE(p.discount_price, p.price))
        INTO v_unit
        FROM public.cart_items c
        JOIN public.products p ON p.id = c.product_id
        WHERE c.user_id = p_user_id
          AND (v_promo.product_id IS NULL OR c.product_id = v_promo.product_id);

        v_line_discount := round(v_sets * v_promo.get_quantity * COALESCE(v_unit, 0), 2);
        v_applicable := v_line_discount > 0;
      END IF;
    END IF;

    IF v_promo.max_discount_amount IS NOT NULL THEN
      v_line_discount := LEAST(v_line_discount, v_promo.max_discount_amount);
    END IF;
    v_line_discount := LEAST(v_line_discount, v_subtotal);

    IF v_applicable THEN
      IF NOT v_promo.stackable THEN
        v_used_non_stackable := true;
      END IF;

      v_merch_discount := v_merch_discount + v_line_discount;
      IF v_promo.promo_type = 'free_delivery' THEN
        v_free_delivery := true;
      END IF;

      v_applied := v_applied || jsonb_build_array(jsonb_build_object(
        'id', v_promo.id,
        'code', v_promo.code,
        'name', v_promo.name,
        'promoType', v_promo.promo_type,
        'discount', v_line_discount,
        'freeDelivery', v_promo.promo_type = 'free_delivery'
      ));
    END IF;
  END LOOP;

  v_merch_discount := LEAST(v_merch_discount, v_subtotal);

  RETURN jsonb_build_object(
    'merchandiseDiscount', v_merch_discount,
    'freeDelivery', v_free_delivery,
    'applied', v_applied,
    'subtotal', v_subtotal
  );
END;
$$;

REVOKE ALL ON FUNCTION public.compute_checkout_promotions(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.compute_checkout_promotions(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. Hardened place_order — server computes discounts; client params ignored
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.place_order(
  p_user_id uuid DEFAULT auth.uid(),
  p_delivery_type text DEFAULT NULL,
  p_pickup_location_id uuid DEFAULT NULL,
  p_delivery_address jsonb DEFAULT NULL,
  p_customer_note text DEFAULT NULL,
  p_payment_method text DEFAULT 'cod',
  p_coupon_code text DEFAULT NULL,
  p_loyalty_points integer DEFAULT 0,
  p_gift_card_code text DEFAULT NULL,
  p_gift_card_amount numeric DEFAULT 0,
  p_discount_amount numeric DEFAULT 0,
  p_free_delivery boolean DEFAULT false,
  p_promotions_applied jsonb DEFAULT '[]'::jsonb,
  p_referral_code text DEFAULT NULL
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
  v_discount numeric(12,2) := 0;
  v_coupon_discount numeric(12,2) := 0;
  v_gift numeric(12,2) := GREATEST(COALESCE(p_gift_card_amount, 0), 0);
  v_points integer := GREATEST(COALESCE(p_loyalty_points, 0), 0);
  v_free_delivery boolean := false;
  v_payment_method text := COALESCE(NULLIF(trim(p_payment_method), ''), 'cod');
  v_coupon public.coupons;
  v_coupon_code text := NULLIF(upper(trim(p_coupon_code)), '');
  v_gift_card public.gift_cards;
  v_loyalty public.loyalty_accounts;
  v_rule public.loyalty_rules;
  v_points_value numeric(12,2) := 0;
  v_remaining numeric(12,2) := 0;
  v_max_loyalty numeric(12,2) := 0;
  v_user_redemptions integer := 0;
  v_promo_result jsonb;
  v_applied jsonb := '[]'::jsonb;
  r RECORD;
BEGIN
  -- p_discount_amount, p_free_delivery, and p_promotions_applied are accepted for
  -- backwards-compatible signatures but are NOT trusted for pricing decisions.

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

  -- Automatic promotions (authoritative)
  v_promo_result := public.compute_checkout_promotions(p_user_id);
  v_discount := COALESCE((v_promo_result->>'merchandiseDiscount')::numeric, 0);
  v_free_delivery := COALESCE((v_promo_result->>'freeDelivery')::boolean, false);
  v_applied := COALESCE(v_promo_result->'applied', '[]'::jsonb);

  -- Coupon validation + server-computed discount
  IF v_coupon_code IS NOT NULL THEN
    SELECT * INTO v_coupon FROM public.coupons
    WHERE upper(code) = v_coupon_code
    FOR UPDATE;

    IF NOT FOUND OR v_coupon.is_active = false THEN
      RAISE EXCEPTION 'Invalid coupon code';
    END IF;
    IF v_coupon.starts_at IS NOT NULL AND v_coupon.starts_at > now() THEN
      RAISE EXCEPTION 'Coupon is not active yet';
    END IF;
    IF v_coupon.ends_at IS NOT NULL AND v_coupon.ends_at < now() THEN
      RAISE EXCEPTION 'Coupon has expired';
    END IF;
    IF v_coupon.usage_limit IS NOT NULL AND v_coupon.usage_count >= v_coupon.usage_limit THEN
      RAISE EXCEPTION 'Coupon usage limit reached';
    END IF;
    IF v_subtotal < COALESCE(v_coupon.min_order_amount, 0) THEN
      RAISE EXCEPTION 'Order does not meet coupon minimum';
    END IF;

    SELECT COUNT(*) INTO v_user_redemptions
    FROM public.coupon_redemptions
    WHERE coupon_id = v_coupon.id AND user_id = p_user_id;

    IF v_coupon.per_user_limit IS NOT NULL AND v_user_redemptions >= v_coupon.per_user_limit THEN
      RAISE EXCEPTION 'You have already used this coupon';
    END IF;
    IF v_coupon.is_one_time AND v_user_redemptions > 0 THEN
      RAISE EXCEPTION 'This one-time coupon was already used';
    END IF;

    IF v_coupon.discount_type = 'percentage' THEN
      v_coupon_discount := round(v_subtotal * COALESCE(v_coupon.percent_off, 0) / 100.0, 2);
    ELSIF v_coupon.discount_type = 'fixed' THEN
      v_coupon_discount := COALESCE(v_coupon.amount_off, 0);
    ELSE
      v_coupon_discount := 0;
    END IF;

    IF v_coupon.max_discount_amount IS NOT NULL THEN
      v_coupon_discount := LEAST(v_coupon_discount, v_coupon.max_discount_amount);
    END IF;
    v_coupon_discount := LEAST(v_coupon_discount, v_subtotal);
    v_discount := v_discount + v_coupon_discount;

    IF v_coupon.free_delivery OR v_coupon.discount_type = 'free_delivery' THEN
      v_free_delivery := true;
    END IF;

    v_applied := v_applied || jsonb_build_array(jsonb_build_object(
      'id', v_coupon.id,
      'code', v_coupon.code,
      'name', v_coupon.name,
      'promoType', 'coupon',
      'discount', v_coupon_discount,
      'freeDelivery', v_coupon.free_delivery OR v_coupon.discount_type = 'free_delivery'
    ));
  END IF;

  IF v_discount > v_subtotal THEN
    v_discount := v_subtotal;
  END IF;

  -- Loyalty redemption (server-computed value + max percent cap)
  IF v_points > 0 THEN
    v_loyalty := public.ensure_loyalty_account(p_user_id);
    IF v_loyalty.points_balance < v_points THEN
      RAISE EXCEPTION 'Insufficient loyalty points';
    END IF;
    SELECT * INTO v_rule FROM public.loyalty_rules
    WHERE is_active = true ORDER BY created_at ASC LIMIT 1;
    IF FOUND THEN
      IF v_points < v_rule.min_redeem_points THEN
        RAISE EXCEPTION 'Minimum % points required to redeem', v_rule.min_redeem_points;
      END IF;
      v_points_value := round(v_points / NULLIF(v_rule.redeem_points_per_currency, 0), 2);
      v_remaining := GREATEST(v_subtotal - v_discount, 0);
      v_max_loyalty := round(v_remaining * COALESCE(v_rule.max_redeem_percent, 50) / 100.0, 2);
      v_points_value := LEAST(v_points_value, v_max_loyalty, v_remaining);
    ELSE
      v_points_value := round(v_points / 10.0, 2);
      v_remaining := GREATEST(v_subtotal - v_discount, 0);
      v_points_value := LEAST(v_points_value, v_remaining);
    END IF;
    v_discount := v_discount + COALESCE(v_points_value, 0);
  END IF;

  IF v_discount > v_subtotal THEN
    v_discount := v_subtotal;
  END IF;

  IF p_delivery_type = 'delivery' THEN
    IF NOT v_free_delivery THEN
      v_delivery_fee := 200;
    END IF;
  END IF;

  v_total := GREATEST(v_subtotal - v_discount, 0) + v_delivery_fee;

  -- Gift card (partial redemption)
  IF NULLIF(trim(p_gift_card_code), '') IS NOT NULL AND v_gift > 0 THEN
    SELECT * INTO v_gift_card FROM public.gift_cards
    WHERE upper(code) = upper(trim(p_gift_card_code))
    FOR UPDATE;
    IF NOT FOUND OR v_gift_card.status <> 'active' THEN
      RAISE EXCEPTION 'Invalid gift card';
    END IF;
    IF v_gift_card.expires_at IS NOT NULL AND v_gift_card.expires_at < now() THEN
      RAISE EXCEPTION 'Gift card expired';
    END IF;
    IF v_gift > v_gift_card.balance THEN
      RAISE EXCEPTION 'Gift card balance too low';
    END IF;
    IF v_gift > v_total THEN
      v_gift := v_total;
    END IF;
    v_total := v_total - v_gift;
  ELSE
    v_gift := 0;
  END IF;

  INSERT INTO public.orders (
    user_id, status, total, payment_status, payment_method,
    delivery_type, pickup_location_id, delivery_address,
    delivery_fee, customer_note,
    discount_amount, coupon_code, loyalty_points_redeemed,
    gift_card_amount, free_delivery, promotions_applied, referral_code
  )
  VALUES (
    p_user_id, 'pending', v_total, 'pending', v_payment_method,
    p_delivery_type, p_pickup_location_id, p_delivery_address,
    v_delivery_fee, NULLIF(trim(p_customer_note), ''),
    v_discount, v_coupon_code, v_points,
    v_gift, v_free_delivery,
    v_applied,
    NULLIF(upper(trim(p_referral_code)), '')
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
  WHERE c.user_id = p_user_id AND p.id = c.product_id;

  DELETE FROM public.cart_items WHERE user_id = p_user_id;

  IF v_coupon.id IS NOT NULL THEN
    INSERT INTO public.coupon_redemptions (coupon_id, user_id, order_id, discount_amount)
    VALUES (v_coupon.id, p_user_id, v_order_id, v_coupon_discount);
    UPDATE public.coupons SET usage_count = usage_count + 1 WHERE id = v_coupon.id;
  END IF;

  IF v_points > 0 THEN
    UPDATE public.loyalty_accounts
    SET points_balance = points_balance - v_points,
        lifetime_redeemed = lifetime_redeemed + v_points
    WHERE user_id = p_user_id
    RETURNING * INTO v_loyalty;

    INSERT INTO public.loyalty_transactions (
      user_id, tx_type, points, balance_after, order_id, description
    ) VALUES (
      p_user_id, 'redeem_discount', -v_points, v_loyalty.points_balance, v_order_id,
      'Redeemed at checkout'
    );
  END IF;

  IF v_gift > 0 AND v_gift_card.id IS NOT NULL THEN
    UPDATE public.gift_cards
    SET balance = balance - v_gift,
        status = CASE WHEN balance - v_gift <= 0 THEN 'depleted' ELSE status END
    WHERE id = v_gift_card.id
    RETURNING * INTO v_gift_card;

    INSERT INTO public.gift_card_transactions (
      gift_card_id, user_id, order_id, tx_type, amount, balance_after
    ) VALUES (
      v_gift_card.id, p_user_id, v_order_id, 'redeem', v_gift, v_gift_card.balance
    );
  END IF;

  INSERT INTO public.reward_events (user_id, order_id, event_type, payload)
  VALUES (
    p_user_id, v_order_id, 'checkout_rewards_applied',
    jsonb_build_object(
      'discount', v_discount,
      'gift_card', v_gift,
      'points', v_points,
      'coupon', v_coupon_code,
      'free_delivery', v_free_delivery,
      'client_discount_ignored', COALESCE(p_discount_amount, 0),
      'client_free_delivery_ignored', COALESCE(p_free_delivery, false)
    )
  );

  PERFORM public.log_order_event(v_order_id, 'order_placed', jsonb_build_object(
    'delivery_type', p_delivery_type,
    'payment_method', v_payment_method,
    'discount_amount', v_discount
  ));

  RETURN v_order_id;
END;
$$;

REVOKE ALL ON FUNCTION public.place_order(
  uuid, text, uuid, jsonb, text, text, text, integer, text, numeric, numeric, boolean, jsonb, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_order(
  uuid, text, uuid, jsonb, text, text, text, integer, text, numeric, numeric, boolean, jsonb, text
) TO authenticated;

-- ---------------------------------------------------------------------------
-- 3. Harden finalize_payment — payment owner or admin only
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
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF v_status NOT IN ('paid', 'failed', 'cancelled', 'expired', 'processing') THEN
    RAISE EXCEPTION 'Invalid finalize status: %', p_status;
  END IF;

  SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found';
  END IF;

  IF auth.uid() IS DISTINCT FROM v_payment.user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF v_payment.status = 'paid' AND v_status = 'paid' THEN
    INSERT INTO public.payment_events (payment_id, event_type, payload)
    VALUES (
      p_payment_id,
      'duplicate_callback_ignored',
      COALESCE(p_raw_callback, '{}'::jsonb)
    );
    RETURN v_payment;
  END IF;

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

-- ---------------------------------------------------------------------------
-- 4. Harden award_loyalty_for_order — order owner or admin only
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.award_loyalty_for_order(p_order_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order public.orders;
  v_rule public.loyalty_rules;
  v_points integer := 0;
  v_loyalty public.loyalty_accounts;
  v_existing integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF auth.uid() IS DISTINCT FROM v_order.user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT COUNT(*) INTO v_existing
  FROM public.loyalty_transactions
  WHERE order_id = p_order_id AND tx_type = 'earn_purchase';
  IF v_existing > 0 THEN
    RETURN 0;
  END IF;

  SELECT * INTO v_rule FROM public.loyalty_rules WHERE is_active = true ORDER BY created_at ASC LIMIT 1;
  IF NOT FOUND THEN
    v_points := floor(v_order.total * 0.01)::integer;
  ELSE
    v_points := floor(v_order.total * v_rule.earn_points_per_currency)::integer;
  END IF;

  IF v_points <= 0 THEN
    RETURN 0;
  END IF;

  v_loyalty := public.ensure_loyalty_account(v_order.user_id);
  UPDATE public.loyalty_accounts
  SET points_balance = points_balance + v_points,
      lifetime_earned = lifetime_earned + v_points
  WHERE user_id = v_order.user_id
  RETURNING * INTO v_loyalty;

  INSERT INTO public.loyalty_transactions (
    user_id, tx_type, points, balance_after, order_id, description
  ) VALUES (
    v_order.user_id, 'earn_purchase', v_points, v_loyalty.points_balance, p_order_id,
    'Points earned from order'
  );

  RETURN v_points;
END;
$$;

REVOKE ALL ON FUNCTION public.award_loyalty_for_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.award_loyalty_for_order(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 5. payments RLS — admin-only direct UPDATE (RPCs handle customer flows)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS payments_update_own_or_admin ON public.payments;

CREATE POLICY payments_update_admin_only ON public.payments
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ---------------------------------------------------------------------------
-- 6. orders — remove broad admin UPDATE; guard sensitive columns on direct UPDATE
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Admins can update orders" ON public.orders;

CREATE POLICY orders_update_admin_note ON public.orders
  FOR UPDATE TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

CREATE OR REPLACE FUNCTION public.guard_orders_direct_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  -- SECURITY DEFINER RPCs run as the function owner (postgres) and may update freely.
  IF current_user IN ('postgres', 'supabase_admin', 'service_role') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.status IS DISTINCT FROM OLD.status
       OR NEW.payment_status IS DISTINCT FROM OLD.payment_status
       OR NEW.total IS DISTINCT FROM OLD.total
       OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount
       OR NEW.delivery_fee IS DISTINCT FROM OLD.delivery_fee
       OR NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.delivery_type IS DISTINCT FROM OLD.delivery_type
       OR NEW.pickup_location_id IS DISTINCT FROM OLD.pickup_location_id
       OR NEW.delivery_address IS DISTINCT FROM OLD.delivery_address
       OR NEW.payment_method IS DISTINCT FROM OLD.payment_method
       OR NEW.gift_card_amount IS DISTINCT FROM OLD.gift_card_amount
       OR NEW.loyalty_points_redeemed IS DISTINCT FROM OLD.loyalty_points_redeemed
       OR NEW.free_delivery IS DISTINCT FROM OLD.free_delivery
       OR NEW.coupon_code IS DISTINCT FROM OLD.coupon_code
       OR NEW.mpesa_receipt_number IS DISTINCT FROM OLD.mpesa_receipt_number
    THEN
      RAISE EXCEPTION 'Direct order updates to status, payment, or financial fields are not allowed. Use order RPCs.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_guard_sensitive_update ON public.orders;
CREATE TRIGGER orders_guard_sensitive_update
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_orders_direct_update();
