CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    event_type text NOT NULL,
    channel text DEFAULT 'in_app'::text NOT NULL,
    title text NOT NULL,
    body text NOT NULL,
    link text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    status text DEFAULT 'unread'::text NOT NULL,
    audience text DEFAULT 'customer'::text NOT NULL,
    read_at timestamp with time zone,
    archived_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT notifications_audience_check CHECK ((audience = ANY (ARRAY['customer'::text, 'admin'::text, 'system'::text]))),
    CONSTRAINT notifications_channel_check CHECK ((channel = ANY (ARRAY['in_app'::text, 'email'::text, 'sms'::text, 'push'::text]))),
    CONSTRAINT notifications_status_check CHECK ((status = ANY (ARRAY['unread'::text, 'read'::text, 'archived'::text])))
);


--
-- Name: archive_notification(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_notification(p_notification_id uuid) RETURNS public.notifications
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_row public.notifications;
BEGIN
  UPDATE public.notifications
  SET status = 'archived',
      archived_at = now(),
      read_at = COALESCE(read_at, now()),
      updated_at = now()
  WHERE id = p_notification_id
    AND (user_id = auth.uid() OR public.is_admin())
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Notification not found';
  END IF;
  RETURN v_row;
END;
$$;


--
-- Name: award_loyalty_for_order(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.award_loyalty_for_order(p_order_id uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: cancel_order(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_order(p_order_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: compute_checkout_promotions(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.compute_checkout_promotions(p_user_id uuid) RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    user_id uuid NOT NULL,
    provider text DEFAULT 'mpesa'::text NOT NULL,
    method text DEFAULT 'mpesa'::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    amount numeric(12,2) NOT NULL,
    currency text DEFAULT 'KES'::text NOT NULL,
    phone_number text,
    transaction_reference text,
    checkout_request_id text,
    merchant_request_id text,
    receipt_number text,
    failure_reason text,
    raw_request jsonb DEFAULT '{}'::jsonb NOT NULL,
    raw_response jsonb DEFAULT '{}'::jsonb NOT NULL,
    raw_callback jsonb DEFAULT '{}'::jsonb NOT NULL,
    expires_at timestamp with time zone,
    paid_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payments_amount_positive CHECK ((amount > (0)::numeric)),
    CONSTRAINT payments_method_check CHECK ((method = ANY (ARRAY['cod'::text, 'mpesa'::text, 'card'::text, 'paypal'::text, 'bank_transfer'::text]))),
    CONSTRAINT payments_provider_check CHECK ((provider = ANY (ARRAY['mpesa'::text, 'mock_mpesa'::text, 'card'::text, 'paypal'::text, 'bank'::text, 'cod'::text]))),
    CONSTRAINT payments_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'initiated'::text, 'processing'::text, 'paid'::text, 'failed'::text, 'cancelled'::text, 'expired'::text, 'refunded'::text])))
);


--
-- Name: create_payment_for_order(uuid, text, text, text, numeric); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_payment_for_order(p_order_id uuid, p_method text DEFAULT 'mpesa'::text, p_provider text DEFAULT 'mock_mpesa'::text, p_phone_number text DEFAULT NULL::text, p_amount numeric DEFAULT NULL::numeric) RETURNS public.payments
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: enforce_single_default_address(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_single_default_address() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF NEW.is_default THEN
    UPDATE public.customer_addresses
    SET is_default = false
    WHERE user_id = NEW.user_id
      AND id IS DISTINCT FROM NEW.id
      AND is_default = true;
  END IF;
  RETURN NEW;
END;
$$;


--
-- Name: loyalty_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loyalty_accounts (
    user_id uuid NOT NULL,
    points_balance integer DEFAULT 0 NOT NULL,
    lifetime_earned integer DEFAULT 0 NOT NULL,
    lifetime_redeemed integer DEFAULT 0 NOT NULL,
    referral_code text NOT NULL,
    tier text DEFAULT 'member'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT loyalty_accounts_balance_nonneg CHECK ((points_balance >= 0))
);


--
-- Name: ensure_loyalty_account(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_loyalty_account(p_user_id uuid DEFAULT auth.uid()) RETURNS public.loyalty_accounts
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_row public.loyalty_accounts;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_user_id <> auth.uid() AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  SELECT * INTO v_row FROM public.loyalty_accounts WHERE user_id = p_user_id;
  IF FOUND THEN
    RETURN v_row;
  END IF;

  INSERT INTO public.loyalty_accounts (user_id, referral_code)
  VALUES (p_user_id, public.generate_referral_code())
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


--
-- Name: notification_preferences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_preferences (
    user_id uuid NOT NULL,
    email_enabled boolean DEFAULT true NOT NULL,
    sms_enabled boolean DEFAULT false NOT NULL,
    in_app_enabled boolean DEFAULT true NOT NULL,
    push_enabled boolean DEFAULT false NOT NULL,
    marketing_emails boolean DEFAULT false NOT NULL,
    order_updates boolean DEFAULT true NOT NULL,
    payment_updates boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: ensure_notification_preferences(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_notification_preferences(p_user_id uuid DEFAULT auth.uid()) RETURNS public.notification_preferences
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_row public.notification_preferences;
  v_cp public.customer_preferences;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_user_id <> auth.uid() AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  SELECT * INTO v_row FROM public.notification_preferences WHERE user_id = p_user_id;
  IF FOUND THEN
    RETURN v_row;
  END IF;

  SELECT * INTO v_cp FROM public.customer_preferences WHERE user_id = p_user_id;

  INSERT INTO public.notification_preferences (
    user_id, email_enabled, sms_enabled, in_app_enabled, push_enabled,
    marketing_emails, order_updates, payment_updates
  ) VALUES (
    p_user_id,
    COALESCE(v_cp.email_notifications, true),
    COALESCE(v_cp.sms_notifications, false),
    true,
    false,
    COALESCE(v_cp.marketing_emails, false),
    COALESCE(v_cp.order_updates, true),
    COALESCE(v_cp.payment_updates, true)
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


--
-- Name: finalize_payment(uuid, text, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.finalize_payment(p_payment_id uuid, p_status text, p_receipt_number text DEFAULT NULL::text, p_transaction_reference text DEFAULT NULL::text, p_failure_reason text DEFAULT NULL::text, p_raw_callback jsonb DEFAULT '{}'::jsonb) RETURNS public.payments
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: generate_referral_code(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_referral_code() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
  v_code text;
BEGIN
  LOOP
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.loyalty_accounts WHERE referral_code = v_code
    );
  END LOOP;
  RETURN v_code;
END;
$$;


--
-- Name: get_bestseller_product_ids(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_bestseller_product_ids(p_limit integer DEFAULT 12) RETURNS TABLE(product_id uuid, units_sold bigint)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT
    oi.product_id,
    SUM(oi.quantity)::bigint AS units_sold
  FROM public.order_items oi
  INNER JOIN public.orders o ON o.id = oi.order_id
  INNER JOIN public.products p ON p.id = oi.product_id
  WHERE oi.product_id IS NOT NULL
    AND o.status IS DISTINCT FROM 'cancelled'
    AND p.is_active IS TRUE
  GROUP BY oi.product_id
  ORDER BY units_sold DESC, oi.product_id
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 12), 50));
$$;


--
-- Name: FUNCTION get_bestseller_product_ids(p_limit integer); Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON FUNCTION public.get_bestseller_product_ids(p_limit integer) IS 'WS5 M5.3 — anonymized bestseller ids for storefront recommendations (SECURITY DEFINER).';


--
-- Name: guard_orders_direct_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_orders_direct_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
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


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, phone, role)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'phone', ''),
    'customer'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;


--
-- Name: log_order_event(uuid, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_order_event(p_order_id uuid, p_event_type text, p_payload jsonb DEFAULT '{}'::jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO public.order_events (order_id, event_type, payload)
  VALUES (p_order_id, p_event_type, COALESCE(p_payload, '{}'::jsonb));
END;
$$;


--
-- Name: lookup_gift_card(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.lookup_gift_card(p_code text) RETURNS TABLE(id uuid, code text, balance numeric, status text, expires_at timestamp with time zone, currency text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  RETURN QUERY
  SELECT g.id, g.code, g.balance, g.status, g.expires_at, g.currency
  FROM public.gift_cards g
  WHERE upper(g.code) = upper(trim(p_code))
  LIMIT 1;
END;
$$;


--
-- Name: mark_all_notifications_read(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_all_notifications_read(p_audience text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.notifications
  SET status = 'read',
      read_at = COALESCE(read_at, now()),
      updated_at = now()
  WHERE user_id = auth.uid()
    AND status = 'unread'
    AND (p_audience IS NULL OR audience = p_audience);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;


--
-- Name: mark_notification_read(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_notification_read(p_notification_id uuid) RETURNS public.notifications
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_row public.notifications;
BEGIN
  UPDATE public.notifications
  SET status = 'read',
      read_at = COALESCE(read_at, now()),
      updated_at = now()
  WHERE id = p_notification_id
    AND (user_id = auth.uid() OR public.is_admin())
    AND status <> 'archived'
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Notification not found';
  END IF;
  RETURN v_row;
END;
$$;


--
-- Name: mark_payment_initiated(uuid, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.mark_payment_initiated(p_payment_id uuid, p_checkout_request_id text, p_merchant_request_id text DEFAULT NULL::text, p_raw_response jsonb DEFAULT '{}'::jsonb) RETURNS public.payments
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: notify_admin_users(text, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_admin_users(p_event_type text, p_title text, p_body text, p_link text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_count integer := 0;
  v_admin record;
BEGIN
  FOR v_admin IN
    SELECT id FROM public.profiles WHERE role = 'admin'
  LOOP
    INSERT INTO public.notifications (
      user_id, event_type, channel, title, body, link, metadata, audience, status
    ) VALUES (
      v_admin.id, p_event_type, 'in_app', p_title, p_body, p_link,
      COALESCE(p_metadata, '{}'::jsonb), 'admin', 'unread'
    );
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$$;


--
-- Name: place_order(uuid, text, uuid, jsonb, text, text, text, integer, text, numeric, numeric, boolean, jsonb, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.place_order(p_user_id uuid DEFAULT auth.uid(), p_delivery_type text DEFAULT NULL::text, p_pickup_location_id uuid DEFAULT NULL::uuid, p_delivery_address jsonb DEFAULT NULL::jsonb, p_customer_note text DEFAULT NULL::text, p_payment_method text DEFAULT 'cod'::text, p_coupon_code text DEFAULT NULL::text, p_loyalty_points integer DEFAULT 0, p_gift_card_code text DEFAULT NULL::text, p_gift_card_amount numeric DEFAULT 0, p_discount_amount numeric DEFAULT 0, p_free_delivery boolean DEFAULT false, p_promotions_applied jsonb DEFAULT '[]'::jsonb, p_referral_code text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
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


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


--
-- Name: update_order_payment_status(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_order_payment_status(p_order_id uuid, p_payment_status text, p_note text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: update_order_status(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_order_status(p_order_id uuid, p_status text, p_note text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: write_admin_audit(text, text, text, text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.write_admin_audit(p_action text, p_entity_type text, p_entity_id text DEFAULT NULL::text, p_summary text DEFAULT NULL::text, p_metadata jsonb DEFAULT '{}'::jsonb) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  INSERT INTO public.admin_audit_logs (
    actor_id, action, entity_type, entity_id, summary, metadata
  ) VALUES (
    auth.uid(),
    trim(p_action),
    trim(p_entity_type),
    NULLIF(trim(p_entity_id), ''),
    NULLIF(trim(p_summary), ''),
    COALESCE(p_metadata, '{}'::jsonb)
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;


--
-- Name: apply_rls(jsonb, integer); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer DEFAULT (1024 * 1024)) RETURNS SETOF realtime.wal_rls
    LANGUAGE plpgsql
    AS $$
declare
    -- Regclass of the table e.g. public.notes
    entity_ regclass = (quote_ident(wal ->> 'schema') || '.' || quote_ident(wal ->> 'table'))::regclass;

    -- I, U, D, T: insert, update ...
    action realtime.action = (
        case wal ->> 'action'
            when 'I' then 'INSERT'
            when 'U' then 'UPDATE'
            when 'D' then 'DELETE'
            else 'ERROR'
        end
    );

    -- Is row level security enabled for the table
    is_rls_enabled bool = relrowsecurity from pg_class where oid = entity_;

    subscriptions realtime.subscription[] = array_agg(subs)
        from
            realtime.subscription subs
        where
            subs.entity = entity_
            -- Filter by action early - only get subscriptions interested in this action
            -- action_filter column can be: '*' (all), 'INSERT', 'UPDATE', or 'DELETE'
            and (subs.action_filter = '*' or subs.action_filter = action::text);

    -- Subscription vars
    working_role regrole;
    working_selected_columns text[];
    claimed_role regrole;
    claims jsonb;

    subscription_id uuid;
    subscription_has_access bool;
    visible_to_subscription_ids uuid[] = '{}';

    -- structured info for wal's columns
    columns realtime.wal_column[];
    -- previous identity values for update/delete
    old_columns realtime.wal_column[];

    error_record_exceeds_max_size boolean = octet_length(wal::text) > max_record_bytes;

    -- Primary jsonb output for record
    output jsonb;

    -- Loop record for iterating unique roles (outer loop)
    role_record record;
    -- Loop record for iterating unique selected_columns within a role (inner loop)
    cols_record record;
    -- Subscription ids visible at the role level (before fanning out by selected_columns)
    visible_role_sub_ids uuid[] = '{}';

begin
    perform set_config('role', null, true);

    columns =
        array_agg(
            (
                x->>'name',
                x->>'type',
                x->>'typeoid',
                realtime.cast(
                    (x->'value') #>> '{}',
                    coalesce(
                        (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                        (x->>'type')::regtype
                    )
                ),
                (pks ->> 'name') is not null,
                true
            )::realtime.wal_column
        )
        from
            jsonb_array_elements(wal -> 'columns') x
            left join jsonb_array_elements(wal -> 'pk') pks
                on (x ->> 'name') = (pks ->> 'name');

    old_columns =
        array_agg(
            (
                x->>'name',
                x->>'type',
                x->>'typeoid',
                realtime.cast(
                    (x->'value') #>> '{}',
                    coalesce(
                        (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                        (x->>'type')::regtype
                    )
                ),
                (pks ->> 'name') is not null,
                true
            )::realtime.wal_column
        )
        from
            jsonb_array_elements(wal -> 'identity') x
            left join jsonb_array_elements(wal -> 'pk') pks
                on (x ->> 'name') = (pks ->> 'name');

    for role_record in
        select claims_role
        from (select distinct claims_role from unnest(subscriptions)) t
        order by claims_role::text
    loop
        working_role := role_record.claims_role;

        -- Update `is_selectable` for columns and old_columns (once per role)
        columns =
            array_agg(
                (
                    c.name,
                    c.type_name,
                    c.type_oid,
                    c.value,
                    c.is_pkey,
                    pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                )::realtime.wal_column
            )
            from
                unnest(columns) c;

        old_columns =
                array_agg(
                    (
                        c.name,
                        c.type_name,
                        c.type_oid,
                        c.value,
                        c.is_pkey,
                        pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                    )::realtime.wal_column
                )
                from
                    unnest(old_columns) c;

        if action <> 'DELETE' and count(1) = 0 from unnest(columns) c where c.is_pkey then
            -- Fan out 400 error per distinct selected_columns for this role
            for cols_record in
                select selected_columns
                from (select distinct selected_columns from unnest(subscriptions) s where s.claims_role = working_role) t
                order by coalesce(array_to_string(selected_columns, ','), '')
            loop
                working_selected_columns := cols_record.selected_columns;
                return next (
                    jsonb_build_object(
                        'schema', wal ->> 'schema',
                        'table', wal ->> 'table',
                        'type', action
                    ),
                    is_rls_enabled,
                    (select array_agg(s.subscription_id) from unnest(subscriptions) as s where s.claims_role = working_role and (s.selected_columns is not distinct from working_selected_columns)),
                    array['Error 400: Bad Request, no primary key']
                )::realtime.wal_rls;
            end loop;

        -- The claims role does not have SELECT permission to the primary key of entity
        elsif action <> 'DELETE' and sum(c.is_selectable::int) <> count(1) from unnest(columns) c where c.is_pkey then
            -- Fan out 401 error per distinct selected_columns for this role
            for cols_record in
                select selected_columns
                from (select distinct selected_columns from unnest(subscriptions) s where s.claims_role = working_role) t
                order by coalesce(array_to_string(selected_columns, ','), '')
            loop
                working_selected_columns := cols_record.selected_columns;
                return next (
                    jsonb_build_object(
                        'schema', wal ->> 'schema',
                        'table', wal ->> 'table',
                        'type', action
                    ),
                    is_rls_enabled,
                    (select array_agg(s.subscription_id) from unnest(subscriptions) as s where s.claims_role = working_role and (s.selected_columns is not distinct from working_selected_columns)),
                    array['Error 401: Unauthorized']
                )::realtime.wal_rls;
            end loop;

        else
            -- Create the prepared statement (once per role)
            if is_rls_enabled and action <> 'DELETE' then
                if (select 1 from pg_prepared_statements where name = 'walrus_rls_stmt' limit 1) > 0 then
                    deallocate walrus_rls_stmt;
                end if;
                execute realtime.build_prepared_statement_sql('walrus_rls_stmt', entity_, columns);
            end if;

            -- Collect all visible subscription IDs for this role (filter check + RLS check)
            visible_role_sub_ids = '{}';

            for subscription_id, claims in (
                    select
                        subs.subscription_id,
                        subs.claims
                    from
                        unnest(subscriptions) subs
                    where
                        subs.entity = entity_
                        and subs.claims_role = working_role
                        and (
                            realtime.is_visible_through_filters(columns, subs.filters)
                            or (
                              action = 'DELETE'
                              and realtime.is_visible_through_filters(old_columns, subs.filters)
                            )
                        )
            ) loop

                if not is_rls_enabled or action = 'DELETE' then
                    visible_role_sub_ids = visible_role_sub_ids || subscription_id;
                else
                    -- Check if RLS allows the role to see the record
                    perform
                        -- Trim leading and trailing quotes from working_role because set_config
                        -- doesn't recognize the role as valid if they are included
                        set_config('role', trim(both '"' from working_role::text), true),
                        set_config('request.jwt.claims', claims::text, true);

                    execute 'execute walrus_rls_stmt' into subscription_has_access;

                    -- Reset the role on every FOR..LOOP batch execution.
                    -- The first batch of 10 rows is pre-fetched using the current connection role (PG internal behaviour)
                    -- then we have to reset it again otherwise it would use the role defined in the `set_config` above
                    -- to fetch the remaining rows when rows>10, which could be a user-defined role that lacks execution grants.
                    -- The flow is:
                    --   1. run batch with conn role
                    --   2. set_config working_role
                    --   3. execute walrus
                    --   4. reset role (revert)
                    --   5. repeat
                    perform set_config('role', null, true);

                    if subscription_has_access then
                        visible_role_sub_ids = visible_role_sub_ids || subscription_id;
                    end if;
                end if;
            end loop;

            perform set_config('role', null, true);

            -- Inner loop: per distinct selected_columns for this role
            for cols_record in
                select selected_columns
                from (select distinct selected_columns from unnest(subscriptions) s where s.claims_role = working_role) t
                order by coalesce(array_to_string(selected_columns, ','), '')
            loop
                working_selected_columns := cols_record.selected_columns;

                output = jsonb_build_object(
                    'schema', wal ->> 'schema',
                    'table', wal ->> 'table',
                    'type', action,
                    'commit_timestamp', to_char(
                        ((wal ->> 'timestamp')::timestamptz at time zone 'utc'),
                        'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
                    ),
                    'columns', (
                        select
                            jsonb_agg(
                                jsonb_build_object(
                                    'name', pa.attname,
                                    'type', pt.typname
                                )
                                order by pa.attnum asc
                            )
                        from
                            pg_attribute pa
                            join pg_type pt
                                on pa.atttypid = pt.oid
                            left join (
                                select unnest(conkey) as pkey_attnum
                                from pg_constraint
                                where conrelid = entity_ and contype = 'p'
                            ) pk on pk.pkey_attnum = pa.attnum
                        where
                            attrelid = entity_
                            and attnum > 0
                            and pg_catalog.has_column_privilege(working_role, entity_, pa.attname, 'SELECT')
                            and (working_selected_columns is null or pa.attname = any(working_selected_columns) or pk.pkey_attnum is not null)
                    )
                )
                -- Add "record" key for insert and update
                || case
                    when action in ('INSERT', 'UPDATE') then
                        jsonb_build_object(
                            'record',
                            (
                                select
                                    jsonb_object_agg(
                                        -- if unchanged toast, get column name and value from old record
                                        coalesce((c).name, (oc).name),
                                        case
                                            when (c).name is null then (oc).value
                                            else (c).value
                                        end
                                    )
                                from
                                    unnest(columns) c
                                    full outer join unnest(old_columns) oc
                                        on (c).name = (oc).name
                                where
                                    coalesce((c).is_selectable, (oc).is_selectable)
                                    and (working_selected_columns is null or coalesce((c).name, (oc).name) = any(working_selected_columns) or coalesce((c).is_pkey, (oc).is_pkey))
                                    and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                            )
                        )
                    else '{}'::jsonb
                end
                -- Add "old_record" key for update and delete
                || case
                    when action = 'UPDATE' then
                        jsonb_build_object(
                                'old_record',
                                (
                                    select jsonb_object_agg((c).name, (c).value)
                                    from unnest(old_columns) c
                                    where
                                        (c).is_selectable
                                        and (working_selected_columns is null or (c).name = any(working_selected_columns) or (c).is_pkey)
                                        and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                                )
                            )
                    when action = 'DELETE' then
                        jsonb_build_object(
                            'old_record',
                            (
                                select jsonb_object_agg((c).name, (c).value)
                                from unnest(old_columns) c
                                where
                                    (c).is_selectable
                                    and (working_selected_columns is null or (c).name = any(working_selected_columns) or (c).is_pkey)
                                    and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                                    and ( not is_rls_enabled or (c).is_pkey ) -- if RLS enabled, we can't secure deletes so filter to pkey
                            )
                        )
                    else '{}'::jsonb
                end;

                -- Filter visible_role_sub_ids to those matching the current selected_columns group
                visible_to_subscription_ids = coalesce(
                    (
                        select array_agg(s.subscription_id)
                        from unnest(subscriptions) s
                        where s.claims_role = working_role
                          and (s.selected_columns is not distinct from working_selected_columns)
                          and s.subscription_id = any(visible_role_sub_ids)
                    ),
                    '{}'::uuid[]
                );

                return next (
                    output,
                    is_rls_enabled,
                    visible_to_subscription_ids,
                    case
                        when error_record_exceeds_max_size then array['Error 413: Payload Too Large']
                        else '{}'
                    end
                )::realtime.wal_rls;
            end loop;

        end if;
    end loop;

    perform set_config('role', null, true);
end;
$$;


--
-- Name: broadcast_changes(text, text, text, text, text, record, record, text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text DEFAULT 'ROW'::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    -- Declare a variable to hold the JSONB representation of the row
    row_data jsonb := '{}'::jsonb;
BEGIN
    IF level = 'STATEMENT' THEN
        RAISE EXCEPTION 'function can only be triggered for each row, not for each statement';
    END IF;
    -- Check the operation type and handle accordingly
    IF operation = 'INSERT' OR operation = 'UPDATE' OR operation = 'DELETE' THEN
        row_data := jsonb_build_object('old_record', OLD, 'record', NEW, 'operation', operation, 'table', table_name, 'schema', table_schema);
        PERFORM realtime.send (row_data, event_name, topic_name);
    ELSE
        RAISE EXCEPTION 'Unexpected operation type: %', operation;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to process the row: %', SQLERRM;
END;

$$;


--
-- Name: build_prepared_statement_sql(text, regclass, realtime.wal_column[]); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[]) RETURNS text
    LANGUAGE sql
    AS $$
      /*
      Builds a sql string that, if executed, creates a prepared statement to
      tests retrive a row from *entity* by its primary key columns.
      Example
          select realtime.build_prepared_statement_sql('public.notes', '{"id"}'::text[], '{"bigint"}'::text[])
      */
          select
      'prepare ' || prepared_statement_name || ' as
          select
              exists(
                  select
                      1
                  from
                      ' || entity || '
                  where
                      ' || string_agg(quote_ident(pkc.name) || '=' || quote_nullable(pkc.value #>> '{}') , ' and ') || '
              )'
          from
              unnest(columns) pkc
          where
              pkc.is_pkey
          group by
              entity
      $$;


--
-- Name: cast(text, regtype); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime."cast"(val text, type_ regtype) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare
  res jsonb;
begin
  if type_::text = 'bytea' then
    return to_jsonb(val);
  end if;
  execute format('select to_jsonb(%L::'|| type_::text || ')', val) into res;
  return res;
end
$$;


--
-- Name: check_equality_op(realtime.equality_op, regtype, text, text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
/*
Casts *val_1* and *val_2* as type *type_* and check the *op* condition for truthiness
*/
declare
    op_symbol text = (
        case
            when op = 'eq' then '='
            when op = 'neq' then '!='
            when op = 'lt' then '<'
            when op = 'lte' then '<='
            when op = 'gt' then '>'
            when op = 'gte' then '>='
            when op = 'in' then '= any'
            else 'UNKNOWN OP'
        end
    );
    res boolean;
begin
    execute format(
        'select %L::'|| type_::text || ' ' || op_symbol
        || ' ( %L::'
        || (
            case
                when op = 'in' then type_::text || '[]'
                else type_::text end
        )
        || ')', val_1, val_2) into res;
    return res;
end;
$$;


--
-- Name: check_equality_op(realtime.equality_op, regtype, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text, negate boolean) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
declare
    op_symbol text;
    res boolean;
begin
    -- IS DISTINCT FROM / IS NOT DISTINCT FROM: infix, both sides typed literals
    if op = 'isdistinct' then
        execute format(
            'select %L::%s %s %L::%s',
            val_1,
            type_::text,
            case when negate then 'IS NOT DISTINCT FROM' else 'IS DISTINCT FROM' end,
            val_2,
            type_::text
        ) into res;
        return res;
    end if;

    -- IS requires a keyword RHS (NULL, TRUE, FALSE, UNKNOWN), not a typed literal
    if op = 'is' then
        if val_2 not in ('null', 'true', 'false', 'unknown') then
            raise exception 'invalid value for is filter: must be null, true, false, or unknown';
        end if;
        execute format(
            'select %L::%s %s %s',
            val_1,
            type_::text,
            case when negate then 'IS NOT' else 'IS' end,
            upper(val_2)
        ) into res;
        return res;
    end if;

    op_symbol = case
        when op = 'eq'    then '='
        when op = 'neq'   then '!='
        when op = 'lt'    then '<'
        when op = 'lte'   then '<='
        when op = 'gt'    then '>'
        when op = 'gte'   then '>='
        when op = 'in'    then '= any'
        when op = 'like'   then 'LIKE'
        when op = 'ilike'  then 'ILIKE'
        when op = 'match'  then '~'
        when op = 'imatch' then '~*'
        else null
    end;

    if op_symbol is null then
        raise exception 'unsupported equality operator: %', op::text;
    end if;

    execute format(
        'select %L::%s %s (%L::%s)',
        val_1,
        type_::text,
        op_symbol,
        val_2,
        case when op = 'in' then type_::text || '[]' else type_::text end
    ) into res;

    return case when negate then not res else res end;
end;
$$;


--
-- Name: is_visible_through_filters(realtime.wal_column[], realtime.user_defined_filter[]); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[]) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    select
        filters is null
        or array_length(filters, 1) is null
        or coalesce(
            count(col.name) = count(1)
            and sum(
                realtime.check_equality_op(
                    op:=f.op,
                    type_:=coalesce(col.type_oid::regtype, col.type_name::regtype),
                    val_1:=col.value #>> '{}',
                    val_2:=f.value,
                    negate:=coalesce(f.negate, false)
                )::int
            ) filter (where col.name is not null) = count(col.name),
            false
        )
    from
        unnest(filters) f
        left join unnest(columns) col
            on f.column_name = col.name;
$$;


--
-- Name: list_changes(name, name, integer, integer); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer) RETURNS TABLE(wal jsonb, is_rls_enabled boolean, subscription_ids uuid[], errors text[], slot_changes_count bigint)
    LANGUAGE sql
    SET log_min_messages TO 'fatal'
    AS $$
  WITH pub AS (
    SELECT
      concat_ws(
        ',',
        CASE WHEN bool_or(pubinsert) THEN 'insert' ELSE NULL END,
        CASE WHEN bool_or(pubupdate) THEN 'update' ELSE NULL END,
        CASE WHEN bool_or(pubdelete) THEN 'delete' ELSE NULL END
      ) AS w2j_actions,
      coalesce(
        string_agg(
          realtime.quote_wal2json(format('%I.%I', schemaname, tablename)::regclass),
          ','
        ) filter (WHERE ppt.tablename IS NOT NULL),
        ''
      ) AS w2j_add_tables
    FROM pg_publication pp
    LEFT JOIN pg_publication_tables ppt ON pp.pubname = ppt.pubname
    WHERE pp.pubname = publication
    GROUP BY pp.pubname
    LIMIT 1
  ),
  -- MATERIALIZED ensures pg_logical_slot_get_changes is called exactly once
  w2j AS MATERIALIZED (
    SELECT x.*, pub.w2j_add_tables
    FROM pub,
         pg_logical_slot_get_changes(
           slot_name, null, max_changes,
           'include-pk', 'true',
           'include-transaction', 'false',
           'include-timestamp', 'true',
           'include-type-oids', 'true',
           'format-version', '2',
           'actions', pub.w2j_actions,
           'add-tables', pub.w2j_add_tables
         ) x
  ),
  slot_count AS (
    SELECT count(*)::bigint AS cnt
    FROM w2j
    WHERE w2j.w2j_add_tables <> ''
  ),
  rls_filtered AS (
    SELECT xyz.wal, xyz.is_rls_enabled, xyz.subscription_ids, xyz.errors
    FROM w2j,
         realtime.apply_rls(
           wal := w2j.data::jsonb,
           max_record_bytes := max_record_bytes
         ) xyz(wal, is_rls_enabled, subscription_ids, errors)
    WHERE w2j.w2j_add_tables <> ''
      AND xyz.subscription_ids[1] IS NOT NULL
  )
  SELECT rf.wal, rf.is_rls_enabled, rf.subscription_ids, rf.errors, sc.cnt
  FROM rls_filtered rf, slot_count sc

  UNION ALL

  SELECT null, null, null, null, sc.cnt
  FROM slot_count sc
  WHERE NOT EXISTS (SELECT 1 FROM rls_filtered)
$$;


--
-- Name: quote_wal2json(regclass); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.quote_wal2json(entity regclass) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
  SELECT
    realtime.wal2json_escape_identifier(nsp.nspname::text)
    || '.'
    || realtime.wal2json_escape_identifier(pc.relname::text)
  FROM pg_class pc
  JOIN pg_namespace nsp ON pc.relnamespace = nsp.oid
  WHERE pc.oid = entity
$$;


--
-- Name: send(jsonb, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  generated_id uuid;
  final_payload jsonb;
BEGIN
  BEGIN
    generated_id := gen_random_uuid();

    -- Check if payload has an 'id' key, if not, add the generated UUID
    IF payload ? 'id' THEN
      final_payload := payload;
    ELSE
      final_payload := jsonb_set(payload, '{id}', to_jsonb(generated_id));
    END IF;

    -- Set the topic configuration
    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    INSERT INTO realtime.messages (id, payload, event, topic, private, extension)
    VALUES (generated_id, final_payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'WarnSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$$;


--
-- Name: send_binary(bytea, text, text, boolean); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.send_binary(payload bytea, event text, topic text, private boolean DEFAULT true) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
  generated_id uuid;
BEGIN
  BEGIN
    generated_id := gen_random_uuid();

    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    INSERT INTO realtime.messages (id, binary_payload, event, topic, private, extension)
    VALUES (generated_id, payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      RAISE WARNING 'WarnSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$$;


--
-- Name: subscription_check_filters(); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.subscription_check_filters() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare
    col_names text[] = coalesce(
            array_agg(a.attname order by a.attnum),
            '{}'::text[]
        )
        from
            pg_catalog.pg_attribute a
        where
            a.attrelid = new.entity
            and a.attnum > 0
            and not a.attisdropped
            and pg_catalog.has_column_privilege(
                (new.claims ->> 'role'),
                a.attrelid,
                a.attnum,
                'SELECT'
            );
    filter realtime.user_defined_filter;
    col_type regtype;
    in_val jsonb;
    selected_col text;
begin
    for filter in select * from unnest(new.filters) loop
        if not filter.column_name = any(col_names) then
            raise exception 'invalid column for filter %', filter.column_name;
        end if;

        col_type = (
            select atttypid::regtype
            from pg_catalog.pg_attribute
            where attrelid = new.entity
                  and attname = filter.column_name
        );
        if col_type is null then
            raise exception 'failed to lookup type for column %', filter.column_name;
        end if;

        if filter.op = 'in'::realtime.equality_op then
            in_val = realtime.cast(filter.value, (col_type::text || '[]')::regtype);
            if coalesce(jsonb_array_length(in_val), 0) > 100 then
                raise exception 'too many values for `in` filter. Maximum 100';
            end if;
        elsif filter.op = 'is'::realtime.equality_op then
            -- `is` requires a keyword RHS rather than a typed literal
            if filter.value not in ('null', 'true', 'false', 'unknown') then
                raise exception 'invalid value for is filter: must be null, true, false, or unknown';
            end if;
            -- IS NULL works for any type, but IS TRUE/FALSE/UNKNOWN require a boolean
            -- operand. Reject the non-null keywords on non-boolean columns here so they
            -- don't abort apply_rls at WAL time.
            if filter.value <> 'null' and col_type <> 'boolean'::regtype then
                raise exception 'is % filter requires a boolean column, got %', filter.value, col_type::text;
            end if;
        elsif filter.op in ('like'::realtime.equality_op, 'ilike'::realtime.equality_op) then
            -- like/ilike apply the text pattern operator (~~); reject column types that
            -- have no such operator instead of failing at WAL time
            if not exists (
                select 1 from pg_catalog.pg_operator
                where oprname = '~~' and oprleft = col_type
            ) then
                raise exception 'operator % requires a text-compatible column type, got %', filter.op::text, col_type::text;
            end if;
        elsif filter.op in ('match'::realtime.equality_op, 'imatch'::realtime.equality_op) then
            -- match/imatch apply the regex operators ~ / ~*; reject column types that have
            -- no such operator (e.g. integer) instead of failing at WAL time, mirroring the
            -- like/ilike guard above.
            if not exists (
                select 1 from pg_catalog.pg_operator
                where oprname = case when filter.op = 'imatch'::realtime.equality_op then '~*' else '~' end
                  and oprleft = col_type
                  and oprright = col_type
                  and oprresult = 'boolean'::regtype
            ) then
                raise exception 'operator % requires a text-compatible column type, got %', filter.op::text, col_type::text;
            end if;
            -- validate the regex eagerly so a bad pattern is rejected here, not inside
            -- apply_rls where it would abort the WAL stream for the entity
            begin
                perform '' ~ filter.value;
            exception when others then
                raise exception 'invalid regular expression for % filter: %', filter.op::text, sqlerrm;
            end;
        else
            -- eq/neq/lt/lte/gt/gte: value must be coercable to the type
            perform realtime.cast(filter.value, col_type);
        end if;
    end loop;

    if new.selected_columns is not null then
        for selected_col in select * from unnest(new.selected_columns) loop
            if not selected_col = any(col_names) then
                raise exception 'invalid column for select %', selected_col;
            end if;
        end loop;
    end if;

    -- Apply consistent order to filters so the unique constraint can't be tricked by a
    -- different filter order. negate is part of the sort key.
    new.filters = coalesce(
        array_agg(f order by f.column_name, f.op, f.value, f.negate),
        '{}'
    ) from unnest(new.filters) f;

    -- Normalize selected_columns order so ARRAY['a','b'] and ARRAY['b','a'] are treated
    -- as the same subscription group in apply_rls. Preserve an empty array as '{}'
    -- ("primary keys only") so it stays distinct from NULL ("all columns"); array_agg
    -- over an empty set would otherwise collapse '{}' back to NULL.
    if new.selected_columns is not null then
        new.selected_columns = coalesce(
            (
                select array_agg(c order by c)
                from unnest(new.selected_columns) c
            ),
            '{}'::text[]
        );
    end if;

    return new;
end;
$$;


--
-- Name: to_regrole(text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.to_regrole(role_name text) RETURNS regrole
    LANGUAGE sql IMMUTABLE
    AS $$ select role_name::regrole $$;


--
-- Name: topic(); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.topic() RETURNS text
    LANGUAGE sql STABLE
    AS $$
select nullif(current_setting('realtime.topic', true), '')::text;
$$;


--
-- Name: wal2json_escape_identifier(text); Type: FUNCTION; Schema: realtime; Owner: -
--

CREATE FUNCTION realtime.wal2json_escape_identifier(name text) RETURNS text
    LANGUAGE sql IMMUTABLE STRICT
    AS $$
  -- Prefix `\`, `,`, `.`, and any whitespace with `\`
  SELECT regexp_replace(name, '([\\,.[:space:]])', '\\\1', 'g')
$$;


--
-- Name: allow_any_operation(text[]); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.allow_any_operation(expected_operations text[]) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT CASE
      WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
      ELSE raw_operation
    END AS current_operation
    FROM current_operation
  )
  SELECT EXISTS (
    SELECT 1
    FROM normalized n
    CROSS JOIN LATERAL unnest(expected_operations) AS expected_operation
    WHERE expected_operation IS NOT NULL
      AND expected_operation <> ''
      AND n.current_operation = CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END
  );
$$;


--
-- Name: allow_only_operation(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.allow_only_operation(expected_operation text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT
      CASE
        WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
        ELSE raw_operation
      END AS current_operation,
      CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END AS requested_operation
    FROM current_operation
  )
  SELECT CASE
    WHEN requested_operation IS NULL OR requested_operation = '' THEN FALSE
    ELSE COALESCE(current_operation = requested_operation, FALSE)
  END
  FROM normalized;
$$;


--
-- Name: can_insert_object(text, text, uuid, jsonb); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


--
-- Name: enforce_bucket_lifecycle_service_role(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.enforce_bucket_lifecycle_service_role() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
BEGIN
  IF current_user::text IS DISTINCT FROM TG_ARGV[0]
     AND (
       OLD.lifecycle_configuration IS DISTINCT FROM NEW.lifecycle_configuration
       OR OLD.lifecycle_configuration_generation IS DISTINCT FROM NEW.lifecycle_configuration_generation
     ) THEN
    -- AFTER runs only after caller RLS has accepted the proposed row. The API
    -- recognizes this specific error after rolling back its permission probe;
    -- direct non-service writes still fail and cannot persist the change.
    RAISE EXCEPTION 'bucket control columns may only be changed by the configured storage service role'
      USING ERRCODE = 'PST01',
            SCHEMA = TG_TABLE_SCHEMA,
            TABLE = TG_TABLE_NAME,
            CONSTRAINT = TG_NAME;
  END IF;

  RETURN NULL;
END;
$$;


--
-- Name: enforce_bucket_name_length(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.enforce_bucket_name_length() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


--
-- Name: extension(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.extension(name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Get the last path segment (the actual filename)
    SELECT _parts[array_length(_parts, 1)] INTO _filename;
    -- Extract extension: reverse, split on '.', then reverse again
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


--
-- Name: filename(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.filename(name text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    RETURN _parts[array_length(_parts, 1)];
END
$$;


--
-- Name: foldername(text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.foldername(name text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


--
-- Name: get_common_prefix(text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_common_prefix(p_key text, p_prefix text, p_delimiter text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $$
SELECT CASE
    WHEN p_delimiter <> ''
         AND position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(
        p_key,
        length(p_prefix)
            + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1))
            + length(p_delimiter) - 1
    )
    ELSE NULL
END;
$$;


--
-- Name: get_size_by_bucket(text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_size_by_bucket(noncurrent_versions text DEFAULT 'include'::text, delete_markers text DEFAULT 'include'::text) RETURNS TABLE(size bigint, bucket_id text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'include');
    delete_markers := COALESCE(delete_markers, 'include');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'include';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'include';
    END IF;

    return query
        select sum((metadata->>'size')::bigint)::bigint as size, obj.bucket_id
        from "storage".objects as obj
        where (noncurrent_versions != 'exclude' OR obj.archived_at IS NULL)
          and (noncurrent_versions != 'only' OR obj.archived_at IS NOT NULL)
          and (delete_markers != 'exclude' OR NOT obj.is_delete_marker)
          and (delete_markers != 'only' OR obj.is_delete_marker)
        group by obj.bucket_id;
END
$$;


--
-- Name: list_multipart_uploads_with_delimiter(text, text, text, integer, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, next_key_token text DEFAULT ''::text, next_upload_token text DEFAULT ''::text, raw_prefix_param text DEFAULT NULL::text) RETURNS TABLE(key text, id text, created_at timestamp with time zone)
    LANGUAGE sql STABLE
    AS $_$
WITH candidates AS (
    SELECT
        upload.key AS object_key,
        CASE
            WHEN position($3 IN substring(upload.key FROM length(coalesce($7, $2)) + 1)) > 0
            THEN left(
                upload.key,
                length(coalesce($7, $2))
                    + position($3 IN substring(upload.key FROM length(coalesce($7, $2)) + 1))
                    + length($3) - 1
            )
            ELSE upload.key
        END AS result_key,
        upload.id,
        upload.created_at,
        position($3 IN substring(upload.key FROM length(coalesce($7, $2)) + 1)) > 0 AS is_common_prefix
    FROM storage.s3_multipart_uploads AS upload
    WHERE upload.bucket_id = $1
      AND upload.key COLLATE "C" LIKE $2 || '%'
), filtered AS (
    SELECT candidate.*
    FROM candidates AS candidate
    WHERE $5 = ''
       OR candidate.result_key COLLATE "C" > $5
       OR (
           candidate.result_key COLLATE "C" = $5
           AND NOT candidate.is_common_prefix
           AND $6 <> ''
           -- A completed or aborted marker repeats the remaining same-key uploads.
           AND COALESCE(
               (candidate.created_at, candidate.id COLLATE "C") > (
                   SELECT marker.created_at, marker.id COLLATE "C"
                   FROM storage.s3_multipart_uploads AS marker
                   WHERE marker.bucket_id = $1
                     AND marker.key COLLATE "C" = $5
                     AND marker.id = $6
               ),
               TRUE
           )
       )
), ranked AS (
    SELECT
        filtered.*,
        row_number() OVER (
            PARTITION BY filtered.result_key COLLATE "C"
            ORDER BY filtered.created_at, filtered.id COLLATE "C"
        ) AS prefix_rank
    FROM filtered
)
SELECT ranked.result_key, ranked.id, ranked.created_at
FROM ranked
WHERE NOT ranked.is_common_prefix OR ranked.prefix_rank = 1
ORDER BY ranked.result_key COLLATE "C", ranked.created_at, ranked.id COLLATE "C"
LIMIT $4;
$_$;


--
-- Name: list_objects_with_delimiter(text, text, text, integer, text, text, text, text, text, timestamp with time zone, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.list_objects_with_delimiter(_bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, start_after text DEFAULT ''::text, next_token text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text, noncurrent_versions text DEFAULT 'exclude'::text, delete_markers text DEFAULT 'exclude'::text, next_token_archived_at timestamp with time zone DEFAULT NULL::timestamp with time zone, next_token_version text DEFAULT ''::text) RETURNS TABLE(name text, id uuid, metadata jsonb, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, version text, archived_at timestamp with time zone, is_delete_marker boolean, is_versioned boolean)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_start_relative TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;
    v_version_filter TEXT;

    -- true when noncurrent_versions can return >1 row per name; keeps them
    -- ordered most-recent-first and lets pagination resume mid-key
    v_multi_row BOOLEAN;
    v_name_order TEXT;
    v_exact_range_predicate TEXT;
    v_strict_range_predicate TEXT;
    v_inclusive_range_predicate TEXT;

    -- Seek state for the current name. archived_at is normalized to JavaScript's
    -- millisecond precision and version breaks ties within the same millisecond.
    -- Current rows use 'infinity'; NULL means no tiebreak has been established.
    v_next_seek TEXT;
    v_next_seek_at TIMESTAMPTZ;
    v_next_seek_version TEXT;
    v_next_seek_strict BOOLEAN := false;
    v_cursor_is_folder BOOLEAN;
    v_count INT := 0;
    v_previous_seek TEXT;
    v_previous_seek_at TIMESTAMPTZ;
    v_previous_seek_version TEXT;
    v_previous_count INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;
    v_batch_query_strict TEXT;
    v_delete_marker_peek_query TEXT;
    v_delete_marker_peek_query_strict TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);
    v_next_seek_at := NULL;
    v_next_seek_version := '';

    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'exclude');
    delete_markers := COALESCE(delete_markers, 'exclude');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'exclude';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'exclude';
    END IF;

    v_multi_row := noncurrent_versions IN ('only', 'include');
    v_name_order := CASE WHEN v_is_asc THEN 'ASC' ELSE 'DESC' END;

    v_version_filter := '';
    IF noncurrent_versions = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NULL';
    ELSIF noncurrent_versions = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NOT NULL';
    END IF;
    IF delete_markers = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND NOT o.is_delete_marker';
    ELSIF delete_markers = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.is_delete_marker';
    END IF;

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Keep caller-provided cursors inside the requested prefix range.
    IF v_start <> '' AND v_upper_bound IS NOT NULL THEN
        IF v_is_asc THEN
            IF v_start COLLATE "C" < v_prefix COLLATE "C" THEN
                v_start := '';
            ELSIF v_start COLLATE "C" >= v_upper_bound COLLATE "C" THEN
                RETURN;
            END IF;
        ELSE
            IF v_start COLLATE "C" < v_prefix COLLATE "C" THEN
                RETURN;
            ELSIF v_start COLLATE "C" >= v_upper_bound COLLATE "C" THEN
                v_start := '';
            END IF;
        END IF;
    END IF;

    v_start_relative := substring(v_start FROM length(v_prefix) + 1);

    -- Direction affects only the indexed name range and its ordering. Cursor
    -- state transitions and within-key version ordering stay shared.
    IF v_is_asc THEN
        v_exact_range_predicate := 'TRUE';
        v_strict_range_predicate := 'o.name COLLATE "C" > $2';
        v_inclusive_range_predicate := 'o.name COLLATE "C" >= $2';
        IF v_upper_bound IS NOT NULL THEN
            v_exact_range_predicate := 'o.name COLLATE "C" < $3';
            v_strict_range_predicate := v_strict_range_predicate || ' AND o.name COLLATE "C" < $3';
            v_inclusive_range_predicate := v_inclusive_range_predicate || ' AND o.name COLLATE "C" < $3';
        END IF;
    ELSE
        v_exact_range_predicate := 'TRUE';
        v_strict_range_predicate := 'o.name COLLATE "C" < $2';
        v_inclusive_range_predicate := 'o.name COLLATE "C" < $2';
        IF v_prefix <> '' THEN
            v_exact_range_predicate := 'o.name COLLATE "C" >= $3';
            v_strict_range_predicate := v_strict_range_predicate || ' AND o.name COLLATE "C" >= $3';
            v_inclusive_range_predicate := v_inclusive_range_predicate || ' AND o.name COLLATE "C" >= $3';
        END IF;
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    -- The multi-row order matches the externally serialized cursor exactly:
    -- archived_at at millisecond precision, then version as the final tiebreak.
    --
    -- When v_multi_row, the seek is a keyset tuple comparison ("name > $2 OR
    -- (name = $2 AND tiebreak)") - Postgres won't split that OR into indexable
    -- form (confirmed even with fully literal values), so as one WHERE clause
    -- it forces a full bucket scan filtered row-by-row. Splitting it into two
    -- independently-indexable branches (exact name match with the tiebreak
    -- filter, vs. strictly-past names) combined with UNION ALL lets each
    -- branch keep name as a real index condition; the outer ORDER BY/LIMIT
    -- re-merges them into the same page the single query used to produce.
    IF v_multi_row THEN
        v_batch_query := format(
            $sql$
            SELECT *
            FROM (
                (
                    SELECT o.name, o.id, o.updated_at, o.created_at,
                           o.last_accessed_at, o.metadata, o.version,
                           o.archived_at, o.is_delete_marker, o.is_versioned
                    FROM storage.objects o
                    WHERE o.bucket_id = $1
                      AND o.name COLLATE "C" = $2
                      AND %s
                      AND NOT $7::boolean
                      AND (
                          $5::timestamptz IS NULL
                          OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < $5
                          OR (
                              COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = $5
                              AND COALESCE(o.version, '') > $6
                          )
                      )
                      %s
                    ORDER BY
                        COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC,
                        COALESCE(o.version, '') ASC
                    LIMIT $4
                )
                UNION ALL
                (
                    SELECT o.name, o.id, o.updated_at, o.created_at,
                           o.last_accessed_at, o.metadata, o.version,
                           o.archived_at, o.is_delete_marker, o.is_versioned
                    FROM storage.objects o
                    WHERE o.bucket_id = $1
                      AND %s
                      %s
                    ORDER BY
                        o.name COLLATE "C" %s,
                        COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC,
                        COALESCE(o.version, '') ASC
                    LIMIT $4
                )
            ) sub
            ORDER BY
                sub.name COLLATE "C" %s,
                COALESCE(date_trunc('milliseconds', sub.archived_at), 'infinity'::timestamptz) DESC,
                COALESCE(sub.version, '') ASC
            LIMIT $4
            $sql$,
            v_exact_range_predicate,
            v_version_filter,
            v_strict_range_predicate,
            v_version_filter,
            v_name_order,
            v_name_order
        );
    ELSE
        v_batch_query := format(
            $sql$
            SELECT o.name, o.id, o.updated_at, o.created_at,
                   o.last_accessed_at, o.metadata, o.version,
                   o.archived_at, o.is_delete_marker, o.is_versioned
            FROM storage.objects o
            WHERE o.bucket_id = $1
              AND %s
              %s
            ORDER BY o.name COLLATE "C" %s, o.archived_at DESC
            LIMIT $4
            $sql$,
            v_inclusive_range_predicate,
            v_version_filter,
            v_name_order
        );

        -- Strict counterpart of the query above: used once the single-row
        -- ASC batch advance (below) has left v_next_seek pointing at the
        -- last row already emitted, so an inclusive predicate would
        -- re-match it forever. Only single-row mode ever sets strict mode,
        -- so this variant is never needed when v_multi_row.
        v_batch_query_strict := format(
            $sql$
            SELECT o.name, o.id, o.updated_at, o.created_at,
                   o.last_accessed_at, o.metadata, o.version,
                   o.archived_at, o.is_delete_marker, o.is_versioned
            FROM storage.objects o
            WHERE o.bucket_id = $1
              AND %s
              %s
            ORDER BY o.name COLLATE "C" %s, o.archived_at DESC
            LIMIT $4
            $sql$,
            v_strict_range_predicate,
            v_version_filter,
            v_name_order
        );
    END IF;

    -- The static peek predicates cannot use the partial delete-marker index
    -- once PL/pgSQL switches to a generic plan because whether
    -- is_delete_marker is required remains parameter-dependent. Reuse the
    -- already-specialized batch query with a one-row limit for this sparse
    -- filter so the plan sees a literal `o.is_delete_marker` predicate.
    IF delete_markers = 'only' THEN
        v_delete_marker_peek_query :=
            'SELECT marker_page.name FROM (' || v_batch_query || ') marker_page LIMIT 1';
        IF NOT v_multi_row THEN
            v_delete_marker_peek_query_strict :=
                'SELECT marker_page.name FROM (' || v_batch_query_strict || ') marker_page LIMIT 1';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor performs one specialized initial seek so
            -- partial current-version and delete-marker indexes remain available.
            EXECUTE format(
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1%s%s ORDER BY o.name COLLATE "C" DESC LIMIT 1',
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND o.name COLLATE "C" >= $2 AND o.name COLLATE "C" < $3'
                    ELSE ''
                END,
                v_version_filter
            )
            INTO v_next_seek
            USING _bucket_id, v_prefix, v_upper_bound;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Folder continuation tokens retain their trailing delimiter. A
        -- delimiter-less startAfter is always a literal key boundary.
        v_cursor_is_folder := delimiter_param <> ''
            AND v_start_relative <> ''
            AND right(v_start_relative, length(delimiter_param)) = delimiter_param;

        IF v_cursor_is_folder THEN
            v_next_seek := CASE
                WHEN right(v_start, length(delimiter_param)) = delimiter_param
                    THEN v_start
                ELSE v_start || delimiter_param
            END;
            IF v_is_asc THEN
                v_next_seek := left(v_next_seek, -1)
                    || chr(ascii(right(v_next_seek, 1)) + 1);
            END IF;
            v_next_seek_strict := NOT v_is_asc;
        ELSE
            -- leaf object: when v_multi_row, stay on v_start with the
            -- caller-supplied tiebreak so a page boundary mid-key resumes
            -- that key's remaining rows instead of skipping them. Truncate
            -- to milliseconds like every other v_next_seek_at assignment -
            -- harmless today since object.ts's cursor always round-trips
            -- through JS Date first, but this shouldn't rely on that.
            IF v_multi_row THEN
                v_next_seek := v_start;
                v_next_seek_at := date_trunc('milliseconds', next_token_archived_at);
                v_next_seek_version := coalesce(next_token_version, '');
                v_next_seek_strict := coalesce(next_token, '') = '';
            ELSIF v_is_asc THEN
                v_next_seek := v_start;
                v_next_seek_strict := true;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        v_previous_seek := v_next_seek;
        v_previous_seek_at := v_next_seek_at;
        v_previous_seek_version := v_next_seek_version;
        v_previous_count := v_count;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        -- v_multi_row is branched here (rather than folded into the WHERE
        -- clause as a bound parameter) so each concrete query keeps an
        -- unconditional seek predicate - once PL/pgSQL switches to its
        -- cached generic plan (after 5 calls), a parameter-gated
        -- "(NOT v_multi_row AND name >= $x) OR (v_multi_row AND ...)"
        -- predicate stops the planner from using name as an index
        -- condition at all, degrading every subsequent peek to a full
        -- index scan filtered row-by-row instead of a bounded range scan.
        -- v_multi_row's seek predicate is a keyset tuple comparison
        -- ("name > x OR (name = x AND tiebreak)") - Postgres does not
        -- split this OR into indexable form even with fully literal
        -- values, so it falls back to a full scan filtered row-by-row.
        -- Splitting it into two independently-indexable branches (exact
        -- name match with the tiebreak filter, vs. strictly-past name)
        -- combined with UNION ALL lets each branch keep name as a real
        -- index condition; the outer ORDER BY/LIMIT picks whichever of
        -- the (at most 2) rows sorts first.
        IF delete_markers = 'only' THEN
            EXECUTE CASE WHEN v_next_seek_strict AND NOT v_multi_row
                THEN v_delete_marker_peek_query_strict
                ELSE v_delete_marker_peek_query
            END
                INTO v_peek_name
                USING _bucket_id, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END,
                    1, v_next_seek_at, v_next_seek_version, v_next_seek_strict;
        ELSIF v_multi_row THEN
            IF v_is_asc THEN
                IF v_upper_bound IS NOT NULL THEN
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND o.name COLLATE "C" < v_upper_bound
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" > v_next_seek AND o.name COLLATE "C" < v_upper_bound
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" ASC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" ASC LIMIT 1;
                ELSE
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" > v_next_seek
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" ASC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" ASC LIMIT 1;
                END IF;
            ELSE
                IF v_upper_bound IS NOT NULL THEN
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND o.name COLLATE "C" >= v_prefix
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" DESC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" DESC LIMIT 1;
                ELSE
                    SELECT sub.name INTO v_peek_name FROM (
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" = v_next_seek
                           AND NOT v_next_seek_strict
                           AND (v_next_seek_at IS NULL
                                OR COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) < v_next_seek_at
                                OR (COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) = v_next_seek_at
                                    AND COALESCE(o.version, '') > v_next_seek_version))
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY COALESCE(date_trunc('milliseconds', o.archived_at), 'infinity'::timestamptz) DESC, COALESCE(o.version, '') ASC LIMIT 1)
                        UNION ALL
                        (SELECT o.name FROM storage.objects o
                         WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                           AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                           AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                           AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                           AND (delete_markers != 'only' OR o.is_delete_marker)
                         ORDER BY o.name COLLATE "C" DESC LIMIT 1)
                    ) sub ORDER BY sub.name COLLATE "C" DESC LIMIT 1;
                END IF;
            END IF;
        ELSE
            -- Single-row mode is always noncurrent_versions='exclude'. Keep
            -- this predicate literal so generic plans use the current index.
            IF v_is_asc THEN
                IF v_next_seek_strict AND v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" > v_next_seek
                      AND o.name COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                ELSIF v_next_seek_strict THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" > v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                ELSIF v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" >= v_next_seek
                      AND o.name COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                ELSE
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" >= v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" ASC LIMIT 1;
                END IF;
            ELSE
                IF v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" < v_next_seek
                      AND o.name COLLATE "C" >= v_prefix
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" DESC LIMIT 1;
                ELSE
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = _bucket_id
                      AND o.name COLLATE "C" < v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                      AND (delete_markers != 'only' OR o.is_delete_marker)
                    ORDER BY o.name COLLATE "C" DESC LIMIT 1;
                END IF;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := v_common_prefix;
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            version := NULL;
            archived_at := NULL;
            is_delete_marker := NULL;
            is_versioned := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1)
                    || chr(ascii(right(v_common_prefix, 1)) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
            v_next_seek_at := NULL;
            v_next_seek_version := '';
            v_next_seek_strict := NOT v_is_asc;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE CASE WHEN v_next_seek_strict AND NOT v_multi_row THEN v_batch_query_strict ELSE v_batch_query END
                USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size, v_next_seek_at, v_next_seek_version,
                v_next_seek_strict
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it. Reset
                    -- strict mode too it may have been set by an earlier
                    -- row in this same batch (see the single-row ASC advance
                    -- below), and v_next_seek here is the folder-triggering
                    -- row's own name, which the next peek must find inclusively.
                    v_next_seek := CASE
                        WHEN v_is_asc THEN v_current.name
                        ELSE v_current.name || delimiter_param
                    END;
                    v_next_seek_at := NULL;
                    v_next_seek_version := '';
                    v_next_seek_strict := false;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                version := v_current.version;
                archived_at := v_current.archived_at;
                is_delete_marker := v_current.is_delete_marker;
                is_versioned := v_current.is_versioned;
                RETURN NEXT;
                v_count := v_count + 1;

                -- when v_multi_row, stay on this name and record its
                -- archived_at as the new tiebreak so remaining rows for the
                -- same key are picked up before moving to the next name
                IF v_multi_row THEN
                    v_next_seek := v_current.name;
                    v_next_seek_at := COALESCE(date_trunc('milliseconds', v_current.archived_at), 'infinity'::timestamptz);
                    v_next_seek_version := COALESCE(v_current.version, '');
                    v_next_seek_strict := false;
                ELSIF v_is_asc THEN
                    -- Appending the delimiter as a fake lexical successor
                    -- would skip a real key like `name || '!'` (or any
                    -- character sorting below the delimiter), which sorts
                    -- between `name` and `name || delimiter`. Track the real
                    -- name and mark the next comparison strict instead.
                    v_next_seek := v_current.name;
                    v_next_seek_strict := true;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;

        IF v_count = v_previous_count
           AND v_next_seek IS NOT DISTINCT FROM v_previous_seek
           AND v_next_seek_at IS NOT DISTINCT FROM v_previous_seek_at
           AND v_next_seek_version IS NOT DISTINCT FROM v_previous_seek_version THEN
            RAISE EXCEPTION 'storage.list_objects_with_delimiter made no progress at seek (%, %, %)',
                v_next_seek, v_next_seek_at, v_next_seek_version;
        END IF;
    END LOOP;
END;
$_$;


--
-- Name: operation(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.operation() RETURNS text
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


--
-- Name: protect_bucket_control_columns(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.protect_bucket_control_columns() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  configuration_changed boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.lifecycle_configuration IS NOT NULL
       OR NEW.lifecycle_configuration_generation IS NOT NULL THEN
      IF NOT pg_has_role(current_user, TG_ARGV[0], 'MEMBER') THEN
        RAISE EXCEPTION 'only members of the configured storage service role may insert lifecycle policy state'
          USING ERRCODE = '42501',
                HINT = format(
                  'Insert with both lifecycle columns NULL and configure lifecycle through the Storage API afterward, or insert as a member of %I.',
                  TG_ARGV[0]
                );
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  configuration_changed =
    OLD.lifecycle_configuration IS DISTINCT FROM NEW.lifecycle_configuration
    OR OLD.lifecycle_configuration_generation IS DISTINCT FROM NEW.lifecycle_configuration_generation;

  IF NOT configuration_changed THEN
    RETURN NEW;
  END IF;

  IF NEW.type IS DISTINCT FROM 'STANDARD' THEN
    RAISE EXCEPTION 'bucket versioning and lifecycle controls require a Standard bucket'
      USING ERRCODE = '0A000';
  END IF;

  IF NEW.lifecycle_configuration IS NULL
     AND NEW.lifecycle_configuration_generation IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.lifecycle_configuration IS NULL
     OR NEW.lifecycle_configuration_generation IS NULL
     OR OLD.lifecycle_configuration IS NOT DISTINCT FROM NEW.lifecycle_configuration
     OR OLD.lifecycle_configuration_generation IS NOT DISTINCT FROM NEW.lifecycle_configuration_generation THEN
    RAISE EXCEPTION 'a changed lifecycle policy requires a new non-null generation'
      USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$$;


--
-- Name: protect_delete(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.protect_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


--
-- Name: search(text, text, integer, integer, integer, text, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text, noncurrent_versions text DEFAULT 'exclude'::text, delete_markers text DEFAULT 'exclude'::text) RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb, version text, archived_at timestamp with time zone, is_delete_marker boolean, is_versioned boolean)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_prefix_len INT;
    v_prefix_start INT;
    v_combined_levels INT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;
    v_version_filter TEXT;
    v_multi_row BOOLEAN;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;
    v_delete_marker_peek_query TEXT;
    v_delete_marker_peek_query_strict TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_next_seek_at TIMESTAMPTZ;
    v_next_seek_version TEXT;
    v_next_seek_strict BOOLEAN := false;
    v_count INT := 0;
    v_skipped INT := 0;
    v_previous_seek TEXT;
    v_previous_seek_at TIMESTAMPTZ;
    v_previous_seek_version TEXT;
    v_previous_count INT;
    v_previous_skipped INT;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_prefix_len := length(coalesce(prefix, ''));
    v_prefix_start := coalesce(array_length(string_to_array(coalesce(prefix, ''), v_delimiter), 1), 1);
    v_combined_levels := coalesce(array_length(string_to_array(v_prefix, v_delimiter), 1), 1);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);
    v_next_seek_at := NULL;
    v_next_seek_version := '';

    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'exclude');
    delete_markers := COALESCE(delete_markers, 'exclude');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'exclude';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'exclude';
    END IF;

    v_multi_row := noncurrent_versions IN ('only', 'include');

    v_version_filter := '';
    IF noncurrent_versions = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NULL';
    ELSIF noncurrent_versions = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.archived_at IS NOT NULL';
    END IF;
    IF delete_markers = 'exclude' THEN
        v_version_filter := v_version_filter || ' AND NOT o.is_delete_marker';
    ELSIF delete_markers = 'only' THEN
        v_version_filter := v_version_filter || ' AND o.is_delete_marker';
    END IF;

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT array_to_string(path_tokens[$1:$2], '/') AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $3 || '%%'
                  AND bucket_id = $4
                  AND array_length(objects.path_tokens, 1) <> $2
                  AND ($7 != 'exclude' OR objects.archived_at IS NULL)
                  AND ($7 != 'only' OR objects.archived_at IS NOT NULL)
                  AND ($8 != 'exclude' OR NOT objects.is_delete_marker)
                  AND ($8 != 'only' OR objects.is_delete_marker)
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata,
                   NULL::text AS version,
                   NULL::timestamptz AS archived_at,
                   NULL::boolean AS is_delete_marker,
                   NULL::boolean AS is_versioned FROM folders)
            UNION ALL
            (SELECT array_to_string(path_tokens[$1:$2], '/') AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata,
                   version, archived_at, is_delete_marker, is_versioned
             FROM storage.objects
             WHERE objects.name ILIKE $3 || '%%'
               AND bucket_id = $4
               AND array_length(objects.path_tokens, 1) = $2
               AND ($7 != 'exclude' OR objects.archived_at IS NULL)
               AND ($7 != 'only' OR objects.archived_at IS NOT NULL)
               AND ($8 != 'exclude' OR NOT objects.is_delete_marker)
               AND ($8 != 'only' OR objects.is_delete_marker)
             -- name, then version, as tiebreaks so two versions of the same
             -- key tying on the sort column still sort deterministically
             ORDER BY %I %s, name COLLATE "C" %s, COALESCE(version, '') %s)
            LIMIT $5 OFFSET $6
            $sql$, v_sort_order, v_order_by, v_sort_order, v_sort_order, v_sort_order
        ) USING v_prefix_start, v_combined_levels, v_prefix, bucketname, v_limit, offsets, noncurrent_versions, delete_markers;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build a resume-safe batch query. The exact-name branch returns remaining
    -- versions after the current (archived_at, version) boundary; the strict
    -- name branch returns subsequent keys. UNION ALL keeps both predicates
    -- independently indexable.
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" > $2 AND lower(o.name) COLLATE "C" < $3' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" ASC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" > $2' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" ASC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 AND lower(o.name) COLLATE "C" >= $3' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" DESC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" DESC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT * FROM (' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" = $2 AND ($5::timestamptz IS NULL OR COALESCE(o.archived_at, ''infinity''::timestamptz) < $5 OR (COALESCE(o.archived_at, ''infinity''::timestamptz) = $5 AND COALESCE(o.version, '''') > $6))' ||
                v_version_filter || ' ORDER BY COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4) UNION ALL ' ||
                '(SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata, o.version, o.archived_at, o.is_delete_marker, o.is_versioned FROM storage.objects o ' ||
                'WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2' || v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" DESC, COALESCE(o.archived_at, ''infinity''::timestamptz) DESC, COALESCE(o.version, '''') ASC LIMIT $4)' ||
                ') sub ORDER BY lower(sub.name) COLLATE "C" DESC, COALESCE(sub.archived_at, ''infinity''::timestamptz) DESC, COALESCE(sub.version, '''') ASC LIMIT $4';
        END IF;
    END IF;

    -- Keep the delete-marker predicate literal so the cached generic
    -- plan can use idx_objects_delete_markers during the main-loop peek.
    IF delete_markers = 'only' THEN
        IF v_multi_row THEN
            v_delete_marker_peek_query :=
                'SELECT marker_page.name FROM (' || v_batch_query || ') marker_page LIMIT 1';
        ELSIF v_is_asc THEN
            -- Two separate literal query strings, not one gated by a bound
            -- boolean: folding "$n AND op1 OR NOT $n AND op2" into a single
            -- query defeats the generic plan's ability to push either
            -- comparison into the index. Branching in PL/pgSQL control flow
            -- instead keeps each query's index condition intact.
            v_delete_marker_peek_query :=
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1 ' ||
                'AND lower(o.name) COLLATE "C" >= $2' ||
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND lower(o.name) COLLATE "C" < $3'
                    ELSE ''
                END ||
                v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1';
            -- Strict variant: used once the single-row ASC batch advance
            -- (below) has left v_next_seek pointing at the last row already
            -- emitted, so a plain >= would re-match it forever.
            v_delete_marker_peek_query_strict :=
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1 ' ||
                'AND lower(o.name) COLLATE "C" > $2' ||
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND lower(o.name) COLLATE "C" < $3'
                    ELSE ''
                END ||
                v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1';
        ELSE
            v_delete_marker_peek_query :=
                'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1 ' ||
                'AND lower(o.name) COLLATE "C" < $2' ||
                CASE WHEN v_upper_bound IS NOT NULL
                    THEN ' AND lower(o.name) COLLATE "C" >= $3'
                    ELSE ''
                END ||
                v_version_filter ||
                ' ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC performs one specialized initial seek so partial current-version
        -- and delete-marker indexes remain available.
        EXECUTE format(
            'SELECT o.name FROM storage.objects o WHERE o.bucket_id = $1%s%s ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1',
            CASE WHEN v_upper_bound IS NOT NULL
                THEN ' AND lower(o.name) COLLATE "C" >= $2 AND lower(o.name) COLLATE "C" < $3'
                ELSE ''
            END,
            v_version_filter
        )
        INTO v_peek_name
        USING bucketname, v_prefix_lower, v_upper_bound;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch and
    -- the delete-marker-only path
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        v_previous_seek := v_next_seek;
        v_previous_seek_at := v_next_seek_at;
        v_previous_seek_version := v_next_seek_version;
        v_previous_count := v_count;
        v_previous_skipped := v_skipped;

        -- STEP 1: PEEK
        v_peek_name := NULL;
        IF delete_markers = 'only' THEN
            EXECUTE CASE WHEN v_next_seek_strict
                THEN v_delete_marker_peek_query_strict
                ELSE v_delete_marker_peek_query
            END
                INTO v_peek_name
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END,
                    1, v_next_seek_at, v_next_seek_version;
        ELSIF v_multi_row AND v_next_seek_at IS NOT NULL THEN
            SELECT o.name INTO v_peek_name
            FROM storage.objects o
            WHERE o.bucket_id = bucketname
              AND lower(o.name) COLLATE "C" = v_next_seek
              AND (COALESCE(o.archived_at, 'infinity'::timestamptz) < v_next_seek_at
                   OR (COALESCE(o.archived_at, 'infinity'::timestamptz) = v_next_seek_at
                       AND COALESCE(o.version, '') > v_next_seek_version))
              AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
              AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
              AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
              AND (delete_markers != 'only' OR o.is_delete_marker)
            ORDER BY COALESCE(o.archived_at, 'infinity'::timestamptz) DESC,
                     COALESCE(o.version, '') ASC
            LIMIT 1;

            -- The current key is exhausted. Clear its version boundary and
            -- make the following ASC name peek strict. Appending '/' is not a
            -- valid lexical successor because keys ending in characters such
            -- as '!' sort between the exhausted name and name || '/'.
            IF v_peek_name IS NULL THEN
                IF v_is_asc THEN
                    v_next_seek_strict := true;
                END IF;
                v_next_seek_at := NULL;
                v_next_seek_version := '';
            END IF;
        END IF;

        -- Single-row mode is always noncurrent_versions='exclude'. Keep the
        -- current-row predicate literal so generic plans use the current index.
        IF delete_markers != 'only' AND v_peek_name IS NULL AND NOT v_multi_row THEN
            IF v_is_asc THEN
                IF v_next_seek_strict AND v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                ELSIF v_next_seek_strict THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                ELSIF v_upper_bound IS NOT NULL THEN
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                ELSE
                    SELECT o.name INTO v_peek_name FROM storage.objects o
                    WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                      AND o.archived_at IS NULL
                      AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                    ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
                END IF;
            ELSIF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                  AND o.archived_at IS NULL
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                  AND o.archived_at IS NULL
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        ELSIF delete_markers != 'only' AND v_peek_name IS NULL AND v_is_asc THEN
            IF v_next_seek_strict AND v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSIF v_next_seek_strict THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" > v_next_seek
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSIF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSIF delete_markers != 'only' AND v_peek_name IS NULL THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                  AND (noncurrent_versions != 'exclude' OR o.archived_at IS NULL)
                  AND (noncurrent_versions != 'only' OR o.archived_at IS NOT NULL)
                  AND (delete_markers != 'exclude' OR NOT o.is_delete_marker)
                  AND (delete_markers != 'only' OR o.is_delete_marker)
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- If the peek landed on a different key than we were tracking, any
        -- version boundary belongs to the OLD key and must not leak into the
        -- new one - e.g. the deleteMarkers='only' peek doesn't know or care
        -- whether it's continuing the same key or jumping to a new one, so
        -- it never clears these itself.
        IF lower(v_peek_name) IS DISTINCT FROM v_next_seek THEN
            v_next_seek_at := NULL;
            v_next_seek_version := '';
        END IF;

        -- The peek is authoritative for the next key to process. This is
        -- especially important after exhausting a multi-version key: the
        -- version boundary has been cleared, so executing the batch against
        -- a stale v_next_seek would replay every version of that old key.
        v_next_seek := lower(v_peek_name);
        v_next_seek_strict := false;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := substring(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter) from v_prefix_len + 1);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                version := NULL;
                archived_at := NULL;
                is_delete_marker := NULL;
                is_versioned := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
            v_next_seek_at := NULL;
            v_next_seek_version := '';
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size,
                    v_next_seek_at, v_next_seek_version
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it. Reset
                    -- strict mode too - it may have been set by an earlier
                    -- row in this same batch (see the single-row ASC advance
                    -- below), and v_next_seek here is the folder-triggering
                    -- row's own name, which the next peek must find inclusively.
                    v_next_seek := CASE
                        WHEN v_is_asc THEN lower(v_current.name)
                        ELSE lower(v_current.name) || v_delimiter
                    END;
                    v_next_seek_at := NULL;
                    v_next_seek_version := '';
                    v_next_seek_strict := false;
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := substring(v_current.name from v_prefix_len + 1);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    version := v_current.version;
                    archived_at := v_current.archived_at;
                    is_delete_marker := v_current.is_delete_marker;
                    is_versioned := v_current.is_versioned;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Multi-row mode must remain on this key until all of its
                -- versions have crossed the internal batch boundary.
                IF v_multi_row THEN
                    v_next_seek := lower(v_current.name);
                    v_next_seek_at := COALESCE(v_current.archived_at, 'infinity'::timestamptz);
                    v_next_seek_version := COALESCE(v_current.version, '');
                ELSIF v_is_asc THEN
                    -- Appending the delimiter as a fake lexical successor would
                    -- skip a real key like `name || '!'` (or any character
                    -- sorting below the delimiter), which sorts between `name`
                    -- and `name || delimiter`. Track the real name and mark the
                    -- next comparison strict instead - same fix as the
                    -- exhausted-key case above.
                    v_next_seek := lower(v_current.name);
                    v_next_seek_strict := true;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;

        IF v_count = v_previous_count
           AND v_skipped = v_previous_skipped
           AND v_next_seek IS NOT DISTINCT FROM v_previous_seek
           AND v_next_seek_at IS NOT DISTINCT FROM v_previous_seek_at
           AND v_next_seek_version IS NOT DISTINCT FROM v_previous_seek_version THEN
            RAISE EXCEPTION 'storage.search made no progress at seek (%, %, %)',
                v_next_seek, v_next_seek_at, v_next_seek_version;
        END IF;
    END LOOP;
END;
$_$;


--
-- Name: search_by_timestamp(text, text, integer, integer, text, text, text, text, text, text, text); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_by_timestamp(p_prefix text, p_bucket_id text, p_limit integer, p_level integer, p_start_after text, p_sort_order text, p_sort_column text, p_sort_column_after text, noncurrent_versions text DEFAULT 'exclude'::text, delete_markers text DEFAULT 'exclude'::text, p_start_after_version text DEFAULT ''::text) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb, version text, archived_at timestamp with time zone, is_delete_marker boolean, is_versioned boolean)
    LANGUAGE plpgsql STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
    v_prefix_pattern text;
    v_sort_order text;
    v_sort_column text;
    v_version_tiebreak text;
BEGIN
    v_prefix := coalesce(p_prefix, '');
    -- Keep the raw prefix for common-prefix calculations and escape only LIKE metacharacters.
    v_prefix_pattern := replace(v_prefix, chr(92), chr(92) || chr(92));
    v_prefix_pattern := replace(v_prefix_pattern, '%', chr(92) || '%');
    v_prefix_pattern := replace(v_prefix_pattern, '_', chr(92) || '_');

    -- COALESCE first: NULL NOT IN (...) evaluates to NULL (not TRUE), so a
    -- bare NOT IN check silently leaves an explicit NULL argument unreset.
    noncurrent_versions := COALESCE(noncurrent_versions, 'exclude');
    delete_markers := COALESCE(delete_markers, 'exclude');
    IF noncurrent_versions NOT IN ('exclude', 'only', 'include') THEN
        noncurrent_versions := 'exclude';
    END IF;
    IF delete_markers NOT IN ('exclude', 'only', 'include') THEN
        delete_markers := 'exclude';
    END IF;

    -- $9 is only populated in multi-row mode; it's always '' otherwise, so
    -- only use each row's real version as a tiebreak in multi-row mode.
    v_version_tiebreak := CASE WHEN noncurrent_versions IN ('only', 'include') THEN 'COALESCE(version, '''')' ELSE '''''' END;

    -- Defense-in-depth: this function is independently reachable and must
    -- not trust p_sort_order/p_sort_column to already be validated by a
    -- caller. Normalize to the same strict allow-list storage.search_v2
    -- uses before interpolating anything into dynamic SQL below.
    v_sort_order := lower(coalesce(p_sort_order, 'asc'));
    IF v_sort_order NOT IN ('asc', 'desc') THEN
        v_sort_order := 'asc';
    END IF;

    v_sort_column := lower(coalesce(p_sort_column, 'updated_at'));
    IF v_sort_column NOT IN ('updated_at', 'created_at') THEN
        v_sort_column := 'updated_at';
    END IF;

    IF v_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                o.version AS obj_version,
                o.archived_at AS obj_archived_at,
                o.is_delete_marker AS obj_is_delete_marker,
                o.is_versioned AS obj_is_versioned,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $10 || '%%'
              AND ($7 != 'exclude' OR o.archived_at IS NULL)
              AND ($7 != 'only' OR o.archived_at IS NOT NULL)
              AND ($8 != 'exclude' OR NOT o.is_delete_marker)
              AND ($8 != 'only' OR o.is_delete_marker)
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                common_prefix AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                NULL::text AS version,
                NULL::timestamptz AS archived_at,
                NULL::boolean AS is_delete_marker,
                NULL::boolean AS is_versioned,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                obj_version AS version,
                obj_archived_at AS archived_at,
                obj_is_delete_marker AS is_delete_marker,
                obj_is_versioned AS is_versioned,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz),
                    name COLLATE "C",
                    %s
                ) %s ROW(
                    -- truncated the same way as the stored value above
                    date_trunc('milliseconds', COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz)),
                    $5,
                    $9
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata,
            version,
            archived_at,
            is_delete_marker,
            is_versioned
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s,
            COALESCE(version, '') %s
        LIMIT $4
    $sql$,
        v_sort_column,
        v_version_tiebreak,
        v_cursor_op,
        v_sort_column,
        v_sort_order,
        v_sort_order,
        v_sort_order
    );

    -- version is the third tiebreak component for two versions of the same
    -- key tying on both timestamp and name (see filtered CTE / ORDER BY above)
    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after, noncurrent_versions, delete_markers, coalesce(p_start_after_version, ''), v_prefix_pattern;
END;
$_$;


--
-- Name: search_v2(text, text, integer, integer, text, text, text, text, text, text, timestamp with time zone, text, boolean); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer DEFAULT 100, levels integer DEFAULT 1, start_after text DEFAULT ''::text, sort_order text DEFAULT 'asc'::text, sort_column text DEFAULT 'name'::text, sort_column_after text DEFAULT ''::text, noncurrent_versions text DEFAULT 'exclude'::text, delete_markers text DEFAULT 'exclude'::text, start_after_archived_at timestamp with time zone DEFAULT NULL::timestamp with time zone, start_after_version text DEFAULT ''::text, start_after_is_continuation boolean DEFAULT false) RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb, version text, archived_at timestamp with time zone, is_delete_marker boolean, is_versioned boolean)
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata,
            l.version,
            l.archived_at,
            l.is_delete_marker,
            l.is_versioned
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            CASE WHEN start_after_is_continuation THEN '' ELSE start_after END,
            CASE WHEN start_after_is_continuation THEN start_after ELSE '' END,
            v_sort_ord,
            noncurrent_versions,
            delete_markers,
            start_after_archived_at,
            start_after_version
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after,
            noncurrent_versions, delete_markers, start_after_version
        );
    END IF;
END;
$$;


--
-- Name: update_updated_at_column(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.update_updated_at_column() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


--
-- Name: audit_log_entries; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.audit_log_entries (
    instance_id uuid,
    id uuid NOT NULL,
    payload json,
    created_at timestamp with time zone,
    ip_address character varying(64) DEFAULT ''::character varying NOT NULL
);


--
-- Name: TABLE audit_log_entries; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.audit_log_entries IS 'Auth: Audit trail for user actions.';


--
-- Name: custom_oauth_providers; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.custom_oauth_providers (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    provider_type text NOT NULL,
    identifier text NOT NULL,
    name text NOT NULL,
    client_id text NOT NULL,
    client_secret text NOT NULL,
    acceptable_client_ids text[] DEFAULT '{}'::text[] NOT NULL,
    scopes text[] DEFAULT '{}'::text[] NOT NULL,
    pkce_enabled boolean DEFAULT true NOT NULL,
    attribute_mapping jsonb DEFAULT '{}'::jsonb NOT NULL,
    authorization_params jsonb DEFAULT '{}'::jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    email_optional boolean DEFAULT false NOT NULL,
    issuer text,
    discovery_url text,
    skip_nonce_check boolean DEFAULT false NOT NULL,
    cached_discovery jsonb,
    discovery_cached_at timestamp with time zone,
    authorization_url text,
    token_url text,
    userinfo_url text,
    jwks_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    custom_claims_allowlist text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT custom_oauth_providers_authorization_url_https CHECK (((authorization_url IS NULL) OR (authorization_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_authorization_url_length CHECK (((authorization_url IS NULL) OR (char_length(authorization_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_client_id_length CHECK (((char_length(client_id) >= 1) AND (char_length(client_id) <= 512))),
    CONSTRAINT custom_oauth_providers_discovery_url_length CHECK (((discovery_url IS NULL) OR (char_length(discovery_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_identifier_format CHECK ((identifier ~ '^[a-z0-9][a-z0-9:-]{0,48}[a-z0-9]$'::text)),
    CONSTRAINT custom_oauth_providers_issuer_length CHECK (((issuer IS NULL) OR ((char_length(issuer) >= 1) AND (char_length(issuer) <= 2048)))),
    CONSTRAINT custom_oauth_providers_jwks_uri_https CHECK (((jwks_uri IS NULL) OR (jwks_uri ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_jwks_uri_length CHECK (((jwks_uri IS NULL) OR (char_length(jwks_uri) <= 2048))),
    CONSTRAINT custom_oauth_providers_name_length CHECK (((char_length(name) >= 1) AND (char_length(name) <= 100))),
    CONSTRAINT custom_oauth_providers_oauth2_requires_endpoints CHECK (((provider_type <> 'oauth2'::text) OR ((authorization_url IS NOT NULL) AND (token_url IS NOT NULL) AND (userinfo_url IS NOT NULL)))),
    CONSTRAINT custom_oauth_providers_oidc_discovery_url_https CHECK (((provider_type <> 'oidc'::text) OR (discovery_url IS NULL) OR (discovery_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_oidc_issuer_https CHECK (((provider_type <> 'oidc'::text) OR (issuer IS NULL) OR (issuer ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_oidc_requires_issuer CHECK (((provider_type <> 'oidc'::text) OR (issuer IS NOT NULL))),
    CONSTRAINT custom_oauth_providers_provider_type_check CHECK ((provider_type = ANY (ARRAY['oauth2'::text, 'oidc'::text]))),
    CONSTRAINT custom_oauth_providers_token_url_https CHECK (((token_url IS NULL) OR (token_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_token_url_length CHECK (((token_url IS NULL) OR (char_length(token_url) <= 2048))),
    CONSTRAINT custom_oauth_providers_userinfo_url_https CHECK (((userinfo_url IS NULL) OR (userinfo_url ~~ 'https://%'::text))),
    CONSTRAINT custom_oauth_providers_userinfo_url_length CHECK (((userinfo_url IS NULL) OR (char_length(userinfo_url) <= 2048)))
);


--
-- Name: flow_state; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.flow_state (
    id uuid NOT NULL,
    user_id uuid,
    auth_code text,
    code_challenge_method auth.code_challenge_method,
    code_challenge text,
    provider_type text NOT NULL,
    provider_access_token text,
    provider_refresh_token text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    authentication_method text NOT NULL,
    auth_code_issued_at timestamp with time zone,
    invite_token text,
    referrer text,
    oauth_client_state_id uuid,
    linking_target_id uuid,
    email_optional boolean DEFAULT false NOT NULL
);


--
-- Name: TABLE flow_state; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.flow_state IS 'Stores metadata for all OAuth/SSO login flows';


--
-- Name: identities; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.identities (
    provider_id text NOT NULL,
    user_id uuid NOT NULL,
    identity_data jsonb NOT NULL,
    provider text NOT NULL,
    last_sign_in_at timestamp with time zone,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    email text GENERATED ALWAYS AS (lower((identity_data ->> 'email'::text))) STORED,
    id uuid DEFAULT gen_random_uuid() NOT NULL
);


--
-- Name: TABLE identities; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.identities IS 'Auth: Stores identities associated to a user.';


--
-- Name: COLUMN identities.email; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.identities.email IS 'Auth: Email is a generated column that references the optional email property in the identity_data';


--
-- Name: instances; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.instances (
    id uuid NOT NULL,
    uuid uuid,
    raw_base_config text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone
);


--
-- Name: TABLE instances; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.instances IS 'Auth: Manages users across multiple sites.';


--
-- Name: mfa_amr_claims; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_amr_claims (
    session_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    authentication_method text NOT NULL,
    id uuid NOT NULL
);


--
-- Name: TABLE mfa_amr_claims; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_amr_claims IS 'auth: stores authenticator method reference claims for multi factor authentication';


--
-- Name: mfa_challenges; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_challenges (
    id uuid NOT NULL,
    factor_id uuid NOT NULL,
    created_at timestamp with time zone NOT NULL,
    verified_at timestamp with time zone,
    ip_address inet NOT NULL,
    otp_code text,
    web_authn_session_data jsonb
);


--
-- Name: TABLE mfa_challenges; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_challenges IS 'auth: stores metadata about challenge requests made';


--
-- Name: mfa_factors; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_factors (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    friendly_name text,
    factor_type auth.factor_type NOT NULL,
    status auth.factor_status NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    secret text,
    phone text,
    last_challenged_at timestamp with time zone,
    web_authn_credential jsonb,
    web_authn_aaguid uuid,
    last_webauthn_challenge_data jsonb
);


--
-- Name: TABLE mfa_factors; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.mfa_factors IS 'auth: stores metadata about factors';


--
-- Name: COLUMN mfa_factors.last_webauthn_challenge_data; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.mfa_factors.last_webauthn_challenge_data IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';


--
-- Name: mfa_recovery_code_sets; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_recovery_code_sets (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    mfa_factor_id uuid NOT NULL,
    failed_verification_count integer DEFAULT 0 NOT NULL,
    verification_locked_until timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT mfa_recovery_code_sets_failed_verification_count_check CHECK ((failed_verification_count >= 0))
);


--
-- Name: mfa_recovery_codes; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.mfa_recovery_codes (
    id uuid NOT NULL,
    mfa_recovery_code_set_id uuid NOT NULL,
    code_hash text NOT NULL,
    consumed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: oauth_authorizations; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_authorizations (
    id uuid NOT NULL,
    authorization_id text NOT NULL,
    client_id uuid NOT NULL,
    user_id uuid,
    redirect_uri text NOT NULL,
    scope text NOT NULL,
    state text,
    resource text,
    code_challenge text,
    code_challenge_method auth.code_challenge_method,
    response_type auth.oauth_response_type DEFAULT 'code'::auth.oauth_response_type NOT NULL,
    status auth.oauth_authorization_status DEFAULT 'pending'::auth.oauth_authorization_status NOT NULL,
    authorization_code text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '00:03:00'::interval) NOT NULL,
    approved_at timestamp with time zone,
    nonce text,
    CONSTRAINT oauth_authorizations_authorization_code_length CHECK ((char_length(authorization_code) <= 255)),
    CONSTRAINT oauth_authorizations_code_challenge_length CHECK ((char_length(code_challenge) <= 128)),
    CONSTRAINT oauth_authorizations_expires_at_future CHECK ((expires_at > created_at)),
    CONSTRAINT oauth_authorizations_nonce_length CHECK ((char_length(nonce) <= 255)),
    CONSTRAINT oauth_authorizations_redirect_uri_length CHECK ((char_length(redirect_uri) <= 2048)),
    CONSTRAINT oauth_authorizations_resource_length CHECK ((char_length(resource) <= 2048)),
    CONSTRAINT oauth_authorizations_scope_length CHECK ((char_length(scope) <= 4096)),
    CONSTRAINT oauth_authorizations_state_length CHECK ((char_length(state) <= 4096))
);


--
-- Name: oauth_client_states; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_client_states (
    id uuid NOT NULL,
    provider_type text NOT NULL,
    code_verifier text,
    created_at timestamp with time zone NOT NULL
);


--
-- Name: TABLE oauth_client_states; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.oauth_client_states IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';


--
-- Name: oauth_clients; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_clients (
    id uuid NOT NULL,
    client_secret_hash text,
    registration_type auth.oauth_registration_type NOT NULL,
    redirect_uris text NOT NULL,
    grant_types text NOT NULL,
    client_name text,
    client_uri text,
    logo_uri text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    client_type auth.oauth_client_type DEFAULT 'confidential'::auth.oauth_client_type NOT NULL,
    token_endpoint_auth_method text NOT NULL,
    CONSTRAINT oauth_clients_client_name_length CHECK ((char_length(client_name) <= 1024)),
    CONSTRAINT oauth_clients_client_uri_length CHECK ((char_length(client_uri) <= 2048)),
    CONSTRAINT oauth_clients_logo_uri_length CHECK ((char_length(logo_uri) <= 2048)),
    CONSTRAINT oauth_clients_token_endpoint_auth_method_check CHECK ((token_endpoint_auth_method = ANY (ARRAY['client_secret_basic'::text, 'client_secret_post'::text, 'none'::text])))
);


--
-- Name: oauth_consents; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.oauth_consents (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    client_id uuid NOT NULL,
    scopes text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT oauth_consents_revoked_after_granted CHECK (((revoked_at IS NULL) OR (revoked_at >= granted_at))),
    CONSTRAINT oauth_consents_scopes_length CHECK ((char_length(scopes) <= 2048)),
    CONSTRAINT oauth_consents_scopes_not_empty CHECK ((char_length(TRIM(BOTH FROM scopes)) > 0))
);


--
-- Name: one_time_tokens; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.one_time_tokens (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    token_type auth.one_time_token_type NOT NULL,
    token_hash text NOT NULL,
    relates_to text NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone,
    CONSTRAINT one_time_tokens_token_hash_check CHECK ((char_length(token_hash) > 0))
);


--
-- Name: refresh_tokens; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.refresh_tokens (
    instance_id uuid,
    id bigint NOT NULL,
    token character varying(255),
    user_id character varying(255),
    revoked boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    parent character varying(255),
    session_id uuid
);


--
-- Name: TABLE refresh_tokens; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.refresh_tokens IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE; Schema: auth; Owner: -
--

CREATE SEQUENCE auth.refresh_tokens_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE OWNED BY; Schema: auth; Owner: -
--

ALTER SEQUENCE auth.refresh_tokens_id_seq OWNED BY auth.refresh_tokens.id;


--
-- Name: saml_providers; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.saml_providers (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    entity_id text NOT NULL,
    metadata_xml text NOT NULL,
    metadata_url text,
    attribute_mapping jsonb,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    name_id_format text,
    CONSTRAINT "entity_id not empty" CHECK ((char_length(entity_id) > 0)),
    CONSTRAINT "metadata_url not empty" CHECK (((metadata_url = NULL::text) OR (char_length(metadata_url) > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK ((char_length(metadata_xml) > 0))
);


--
-- Name: TABLE saml_providers; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.saml_providers IS 'Auth: Manages SAML Identity Provider connections.';


--
-- Name: saml_relay_states; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.saml_relay_states (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    request_id text NOT NULL,
    for_email text,
    redirect_to text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    flow_state_id uuid,
    CONSTRAINT "request_id not empty" CHECK ((char_length(request_id) > 0))
);


--
-- Name: TABLE saml_relay_states; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.saml_relay_states IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';


--
-- Name: schema_migrations; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.schema_migrations (
    version character varying(255) NOT NULL
);


--
-- Name: TABLE schema_migrations; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.schema_migrations IS 'Auth: Manages updates to the auth system.';


--
-- Name: scim_tokens; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.scim_tokens (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    token_hash text NOT NULL,
    prefix text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone,
    revoked_at timestamp with time zone,
    last_used_at timestamp with time zone,
    CONSTRAINT scim_tokens_expires_at_future CHECK (((expires_at IS NULL) OR (expires_at > created_at))),
    CONSTRAINT scim_tokens_revoked_after_created CHECK (((revoked_at IS NULL) OR (revoked_at >= created_at))),
    CONSTRAINT scim_tokens_token_hash_check CHECK ((token_hash ~ '^[0-9a-f]{64}$'::text))
);


--
-- Name: scim_users; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.scim_users (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    user_id uuid,
    resource jsonb NOT NULL,
    user_name text GENERATED ALWAYS AS (lower((resource ->> 'userName'::text))) STORED NOT NULL,
    external_id text GENERATED ALWAYS AS ((resource ->> 'externalId'::text)) STORED,
    active boolean GENERATED ALWAYS AS (COALESCE(((resource ->> 'active'::text))::boolean, true)) STORED NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);


--
-- Name: sessions; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sessions (
    id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    factor_id uuid,
    aal auth.aal_level,
    not_after timestamp with time zone,
    refreshed_at timestamp without time zone,
    user_agent text,
    ip inet,
    tag text,
    oauth_client_id uuid,
    refresh_token_hmac_key text,
    refresh_token_counter bigint,
    scopes text,
    CONSTRAINT sessions_scopes_length CHECK ((char_length(scopes) <= 4096))
);


--
-- Name: TABLE sessions; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sessions IS 'Auth: Stores session data associated to a user.';


--
-- Name: COLUMN sessions.not_after; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.not_after IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';


--
-- Name: COLUMN sessions.refresh_token_hmac_key; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.refresh_token_hmac_key IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';


--
-- Name: COLUMN sessions.refresh_token_counter; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sessions.refresh_token_counter IS 'Holds the ID (counter) of the last issued refresh token.';


--
-- Name: sso_domains; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sso_domains (
    id uuid NOT NULL,
    sso_provider_id uuid NOT NULL,
    domain text NOT NULL,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK ((char_length(domain) > 0))
);


--
-- Name: TABLE sso_domains; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sso_domains IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';


--
-- Name: sso_providers; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.sso_providers (
    id uuid NOT NULL,
    resource_id text,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    disabled boolean,
    CONSTRAINT "resource_id not empty" CHECK (((resource_id = NULL::text) OR (char_length(resource_id) > 0)))
);


--
-- Name: TABLE sso_providers; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.sso_providers IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';


--
-- Name: COLUMN sso_providers.resource_id; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.sso_providers.resource_id IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';


--
-- Name: users; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.users (
    instance_id uuid,
    id uuid NOT NULL,
    aud character varying(255),
    role character varying(255),
    email character varying(255),
    encrypted_password character varying(255),
    email_confirmed_at timestamp with time zone,
    invited_at timestamp with time zone,
    confirmation_token character varying(255),
    confirmation_sent_at timestamp with time zone,
    recovery_token character varying(255),
    recovery_sent_at timestamp with time zone,
    email_change_token_new character varying(255),
    email_change character varying(255),
    email_change_sent_at timestamp with time zone,
    last_sign_in_at timestamp with time zone,
    raw_app_meta_data jsonb,
    raw_user_meta_data jsonb,
    is_super_admin boolean,
    created_at timestamp with time zone,
    updated_at timestamp with time zone,
    phone text DEFAULT NULL::character varying,
    phone_confirmed_at timestamp with time zone,
    phone_change text DEFAULT ''::character varying,
    phone_change_token character varying(255) DEFAULT ''::character varying,
    phone_change_sent_at timestamp with time zone,
    confirmed_at timestamp with time zone GENERATED ALWAYS AS (LEAST(email_confirmed_at, phone_confirmed_at)) STORED,
    email_change_token_current character varying(255) DEFAULT ''::character varying,
    email_change_confirm_status smallint DEFAULT 0,
    banned_until timestamp with time zone,
    reauthentication_token character varying(255) DEFAULT ''::character varying,
    reauthentication_sent_at timestamp with time zone,
    is_sso_user boolean DEFAULT false NOT NULL,
    deleted_at timestamp with time zone,
    is_anonymous boolean DEFAULT false NOT NULL,
    CONSTRAINT users_email_change_confirm_status_check CHECK (((email_change_confirm_status >= 0) AND (email_change_confirm_status <= 2)))
);


--
-- Name: TABLE users; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON TABLE auth.users IS 'Auth: Stores user login data within a secure schema.';


--
-- Name: COLUMN users.is_sso_user; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON COLUMN auth.users.is_sso_user IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';


--
-- Name: webauthn_challenges; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.webauthn_challenges (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    challenge_type text NOT NULL,
    session_data jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    CONSTRAINT webauthn_challenges_challenge_type_check CHECK ((challenge_type = ANY (ARRAY['signup'::text, 'registration'::text, 'authentication'::text])))
);


--
-- Name: webauthn_credentials; Type: TABLE; Schema: auth; Owner: -
--

CREATE TABLE auth.webauthn_credentials (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    credential_id bytea NOT NULL,
    public_key bytea NOT NULL,
    attestation_type text DEFAULT ''::text NOT NULL,
    aaguid uuid,
    sign_count bigint DEFAULT 0 NOT NULL,
    transports jsonb DEFAULT '[]'::jsonb NOT NULL,
    backup_eligible boolean DEFAULT false NOT NULL,
    backed_up boolean DEFAULT false NOT NULL,
    friendly_name text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone
);


--
-- Name: admin_audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.admin_audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_id uuid,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id text,
    summary text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    ip_hint text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT admin_audit_logs_action_check CHECK ((char_length(action) > 0)),
    CONSTRAINT admin_audit_logs_entity_type_check CHECK ((char_length(entity_type) > 0))
);


--
-- Name: TABLE admin_audit_logs; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON TABLE public.admin_audit_logs IS 'WS9 — administrator action audit trail.';


--
-- Name: cart_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cart_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    product_id uuid,
    quantity smallint DEFAULT '1'::smallint,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT cart_items_quantity_check CHECK ((quantity > 0))
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    slug text,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: coupon_redemptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coupon_redemptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    coupon_id uuid NOT NULL,
    user_id uuid NOT NULL,
    order_id uuid,
    discount_amount numeric(12,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: coupons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coupons (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    description text,
    discount_type text NOT NULL,
    percent_off numeric(5,2),
    amount_off numeric(12,2),
    free_delivery boolean DEFAULT false NOT NULL,
    min_order_amount numeric(12,2) DEFAULT 0 NOT NULL,
    max_discount_amount numeric(12,2),
    usage_limit integer,
    usage_count integer DEFAULT 0 NOT NULL,
    per_user_limit integer DEFAULT 1,
    is_one_time boolean DEFAULT false NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    promotion_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT coupons_discount_type_check CHECK ((discount_type = ANY (ARRAY['percentage'::text, 'fixed'::text, 'free_delivery'::text])))
);


--
-- Name: customer_addresses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_addresses (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    label text NOT NULL,
    recipient_name text NOT NULL,
    phone text NOT NULL,
    county text NOT NULL,
    town text NOT NULL,
    street_address text NOT NULL,
    additional_directions text,
    is_default boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT customer_addresses_label_check CHECK ((label = ANY (ARRAY['home'::text, 'work'::text, 'other'::text])))
);


--
-- Name: customer_preferences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.customer_preferences (
    user_id uuid NOT NULL,
    preferred_fulfillment text,
    preferred_pickup_location_id uuid,
    marketing_emails boolean DEFAULT false NOT NULL,
    sms_notifications boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    email_notifications boolean DEFAULT true NOT NULL,
    order_updates boolean DEFAULT true NOT NULL,
    payment_updates boolean DEFAULT true NOT NULL,
    CONSTRAINT customer_preferences_fulfillment_check CHECK (((preferred_fulfillment IS NULL) OR (preferred_fulfillment = ANY (ARRAY['pickup'::text, 'delivery'::text]))))
);


--
-- Name: COLUMN customer_preferences.email_notifications; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_preferences.email_notifications IS 'WS7 — allow transactional email (orders/payments/account).';


--
-- Name: COLUMN customer_preferences.order_updates; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_preferences.order_updates IS 'WS7 — order lifecycle notifications.';


--
-- Name: COLUMN customer_preferences.payment_updates; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.customer_preferences.payment_updates IS 'WS7 — payment lifecycle notifications.';


--
-- Name: gift_card_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gift_card_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    gift_card_id uuid NOT NULL,
    user_id uuid,
    order_id uuid,
    tx_type text NOT NULL,
    amount numeric(12,2) NOT NULL,
    balance_after numeric(12,2) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT gift_card_transactions_type_check CHECK ((tx_type = ANY (ARRAY['issue'::text, 'redeem'::text, 'refund'::text, 'adjust'::text, 'expire'::text])))
);


--
-- Name: gift_cards; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.gift_cards (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    initial_balance numeric(12,2) NOT NULL,
    balance numeric(12,2) NOT NULL,
    currency text DEFAULT 'KES'::text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    purchased_by uuid,
    recipient_email text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT gift_cards_balance_nonneg CHECK ((balance >= (0)::numeric)),
    CONSTRAINT gift_cards_status_check CHECK ((status = ANY (ARRAY['active'::text, 'depleted'::text, 'expired'::text, 'disabled'::text])))
);


--
-- Name: loyalty_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loyalty_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    earn_points_per_currency numeric(12,4) DEFAULT 0.01 NOT NULL,
    redeem_points_per_currency numeric(12,4) DEFAULT 10 NOT NULL,
    free_delivery_points integer DEFAULT 500 NOT NULL,
    min_redeem_points integer DEFAULT 100 NOT NULL,
    max_redeem_percent numeric(5,2) DEFAULT 50 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: loyalty_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.loyalty_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    tx_type text NOT NULL,
    points integer NOT NULL,
    balance_after integer NOT NULL,
    order_id uuid,
    description text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT loyalty_transactions_type_check CHECK ((tx_type = ANY (ARRAY['earn_purchase'::text, 'earn_promotion'::text, 'earn_referral'::text, 'earn_bonus'::text, 'redeem_discount'::text, 'redeem_delivery'::text, 'redeem_product'::text, 'adjust'::text, 'expire'::text])))
);


--
-- Name: notification_deliveries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_deliveries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    notification_id uuid,
    user_id uuid NOT NULL,
    event_type text NOT NULL,
    channel text NOT NULL,
    provider text DEFAULT 'mock'::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    retry_count integer DEFAULT 0 NOT NULL,
    max_retries integer DEFAULT 3 NOT NULL,
    external_id text,
    error_message text,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    response jsonb DEFAULT '{}'::jsonb NOT NULL,
    scheduled_at timestamp with time zone,
    sent_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT notification_deliveries_channel_check CHECK ((channel = ANY (ARRAY['in_app'::text, 'email'::text, 'sms'::text, 'push'::text]))),
    CONSTRAINT notification_deliveries_retry_nonneg CHECK ((retry_count >= 0)),
    CONSTRAINT notification_deliveries_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'queued'::text, 'sending'::text, 'sent'::text, 'delivered'::text, 'failed'::text, 'skipped'::text, 'cancelled'::text])))
);


--
-- Name: notification_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_type text NOT NULL,
    user_id uuid,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: notification_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text NOT NULL,
    channel text DEFAULT 'in_app'::text NOT NULL,
    subject text,
    body text NOT NULL,
    description text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT notification_templates_channel_check CHECK ((channel = ANY (ARRAY['in_app'::text, 'email'::text, 'sms'::text, 'push'::text])))
);


--
-- Name: order_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    event_type text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: order_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.order_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    product_id uuid,
    quantity smallint,
    price numeric,
    name text DEFAULT ''::text,
    image_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT order_items_quantity_check CHECK ((quantity > 0))
);


--
-- Name: orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.orders (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    total numeric,
    status text DEFAULT 'pending'::text,
    created_at timestamp without time zone DEFAULT now(),
    payment_status text DEFAULT 'pending'::text NOT NULL,
    note text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    delivery_type text,
    pickup_location_id uuid,
    delivery_address jsonb,
    delivery_fee numeric(12,2) DEFAULT 0 NOT NULL,
    customer_note text,
    payment_method text DEFAULT 'cod'::text NOT NULL,
    mpesa_receipt_number text,
    discount_amount numeric(12,2) DEFAULT 0 NOT NULL,
    coupon_code text,
    loyalty_points_redeemed integer DEFAULT 0 NOT NULL,
    gift_card_amount numeric(12,2) DEFAULT 0 NOT NULL,
    free_delivery boolean DEFAULT false NOT NULL,
    promotions_applied jsonb DEFAULT '[]'::jsonb NOT NULL,
    referral_code text,
    CONSTRAINT orders_delivery_type_check CHECK (((delivery_type IS NULL) OR (delivery_type = ANY (ARRAY['pickup'::text, 'delivery'::text])))),
    CONSTRAINT orders_payment_method_check CHECK ((payment_method = ANY (ARRAY['cod'::text, 'mpesa'::text, 'card'::text, 'paypal'::text, 'bank_transfer'::text]))),
    CONSTRAINT orders_payment_status_check CHECK ((payment_status = ANY (ARRAY['pending'::text, 'paid'::text, 'failed'::text, 'refunded'::text]))),
    CONSTRAINT orders_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'processing'::text, 'ready_for_pickup'::text, 'shipped'::text, 'delivered'::text, 'cancelled'::text])))
);


--
-- Name: COLUMN orders.payment_method; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.payment_method IS 'WS6 — checkout payment channel (cod default).';


--
-- Name: COLUMN orders.mpesa_receipt_number; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.mpesa_receipt_number IS 'WS6 — mirrored from payments.receipt_number when M-Pesa succeeds.';


--
-- Name: COLUMN orders.discount_amount; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.discount_amount IS 'WS8 — merchandise discount (excl. gift card).';


--
-- Name: COLUMN orders.promotions_applied; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.orders.promotions_applied IS 'WS8 — snapshot of applied promo/coupon ids.';


--
-- Name: payment_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payment_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payment_id uuid NOT NULL,
    event_type text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pickup_locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pickup_locations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    building text DEFAULT ''::text NOT NULL,
    description text,
    operating_hours jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: products; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.products (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    slug text,
    price numeric,
    category text,
    category_id uuid,
    featured boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT now(),
    description text,
    stock integer DEFAULT 0 NOT NULL,
    discount_price numeric(12,2),
    image_url text,
    images jsonb DEFAULT '[]'::jsonb NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT products_discount_lte_price_check CHECK (((discount_price IS NULL) OR (price IS NULL) OR (discount_price <= price))),
    CONSTRAINT products_price_nonneg_check CHECK (((price IS NULL) OR (price >= (0)::numeric))),
    CONSTRAINT products_stock_nonneg_check CHECK ((stock >= 0))
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    email text,
    role text DEFAULT 'customer'::text,
    created_at timestamp with time zone DEFAULT now(),
    phone text,
    full_name text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['customer'::text, 'admin'::text])))
);


--
-- Name: promotion_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promotion_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    promotion_id uuid NOT NULL,
    rule_type text NOT NULL,
    rule_value jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT promotion_rules_type_check CHECK ((rule_type = ANY (ARRAY['min_quantity'::text, 'max_uses_per_day'::text, 'customer_segment'::text, 'first_order_only'::text, 'exclude_sale_items'::text])))
);


--
-- Name: promotions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promotions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    code text,
    name text NOT NULL,
    description text,
    promo_type text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    stackable boolean DEFAULT false NOT NULL,
    percent_off numeric(5,2),
    amount_off numeric(12,2),
    buy_quantity integer,
    get_quantity integer,
    category_id uuid,
    product_id uuid,
    min_order_amount numeric(12,2) DEFAULT 0 NOT NULL,
    max_discount_amount numeric(12,2),
    usage_limit integer,
    usage_count integer DEFAULT 0 NOT NULL,
    per_user_limit integer,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    eligibility jsonb DEFAULT '{}'::jsonb NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT promotions_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'paused'::text, 'expired'::text]))),
    CONSTRAINT promotions_type_check CHECK ((promo_type = ANY (ARRAY['percentage'::text, 'fixed'::text, 'free_delivery'::text, 'buy_x_get_y'::text, 'category'::text, 'product'::text, 'storewide'::text])))
);


--
-- Name: referrals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.referrals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    referrer_user_id uuid NOT NULL,
    referred_user_id uuid,
    referral_code text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    reward_points integer DEFAULT 0 NOT NULL,
    referred_reward_points integer DEFAULT 0 NOT NULL,
    order_id uuid,
    rewarded_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT referrals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'signed_up'::text, 'qualified'::text, 'rewarded'::text, 'cancelled'::text])))
);


--
-- Name: reward_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reward_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    order_id uuid,
    event_type text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: wishlists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wishlists (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    product_id uuid,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: messages; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL
)
PARTITION BY RANGE (inserted_at);


--
-- Name: messages_2026_09_21; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_09_21 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_09_22; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_09_22 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_09_23; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_09_23 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_09_24; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_09_24 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_09_25; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_09_25 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_09_26; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_09_26 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_09_27; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_09_27 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: messages_2026_09_28; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.messages_2026_09_28 (
    topic text NOT NULL,
    extension text NOT NULL,
    payload jsonb,
    event text,
    private boolean DEFAULT false,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    inserted_at timestamp without time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    binary_payload bytea,
    skip_broadcast boolean DEFAULT false NOT NULL,
    CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL)))
);


--
-- Name: schema_migrations; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.schema_migrations (
    version bigint NOT NULL,
    inserted_at timestamp(0) without time zone
);


--
-- Name: subscription; Type: TABLE; Schema: realtime; Owner: -
--

CREATE TABLE realtime.subscription (
    id bigint NOT NULL,
    subscription_id uuid NOT NULL,
    entity regclass NOT NULL,
    filters realtime.user_defined_filter[] DEFAULT '{}'::realtime.user_defined_filter[] NOT NULL,
    claims jsonb NOT NULL,
    claims_role regrole GENERATED ALWAYS AS (realtime.to_regrole((claims ->> 'role'::text))) STORED NOT NULL,
    created_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    action_filter text DEFAULT '*'::text,
    selected_columns text[],
    CONSTRAINT subscription_action_filter_check CHECK ((action_filter = ANY (ARRAY['*'::text, 'INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


--
-- Name: subscription_id_seq; Type: SEQUENCE; Schema: realtime; Owner: -
--

ALTER TABLE realtime.subscription ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME realtime.subscription_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: buckets; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets (
    id text NOT NULL,
    name text NOT NULL,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    public boolean DEFAULT false,
    avif_autodetection boolean DEFAULT false,
    file_size_limit bigint,
    allowed_mime_types text[],
    owner_id text,
    type storage.buckettype DEFAULT 'STANDARD'::storage.buckettype NOT NULL,
    versioning_status text DEFAULT 'DISABLED'::text NOT NULL,
    lifecycle_configuration jsonb,
    lifecycle_configuration_generation uuid,
    CONSTRAINT buckets_lifecycle_configuration_pair_check CHECK (((lifecycle_configuration IS NULL) = (lifecycle_configuration_generation IS NULL))),
    CONSTRAINT buckets_lifecycle_configuration_shape_check CHECK (((lifecycle_configuration IS NULL) OR ((jsonb_typeof(lifecycle_configuration) = 'object'::text) AND (lifecycle_configuration ? 'rules'::text) AND
CASE
    WHEN (jsonb_typeof((lifecycle_configuration -> 'rules'::text)) = 'array'::text) THEN ((jsonb_array_length((lifecycle_configuration -> 'rules'::text)) >= 1) AND (jsonb_array_length((lifecycle_configuration -> 'rules'::text)) <= 1000))
    ELSE false
END))),
    CONSTRAINT buckets_lifecycle_configuration_standard_only_check CHECK (((type = 'STANDARD'::storage.buckettype) OR ((lifecycle_configuration IS NULL) AND (lifecycle_configuration_generation IS NULL)))),
    CONSTRAINT buckets_versioning_dark_check CHECK ((versioning_status = 'DISABLED'::text)),
    CONSTRAINT buckets_versioning_standard_only_check CHECK (((type = 'STANDARD'::storage.buckettype) OR (versioning_status = 'DISABLED'::text))),
    CONSTRAINT buckets_versioning_status_check CHECK ((versioning_status = ANY (ARRAY['DISABLED'::text, 'ENABLED'::text, 'SUSPENDED'::text])))
);


--
-- Name: COLUMN buckets.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.buckets.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: buckets_analytics; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets_analytics (
    name text NOT NULL,
    type storage.buckettype DEFAULT 'ANALYTICS'::storage.buckettype NOT NULL,
    format text DEFAULT 'ICEBERG'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    deleted_at timestamp with time zone
);


--
-- Name: buckets_vectors; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.buckets_vectors (
    id text NOT NULL,
    type storage.buckettype DEFAULT 'VECTOR'::storage.buckettype NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: migrations; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.migrations (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    hash character varying(40) NOT NULL,
    executed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: objects; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.objects (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket_id text,
    name text,
    owner uuid,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    last_accessed_at timestamp with time zone DEFAULT now(),
    metadata jsonb,
    path_tokens text[] GENERATED ALWAYS AS (string_to_array(name, '/'::text)) STORED,
    version text,
    owner_id text,
    user_metadata jsonb,
    archived_at timestamp with time zone,
    is_delete_marker boolean DEFAULT false NOT NULL,
    is_versioned boolean DEFAULT false NOT NULL
);


--
-- Name: COLUMN objects.owner; Type: COMMENT; Schema: storage; Owner: -
--

COMMENT ON COLUMN storage.objects.owner IS 'Field is deprecated, use owner_id instead';


--
-- Name: s3_multipart_uploads; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads (
    id text NOT NULL,
    in_progress_size bigint DEFAULT 0 NOT NULL,
    upload_signature text NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    version text NOT NULL,
    owner_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_metadata jsonb,
    metadata jsonb
);


--
-- Name: s3_multipart_uploads_parts; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.s3_multipart_uploads_parts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    upload_id text NOT NULL,
    size bigint DEFAULT 0 NOT NULL,
    part_number integer NOT NULL,
    bucket_id text NOT NULL,
    key text NOT NULL COLLATE pg_catalog."C",
    etag text NOT NULL,
    owner_id text,
    version text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: vector_indexes; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.vector_indexes (
    id text DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL COLLATE pg_catalog."C",
    bucket_id text NOT NULL,
    data_type text NOT NULL,
    dimension integer NOT NULL,
    distance_metric text NOT NULL,
    metadata_configuration jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: supabase_migrations; Owner: -
--

CREATE TABLE supabase_migrations.schema_migrations (
    version text NOT NULL,
    statements text[],
    name text
);


--
-- Name: messages_2026_09_21; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_09_21 FOR VALUES FROM ('2026-09-21 00:00:00') TO ('2026-09-22 00:00:00');


--
-- Name: messages_2026_09_22; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_09_22 FOR VALUES FROM ('2026-09-22 00:00:00') TO ('2026-09-23 00:00:00');


--
-- Name: messages_2026_09_23; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_09_23 FOR VALUES FROM ('2026-09-23 00:00:00') TO ('2026-09-24 00:00:00');


--
-- Name: messages_2026_09_24; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_09_24 FOR VALUES FROM ('2026-09-24 00:00:00') TO ('2026-09-25 00:00:00');


--
-- Name: messages_2026_09_25; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_09_25 FOR VALUES FROM ('2026-09-25 00:00:00') TO ('2026-09-26 00:00:00');


--
-- Name: messages_2026_09_26; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_09_26 FOR VALUES FROM ('2026-09-26 00:00:00') TO ('2026-09-27 00:00:00');


--
-- Name: messages_2026_09_27; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_09_27 FOR VALUES FROM ('2026-09-27 00:00:00') TO ('2026-09-28 00:00:00');


--
-- Name: messages_2026_09_28; Type: TABLE ATTACH; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages ATTACH PARTITION realtime.messages_2026_09_28 FOR VALUES FROM ('2026-09-28 00:00:00') TO ('2026-09-29 00:00:00');


--
-- Name: refresh_tokens id; Type: DEFAULT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens ALTER COLUMN id SET DEFAULT nextval('auth.refresh_tokens_id_seq'::regclass);


--
-- Data for Name: audit_log_entries; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.audit_log_entries (instance_id, id, payload, created_at, ip_address) FROM stdin;
\.


--
-- Data for Name: custom_oauth_providers; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.custom_oauth_providers (id, provider_type, identifier, name, client_id, client_secret, acceptable_client_ids, scopes, pkce_enabled, attribute_mapping, authorization_params, enabled, email_optional, issuer, discovery_url, skip_nonce_check, cached_discovery, discovery_cached_at, authorization_url, token_url, userinfo_url, jwks_uri, created_at, updated_at, custom_claims_allowlist) FROM stdin;
\.


--
-- Data for Name: flow_state; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.flow_state (id, user_id, auth_code, code_challenge_method, code_challenge, provider_type, provider_access_token, provider_refresh_token, created_at, updated_at, authentication_method, auth_code_issued_at, invite_token, referrer, oauth_client_state_id, linking_target_id, email_optional) FROM stdin;
\.


--
-- Data for Name: identities; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at, id) FROM stdin;
e47efb2a-278c-4420-b294-87a16e9be730	e47efb2a-278c-4420-b294-87a16e9be730	{"sub": "e47efb2a-278c-4420-b294-87a16e9be730", "email": "user1@gmail.com", "email_verified": false, "phone_verified": false}	email	2026-06-18 09:45:35.499592+00	2026-06-18 09:45:35.499651+00	2026-06-18 09:45:35.499651+00	ebf5d6a7-e083-40d5-bc6d-c8af6095cc30
2c68a903-e68d-4f00-8586-d0efc6047b2b	2c68a903-e68d-4f00-8586-d0efc6047b2b	{"sub": "2c68a903-e68d-4f00-8586-d0efc6047b2b", "email": "admin@test.com", "email_verified": false, "phone_verified": false}	email	2026-06-18 09:49:40.159738+00	2026-06-18 09:49:40.159804+00	2026-06-18 09:49:40.159804+00	da3c0cf1-a729-40fb-b76b-42f8bc7449f5
7d487b08-c6f1-4726-a23b-cbb9f7647cbd	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{"sub": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "email": "samoraedwin603@gmail.com", "email_verified": false, "phone_verified": false}	email	2026-06-18 18:36:08.355394+00	2026-06-18 18:36:08.355452+00	2026-06-18 18:36:08.355452+00	d08fe725-9f3e-4440-a5f1-849ce0570c10
c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	{"sub": "c1f57dbb-e6f5-4a51-8985-188a6fd3a11b", "email": "samoraedwin101@gmail.com", "email_verified": false, "phone_verified": false}	email	2026-06-22 00:14:14.5077+00	2026-06-22 00:14:14.507753+00	2026-06-22 00:14:14.507753+00	0259d1c1-38c3-4272-950c-da163b3c4422
323a7849-cfa6-4f19-95a0-2f5f82491436	323a7849-cfa6-4f19-95a0-2f5f82491436	{"sub": "323a7849-cfa6-4f19-95a0-2f5f82491436", "email": "audit-test-1783930754107@example.com", "phone": "+254712345678", "full_name": "Audit Test", "email_verified": false, "phone_verified": false}	email	2026-07-13 08:19:15.049029+00	2026-07-13 08:19:15.049121+00	2026-07-13 08:19:15.049121+00	8f18a964-1c39-4be3-8d4a-1d6de132e398
b98a07b1-467f-4e20-ac14-da354b094637	b98a07b1-467f-4e20-ac14-da354b094637	{"sub": "b98a07b1-467f-4e20-ac14-da354b094637", "email": "admin@babeesplace.com", "phone": "+254700000000", "full_name": "Babees Admin", "email_verified": false, "phone_verified": false}	email	2026-07-13 08:19:54.738417+00	2026-07-13 08:19:54.738478+00	2026-07-13 08:19:54.738478+00	d7f2729a-71e5-46fa-bb32-472ce69a0866
91877d22-84c1-4253-9e57-13aa5a617b1c	91877d22-84c1-4253-9e57-13aa5a617b1c	{"sub": "91877d22-84c1-4253-9e57-13aa5a617b1c", "email": "customer@babeesplace.com", "phone": "+254700000000", "full_name": "Babees Customer", "email_verified": false, "phone_verified": false}	email	2026-07-13 08:19:55.975625+00	2026-07-13 08:19:55.975687+00	2026-07-13 08:19:55.975687+00	9b340676-0c36-4ed3-8d4e-eeca69215b19
50c6281a-69e0-4c36-a73b-58780a2c8acd	50c6281a-69e0-4c36-a73b-58780a2c8acd	{"sub": "50c6281a-69e0-4c36-a73b-58780a2c8acd", "email": "ghostprompt101@gmail.com", "phone": "+254712345678", "full_name": "ghost", "email_verified": false, "phone_verified": false}	email	2026-07-20 12:50:01.03683+00	2026-07-20 12:50:01.03689+00	2026-07-20 12:50:01.03689+00	7692ddf9-6ad3-409c-a429-1b310e859969
ce11a1e1-39f2-471e-9c62-483ba6b04780	ce11a1e1-39f2-471e-9c62-483ba6b04780	{"sub": "ce11a1e1-39f2-471e-9c62-483ba6b04780", "email": "wangechi.njeri@babeesplace.demo", "email_verified": false, "phone_verified": false}	email	2026-08-03 08:52:46.558513+00	2026-08-03 08:52:46.558568+00	2026-08-03 08:52:46.558568+00	3ac98f2d-573a-465e-834d-4d34909a5936
ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7	ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7	{"sub": "ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7", "email": "kevin.ochieng@babeesplace.demo", "email_verified": false, "phone_verified": false}	email	2026-08-03 08:52:47.094111+00	2026-08-03 08:52:47.094183+00	2026-08-03 08:52:47.094183+00	e21079c1-3ed1-4657-a82d-cf7e2b237675
328a2e81-1496-404e-88c4-d7f45b72a1b6	328a2e81-1496-404e-88c4-d7f45b72a1b6	{"sub": "328a2e81-1496-404e-88c4-d7f45b72a1b6", "email": "faith.wambui@babeesplace.demo", "email_verified": false, "phone_verified": false}	email	2026-08-03 08:52:47.631081+00	2026-08-03 08:52:47.631145+00	2026-08-03 08:52:47.631145+00	f1ac61d5-5ad1-4be5-a097-9878a7eb2443
1f33a52d-a5b9-475a-bf28-857045f4ad09	1f33a52d-a5b9-475a-bf28-857045f4ad09	{"sub": "1f33a52d-a5b9-475a-bf28-857045f4ad09", "email": "daniel.kiprop@babeesplace.demo", "email_verified": false, "phone_verified": false}	email	2026-08-03 08:52:48.165642+00	2026-08-03 08:52:48.165712+00	2026-08-03 08:52:48.165712+00	052cad07-a3fa-4ca9-a972-65caa8c19fa9
a9c07a6f-4063-4793-a3a0-129d96a50e02	a9c07a6f-4063-4793-a3a0-129d96a50e02	{"sub": "a9c07a6f-4063-4793-a3a0-129d96a50e02", "email": "mercy.akinyi@babeesplace.demo", "email_verified": false, "phone_verified": false}	email	2026-08-03 08:52:48.696155+00	2026-08-03 08:52:48.696219+00	2026-08-03 08:52:48.696219+00	e01874b9-d792-4757-aba0-f35a2b000dcb
a2a071d2-da64-4571-9f17-288c5abd72dc	a2a071d2-da64-4571-9f17-288c5abd72dc	{"sub": "a2a071d2-da64-4571-9f17-288c5abd72dc", "email": "james.mutiso@babeesplace.demo", "email_verified": false, "phone_verified": false}	email	2026-08-03 08:52:49.237812+00	2026-08-03 08:52:49.237875+00	2026-08-03 08:52:49.237875+00	768606d0-1d7f-447f-aeae-26894ebc5d37
d32dcbba-ff92-4df5-bb3e-089d16a5141e	d32dcbba-ff92-4df5-bb3e-089d16a5141e	{"sub": "d32dcbba-ff92-4df5-bb3e-089d16a5141e", "email": "lucy.cherono@babeesplace.demo", "email_verified": false, "phone_verified": false}	email	2026-08-03 08:52:49.767663+00	2026-08-03 08:52:49.767731+00	2026-08-03 08:52:49.767731+00	89939492-9941-49f8-a2df-fc7fd46ca3de
eebd94c0-8179-4619-a527-218ac9f7d5c4	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"sub": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "email": "nesambulaz@gmail.com", "phone": "+254740845440", "full_name": "Nestar Ambula", "email_verified": false, "phone_verified": false}	email	2026-08-13 05:59:54.980685+00	2026-08-13 05:59:54.980741+00	2026-08-13 05:59:54.980741+00	43abb6c0-c1af-4d3d-816a-defd9dcfd52f
5a04e47f-c9d3-485b-8b23-3aa74d9d729e	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	{"sub": "5a04e47f-c9d3-485b-8b23-3aa74d9d729e", "email": "minyoso@gmail", "phone": "+2547555555555", "full_name": "lillian", "email_verified": false, "phone_verified": false}	email	2026-08-13 15:10:24.75022+00	2026-08-13 15:10:24.750289+00	2026-08-13 15:10:24.750289+00	90e8f3fb-e0d7-4a3e-af85-3d247e24b900
0615e227-eeae-4afe-b3e2-0acc74b7c439	0615e227-eeae-4afe-b3e2-0acc74b7c439	{"sub": "0615e227-eeae-4afe-b3e2-0acc74b7c439", "email": "oscaraseka1111@gmail.com", "phone": "+254712944345", "full_name": "Oscar Aseka", "email_verified": false, "phone_verified": false}	email	2026-09-05 10:59:29.06794+00	2026-09-05 10:59:29.06805+00	2026-09-05 10:59:29.06805+00	96e35bd3-bb36-4608-a94d-1830c239f543
\.


--
-- Data for Name: instances; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.instances (id, uuid, raw_base_config, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: mfa_amr_claims; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.mfa_amr_claims (session_id, created_at, updated_at, authentication_method, id) FROM stdin;
0724b8ef-6b1d-4f1a-9208-3aa9b274e626	2026-09-05 10:59:29.133257+00	2026-09-05 10:59:29.133257+00	password	8a036a2d-0b29-4c2f-8f00-f6e97dba03cc
b9ac1288-ee2a-47a2-9e84-9c46d9a96996	2026-09-22 13:44:20.790246+00	2026-09-22 13:44:20.790246+00	password	179f6811-8d5c-45ad-838c-793b5d48d6f6
04a237b6-4f75-492e-b472-c7cd8c14784f	2026-07-13 08:19:15.074221+00	2026-07-13 08:19:15.074221+00	password	a7055ab8-d4ce-455c-86f9-b047669af4ee
fb810481-40f8-4d15-be68-cf7ae33470f7	2026-07-13 08:19:16.410495+00	2026-07-13 08:19:16.410495+00	password	1faf2aee-c48f-46a2-89a9-54446c0a358b
79e4662a-2bfa-4def-b31d-82395a03e844	2026-08-04 06:19:47.13728+00	2026-08-04 06:19:47.13728+00	password	3a65d27f-1cfd-4590-bbd7-650b63d2b874
8cceb5c3-5124-42d7-b4e9-bf331e27a6af	2026-08-13 05:59:55.046817+00	2026-08-13 05:59:55.046817+00	password	c72a9341-a6c5-470f-a261-a65917bcd1c3
84d29128-dcf3-4087-8c43-9939843c58f5	2026-08-26 22:38:30.136112+00	2026-08-26 22:38:30.136112+00	password	82e0539b-7828-4bd4-9934-85c8e12a1158
\.


--
-- Data for Name: mfa_challenges; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.mfa_challenges (id, factor_id, created_at, verified_at, ip_address, otp_code, web_authn_session_data) FROM stdin;
\.


--
-- Data for Name: mfa_factors; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.mfa_factors (id, user_id, friendly_name, factor_type, status, created_at, updated_at, secret, phone, last_challenged_at, web_authn_credential, web_authn_aaguid, last_webauthn_challenge_data) FROM stdin;
\.


--
-- Data for Name: mfa_recovery_code_sets; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.mfa_recovery_code_sets (id, user_id, mfa_factor_id, failed_verification_count, verification_locked_until, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: mfa_recovery_codes; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.mfa_recovery_codes (id, mfa_recovery_code_set_id, code_hash, consumed_at, created_at) FROM stdin;
\.


--
-- Data for Name: oauth_authorizations; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.oauth_authorizations (id, authorization_id, client_id, user_id, redirect_uri, scope, state, resource, code_challenge, code_challenge_method, response_type, status, authorization_code, created_at, expires_at, approved_at, nonce) FROM stdin;
\.


--
-- Data for Name: oauth_client_states; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.oauth_client_states (id, provider_type, code_verifier, created_at) FROM stdin;
\.


--
-- Data for Name: oauth_clients; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.oauth_clients (id, client_secret_hash, registration_type, redirect_uris, grant_types, client_name, client_uri, logo_uri, created_at, updated_at, deleted_at, client_type, token_endpoint_auth_method) FROM stdin;
\.


--
-- Data for Name: oauth_consents; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.oauth_consents (id, user_id, client_id, scopes, granted_at, revoked_at) FROM stdin;
\.


--
-- Data for Name: one_time_tokens; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.one_time_tokens (id, user_id, token_type, token_hash, relates_to, created_at, updated_at, expires_at) FROM stdin;
\.


--
-- Data for Name: refresh_tokens; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.refresh_tokens (instance_id, id, token, user_id, revoked, created_at, updated_at, parent, session_id) FROM stdin;
00000000-0000-0000-0000-000000000000	61	54qj4xupgm3h	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	t	2026-08-26 22:38:30.117235+00	2026-08-26 23:38:03.624269+00	\N	84d29128-dcf3-4087-8c43-9939843c58f5
00000000-0000-0000-0000-000000000000	62	67tqtn4xmiab	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	t	2026-08-26 23:38:03.643927+00	2026-08-27 03:25:43.393297+00	54qj4xupgm3h	84d29128-dcf3-4087-8c43-9939843c58f5
00000000-0000-0000-0000-000000000000	63	h6hnk64fbqtk	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	f	2026-08-27 03:25:43.408592+00	2026-08-27 03:25:43.408592+00	67tqtn4xmiab	84d29128-dcf3-4087-8c43-9939843c58f5
00000000-0000-0000-0000-000000000000	20	qk6dqknbmhvc	323a7849-cfa6-4f19-95a0-2f5f82491436	f	2026-07-13 08:19:15.070123+00	2026-07-13 08:19:15.070123+00	\N	04a237b6-4f75-492e-b472-c7cd8c14784f
00000000-0000-0000-0000-000000000000	21	ioisvjx243w6	323a7849-cfa6-4f19-95a0-2f5f82491436	f	2026-07-13 08:19:16.408779+00	2026-07-13 08:19:16.408779+00	\N	fb810481-40f8-4d15-be68-cf7ae33470f7
00000000-0000-0000-0000-000000000000	60	bai63khqedv6	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-08-25 15:18:25.293072+00	2026-09-01 01:33:54.866679+00	xmah24xw5wid	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	87	rkg6vespguo7	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-01 01:33:54.897755+00	2026-09-01 02:33:22.324908+00	bai63khqedv6	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	88	elt3kzd4cup6	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-01 02:33:22.342353+00	2026-09-01 03:32:22.481045+00	rkg6vespguo7	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	89	4pbc3jy2zjad	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-01 03:32:22.497814+00	2026-09-01 04:31:22.355496+00	elt3kzd4cup6	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	90	jsqk5o6ho55u	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-01 04:31:22.373077+00	2026-09-01 05:30:22.950858+00	4pbc3jy2zjad	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	91	u25ihxhtz5tf	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-01 05:30:22.96971+00	2026-09-04 07:00:16.052705+00	jsqk5o6ho55u	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	92	rlqlr2friq3n	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-04 07:00:16.075212+00	2026-09-05 00:16:26.857326+00	u25ihxhtz5tf	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	93	xt2keip7vprl	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-05 00:16:26.880325+00	2026-09-05 01:15:24.520859+00	rlqlr2friq3n	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	94	pg7yns7d4srq	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-05 01:15:24.538265+00	2026-09-05 02:14:24.668319+00	xt2keip7vprl	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	95	zgjs2uorugeq	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-05 02:14:24.679399+00	2026-09-05 03:13:24.426459+00	pg7yns7d4srq	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	96	jtihjadsqy6l	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-05 03:13:24.441106+00	2026-09-05 04:12:24.671789+00	zgjs2uorugeq	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	97	lpyoq7dodq5r	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-05 04:12:24.68477+00	2026-09-05 05:11:24.479178+00	jtihjadsqy6l	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	98	nlqm5jbpjkp6	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-05 05:11:24.498488+00	2026-09-05 06:10:24.658161+00	lpyoq7dodq5r	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	100	63sowzbdkutl	0615e227-eeae-4afe-b3e2-0acc74b7c439	t	2026-09-05 10:59:29.108352+00	2026-09-12 23:37:08.672032+00	\N	0724b8ef-6b1d-4f1a-9208-3aa9b274e626
00000000-0000-0000-0000-000000000000	101	d35kc6f6cvra	0615e227-eeae-4afe-b3e2-0acc74b7c439	f	2026-09-12 23:37:08.692965+00	2026-09-12 23:37:08.692965+00	63sowzbdkutl	0724b8ef-6b1d-4f1a-9208-3aa9b274e626
00000000-0000-0000-0000-000000000000	99	ii4aa62tiglp	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-05 06:10:24.671058+00	2026-09-22 13:40:33.108457+00	nlqm5jbpjkp6	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	49	baueys4roe23	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-08-04 06:19:47.126809+00	2026-08-04 08:32:11.940263+00	\N	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	103	dr27z22qnj4g	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	f	2026-09-22 13:44:20.776477+00	2026-09-22 13:44:20.776477+00	\N	b9ac1288-ee2a-47a2-9e84-9c46d9a96996
00000000-0000-0000-0000-000000000000	50	4tf67jxlednq	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-08-04 08:32:11.959359+00	2026-08-11 15:54:38.534686+00	baueys4roe23	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	102	akpqzj7wohoc	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-09-22 13:40:33.1171+00	2026-09-22 15:18:18.522151+00	ii4aa62tiglp	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	104	2ahnjj4g3bl4	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	f	2026-09-22 15:18:18.538228+00	2026-09-22 15:18:18.538228+00	akpqzj7wohoc	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	52	be3gjldnbx43	eebd94c0-8179-4619-a527-218ac9f7d5c4	t	2026-08-13 05:59:55.027976+00	2026-08-13 06:58:38.049164+00	\N	8cceb5c3-5124-42d7-b4e9-bf331e27a6af
00000000-0000-0000-0000-000000000000	53	vzgmrfegorty	eebd94c0-8179-4619-a527-218ac9f7d5c4	t	2026-08-13 06:58:38.067086+00	2026-08-13 13:00:28.998516+00	be3gjldnbx43	8cceb5c3-5124-42d7-b4e9-bf331e27a6af
00000000-0000-0000-0000-000000000000	54	2e5aeqd5mkfm	eebd94c0-8179-4619-a527-218ac9f7d5c4	f	2026-08-13 13:00:29.01684+00	2026-08-13 13:00:29.01684+00	vzgmrfegorty	8cceb5c3-5124-42d7-b4e9-bf331e27a6af
00000000-0000-0000-0000-000000000000	51	u52grb3wjqkg	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-08-11 15:54:38.553507+00	2026-08-21 14:30:32.762705+00	4tf67jxlednq	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	57	f4wlwgivxxx4	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-08-21 14:30:32.788414+00	2026-08-23 06:21:37.511577+00	u52grb3wjqkg	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	58	6uiwnokptoub	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-08-23 06:21:37.53349+00	2026-08-23 07:20:31.681503+00	f4wlwgivxxx4	79e4662a-2bfa-4def-b31d-82395a03e844
00000000-0000-0000-0000-000000000000	59	xmah24xw5wid	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	2026-08-23 07:20:31.697721+00	2026-08-25 15:18:25.271153+00	6uiwnokptoub	79e4662a-2bfa-4def-b31d-82395a03e844
\.


--
-- Data for Name: saml_providers; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.saml_providers (id, sso_provider_id, entity_id, metadata_xml, metadata_url, attribute_mapping, created_at, updated_at, name_id_format) FROM stdin;
\.


--
-- Data for Name: saml_relay_states; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.saml_relay_states (id, sso_provider_id, request_id, for_email, redirect_to, created_at, updated_at, flow_state_id) FROM stdin;
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.schema_migrations (version) FROM stdin;
20171026211738
20171026211808
20171026211834
20180103212743
20180108183307
20180119214651
20180125194653
00
20210710035447
20210722035447
20210730183235
20210909172000
20210927181326
20211122151130
20211124214934
20211202183645
20220114185221
20220114185340
20220224000811
20220323170000
20220429102000
20220531120530
20220614074223
20220811173540
20221003041349
20221003041400
20221011041400
20221020193600
20221021073300
20221021082433
20221027105023
20221114143122
20221114143410
20221125140132
20221208132122
20221215195500
20221215195800
20221215195900
20230116124310
20230116124412
20230131181311
20230322519590
20230402418590
20230411005111
20230508135423
20230523124323
20230818113222
20230914180801
20231027141322
20231114161723
20231117164230
20240115144230
20240214120130
20240306115329
20240314092811
20240427152123
20240612123726
20240729123726
20240802193726
20240806073726
20241009103726
20250717082212
20250731150234
20250804100000
20250901200500
20250903112500
20250904133000
20250925093508
20251007112900
20251104100000
20251111201300
20251201000000
20260115000000
20260121000000
20260219120000
20260302000000
20260625000000
20260821000000
20260821010000
20260824000000
20260824000001
20260831180000
\.


--
-- Data for Name: scim_tokens; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.scim_tokens (id, sso_provider_id, token_hash, prefix, created_at, expires_at, revoked_at, last_used_at) FROM stdin;
\.


--
-- Data for Name: scim_users; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.scim_users (id, sso_provider_id, user_id, resource, created_at, updated_at, deleted_at) FROM stdin;
\.


--
-- Data for Name: sessions; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.sessions (id, user_id, created_at, updated_at, factor_id, aal, not_after, refreshed_at, user_agent, ip, tag, oauth_client_id, refresh_token_hmac_key, refresh_token_counter, scopes) FROM stdin;
04a237b6-4f75-492e-b472-c7cd8c14784f	323a7849-cfa6-4f19-95a0-2f5f82491436	2026-07-13 08:19:15.067575+00	2026-07-13 08:19:15.067575+00	\N	aal1	\N	\N	node	105.164.128.201	\N	\N	\N	\N	\N
fb810481-40f8-4d15-be68-cf7ae33470f7	323a7849-cfa6-4f19-95a0-2f5f82491436	2026-07-13 08:19:16.406485+00	2026-07-13 08:19:16.406485+00	\N	aal1	\N	\N	node	105.164.128.201	\N	\N	\N	\N	\N
0724b8ef-6b1d-4f1a-9208-3aa9b274e626	0615e227-eeae-4afe-b3e2-0acc74b7c439	2026-09-05 10:59:29.091337+00	2026-09-12 23:37:08.738601+00	\N	aal1	\N	2026-09-12 23:37:08.738457	Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Mobile Safari/537.36	102.207.191.30	\N	\N	\N	\N	\N
b9ac1288-ee2a-47a2-9e84-9c46d9a96996	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	2026-09-22 13:44:20.736536+00	2026-09-22 13:44:20.736536+00	\N	aal1	\N	\N	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36	105.164.128.102	\N	\N	\N	\N	\N
79e4662a-2bfa-4def-b31d-82395a03e844	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	2026-08-04 06:19:47.114682+00	2026-09-22 15:18:18.576103+00	\N	aal1	\N	2026-09-22 15:18:18.575961	Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/153.0.0.0 Safari/537.36	105.164.128.106	\N	\N	\N	\N	\N
8cceb5c3-5124-42d7-b4e9-bf331e27a6af	eebd94c0-8179-4619-a527-218ac9f7d5c4	2026-08-13 05:59:55.012051+00	2026-08-13 13:00:29.045278+00	\N	aal1	\N	2026-08-13 13:00:29.045159	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36	102.216.154.14	\N	\N	\N	\N	\N
84d29128-dcf3-4087-8c43-9939843c58f5	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	2026-08-26 22:38:30.101392+00	2026-08-27 03:25:43.442055+00	\N	aal1	\N	2026-08-27 03:25:43.441895	Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36	102.205.237.234	\N	\N	\N	\N	\N
\.


--
-- Data for Name: sso_domains; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.sso_domains (id, sso_provider_id, domain, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: sso_providers; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.sso_providers (id, resource_id, created_at, updated_at, disabled) FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, invited_at, confirmation_token, confirmation_sent_at, recovery_token, recovery_sent_at, email_change_token_new, email_change, email_change_sent_at, last_sign_in_at, raw_app_meta_data, raw_user_meta_data, is_super_admin, created_at, updated_at, phone, phone_confirmed_at, phone_change, phone_change_token, phone_change_sent_at, email_change_token_current, email_change_confirm_status, banned_until, reauthentication_token, reauthentication_sent_at, is_sso_user, deleted_at, is_anonymous) FROM stdin;
00000000-0000-0000-0000-000000000000	50c6281a-69e0-4c36-a73b-58780a2c8acd	authenticated	authenticated	ghostprompt101@gmail.com	$2a$10$sPky7GdoT3fo.3INEXbliu3tGmpYLpCSAmk9wmqj//Tu3Da7bcQCO	2026-07-20 12:50:01.048146+00	\N		\N		\N			\N	2026-07-20 12:50:01.056122+00	{"provider": "email", "providers": ["email"]}	{"sub": "50c6281a-69e0-4c36-a73b-58780a2c8acd", "email": "ghostprompt101@gmail.com", "phone": "+254712345678", "full_name": "ghost", "email_verified": true, "phone_verified": false}	\N	2026-07-20 12:50:01.009901+00	2026-08-04 06:18:34.700548+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	ce11a1e1-39f2-471e-9c62-483ba6b04780	authenticated	authenticated	wangechi.njeri@babeesplace.demo	$2a$10$EapEhwiV6GiGdZnTO99wu.ihLSSXaO8ur.SfjFBOtdlcSOJHSYZIe	2026-08-03 09:06:28.736812+00	\N		\N		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"phone": "+254733222002", "full_name": "Wangechi Njeri", "email_verified": true}	\N	2026-08-03 08:52:46.551142+00	2026-08-03 09:06:28.740133+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7	authenticated	authenticated	kevin.ochieng@babeesplace.demo	$2a$10$Y.YbcNVKzLYGdBUndVURHe9.bjlC7.0e.CR7U8LwGSU8mG2evtSJ.	2026-08-03 09:06:29.295172+00	\N		\N		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"phone": "+254700333003", "full_name": "Kevin Ochieng", "email_verified": true}	\N	2026-08-03 08:52:47.092466+00	2026-08-03 09:06:29.298115+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	328a2e81-1496-404e-88c4-d7f45b72a1b6	authenticated	authenticated	faith.wambui@babeesplace.demo	$2a$10$sd5vHbFOUgVGG0S23seoCetOudOiEbi.rvujngUd1nMWkQ9pZ3w.e	2026-08-03 09:06:30.041651+00	\N		\N		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"phone": "+254711444004", "full_name": "Faith Wambui", "email_verified": true}	\N	2026-08-03 08:52:47.629518+00	2026-08-03 09:06:30.04482+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	e47efb2a-278c-4420-b294-87a16e9be730	authenticated	authenticated	user1@gmail.com	$2a$10$lk2BMgto4QeIV/zX9q/Ivu9oMx0iBRwHn9.VYdH84FzlM1kPKn6Zu	2026-06-18 09:45:35.503607+00	\N		\N		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"email_verified": true}	\N	2026-06-18 09:45:35.488258+00	2026-06-18 09:45:35.504534+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	a2a071d2-da64-4571-9f17-288c5abd72dc	authenticated	authenticated	james.mutiso@babeesplace.demo	$2a$10$5DK0dC0wBCQtle6N9eGYJ.tILBEdD2Jw3aZO7/wHINltcrkOEF926	2026-08-03 09:06:32.006462+00	\N		\N		\N			\N	2026-08-31 08:01:42.36526+00	{"provider": "email", "providers": ["email"]}	{"phone": "+254700777007", "full_name": "James Mutiso", "email_verified": true}	\N	2026-08-03 08:52:49.23626+00	2026-08-31 08:01:42.367897+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	a9c07a6f-4063-4793-a3a0-129d96a50e02	authenticated	authenticated	mercy.akinyi@babeesplace.demo	$2a$10$72DJs3oa3BfUXUbjLvNda.vp5PDxOEjXv18WpjnRPxyGjFDr8S2oC	2026-08-03 09:06:31.289615+00	\N		\N		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"phone": "+254733666006", "full_name": "Mercy Akinyi", "email_verified": true}	\N	2026-08-03 08:52:48.694581+00	2026-08-03 09:06:31.292886+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	2c68a903-e68d-4f00-8586-d0efc6047b2b	authenticated	authenticated	admin@test.com	$2a$10$cXm1INnm6AYFGBmGGzyaoOKhMPNp3rF7/FrNPdR8zm0ineTy9E.jy	2026-06-18 09:49:40.16397+00	\N		\N		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"email_verified": true}	\N	2026-06-18 09:49:40.150193+00	2026-06-18 09:49:40.16502+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	d32dcbba-ff92-4df5-bb3e-089d16a5141e	authenticated	authenticated	lucy.cherono@babeesplace.demo	$2a$10$UrxMo2C/h2rE5fO66M0pneFKgjbix8bhLb9t8hawqeQcqq73FTYlC	2026-08-03 09:06:32.719528+00	\N		\N		\N			\N	\N	{"provider": "email", "providers": ["email"]}	{"phone": "+254711888008", "full_name": "Lucy Cherono", "email_verified": true}	\N	2026-08-03 08:52:49.766195+00	2026-08-03 09:06:32.722532+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	authenticated	authenticated	samoraedwin101@gmail.com	$2a$10$4DMFnbMvNhRgfteWMIMZa.v/B11Ap9EXBLHbpgkg3VsSm3SYrIVQW	2026-07-13 17:16:51.306135+00	\N		2026-06-22 00:14:14.514282+00		\N			\N	2026-07-13 17:16:51.326925+00	{"provider": "email", "providers": ["email"]}	{"sub": "c1f57dbb-e6f5-4a51-8985-188a6fd3a11b", "email": "samoraedwin101@gmail.com", "email_verified": true, "phone_verified": false}	\N	2026-06-22 00:14:14.469015+00	2026-08-04 05:40:49.494813+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	1f33a52d-a5b9-475a-bf28-857045f4ad09	authenticated	authenticated	daniel.kiprop@babeesplace.demo	$2a$10$YTMP37LoU6eLAn3jsHihKeW4DvtRoamS5ArtYscQpsljw8SgELwM2	2026-08-03 09:06:30.704511+00	\N		\N		\N			\N	2026-08-31 08:06:14.411764+00	{"provider": "email", "providers": ["email"]}	{"phone": "+254722555005", "full_name": "Daniel Kiprop", "email_verified": true}	\N	2026-08-03 08:52:48.164048+00	2026-08-31 08:06:14.415093+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	91877d22-84c1-4253-9e57-13aa5a617b1c	authenticated	authenticated	customer@babeesplace.com	$2a$10$wZoU7SxgCb1HzCxJkVkaCuxXENxKHY8LH8xuabq4gdlJ3lALMvsdW	2026-08-03 09:06:28.042929+00	\N		\N		\N			\N	2026-08-31 08:08:30.565185+00	{"provider": "email", "providers": ["email"]}	{"sub": "91877d22-84c1-4253-9e57-13aa5a617b1c", "email": "customer@babeesplace.com", "phone": "+254722111001", "full_name": "Brian Mwangi", "email_verified": true, "phone_verified": false}	\N	2026-07-13 08:19:55.971985+00	2026-08-31 08:08:30.567892+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	authenticated	authenticated	samoraedwin603@gmail.com	$2a$10$Be2sTzR.5U0MvTukXYx42.aS9ufyslFVwijHynr4pXVAm0HTqIp1q	2026-06-18 18:36:08.357546+00	\N		\N		2026-06-18 22:59:12.38306+00			\N	2026-09-22 13:44:20.733142+00	{"provider": "email", "providers": ["email"]}	{"email_verified": true}	\N	2026-06-18 18:36:08.327503+00	2026-09-22 15:18:18.547535+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	323a7849-cfa6-4f19-95a0-2f5f82491436	authenticated	authenticated	audit-test-1783930754107@example.com	$2a$10$0Xtbr.26Vkt/hWqpu1tKDucytdy7FyMLaOVAYEgILqIbq.HRmtkMi	2026-07-13 08:19:15.059363+00	\N		\N		\N			\N	2026-07-13 08:19:16.406368+00	{"provider": "email", "providers": ["email"]}	{"sub": "323a7849-cfa6-4f19-95a0-2f5f82491436", "email": "audit-test-1783930754107@example.com", "phone": "+254712345678", "full_name": "Audit Test", "email_verified": true, "phone_verified": false}	\N	2026-07-13 08:19:15.011086+00	2026-07-13 08:19:16.409968+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	b98a07b1-467f-4e20-ac14-da354b094637	authenticated	authenticated	admin@babeesplace.com	$2a$10$G6jL8rM4A/EgNqJLfLfaGOvVO8Mu1eOqVqWqOip/GCnm1ZLJ6GvyS	2026-08-03 09:06:26.877034+00	\N		\N		\N			\N	2026-08-31 08:08:31.61114+00	{"provider": "email", "providers": ["email"]}	{"sub": "b98a07b1-467f-4e20-ac14-da354b094637", "email": "admin@babeesplace.com", "phone": "+254712345001", "full_name": "Amina Otieno", "email_verified": true, "phone_verified": false}	\N	2026-07-13 08:19:54.732114+00	2026-08-31 08:08:31.6154+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	eebd94c0-8179-4619-a527-218ac9f7d5c4	authenticated	authenticated	nesambulaz@gmail.com	$2a$10$Jt0lcSCHE/ZnzrVt82kmaunXu7RWpJRMRGBemObpHftg5Pl.w83AO	2026-08-13 05:59:54.995843+00	\N		\N		\N			\N	2026-08-13 05:59:55.011883+00	{"provider": "email", "providers": ["email"]}	{"sub": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "email": "nesambulaz@gmail.com", "phone": "+254740845440", "full_name": "Nestar Ambula", "email_verified": true, "phone_verified": false}	\N	2026-08-13 05:59:54.933498+00	2026-08-13 13:00:29.020871+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	authenticated	authenticated	minyoso@gmail	$2a$10$yrMtuwwiY50En0hlFyZLtuNaqVlHt3EqV2lYa9osjyVzWOKHktQa6	2026-08-13 15:10:24.762335+00	\N		\N		\N			\N	2026-08-26 22:38:30.100643+00	{"provider": "email", "providers": ["email"]}	{"sub": "5a04e47f-c9d3-485b-8b23-3aa74d9d729e", "email": "minyoso@gmail", "phone": "+2547555555555", "full_name": "lillian", "email_verified": true, "phone_verified": false}	\N	2026-08-13 15:10:24.700208+00	2026-08-27 03:25:43.420861+00	\N	\N			\N		0	\N		\N	f	\N	f
00000000-0000-0000-0000-000000000000	0615e227-eeae-4afe-b3e2-0acc74b7c439	authenticated	authenticated	oscaraseka1111@gmail.com	$2a$10$8Jw1eu0p6jpdvITUh01B7u2T4cxbSCBfjZM5QNSoCm1cnl5lhBj9e	2026-09-05 10:59:29.079027+00	\N		\N		\N			\N	2026-09-05 10:59:29.091197+00	{"provider": "email", "providers": ["email"]}	{"sub": "0615e227-eeae-4afe-b3e2-0acc74b7c439", "email": "oscaraseka1111@gmail.com", "phone": "+254712944345", "full_name": "Oscar Aseka", "email_verified": true, "phone_verified": false}	\N	2026-09-05 10:59:29.013885+00	2026-09-12 23:37:08.709934+00	\N	\N			\N		0	\N		\N	f	\N	f
\.


--
-- Data for Name: webauthn_challenges; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.webauthn_challenges (id, user_id, challenge_type, session_data, created_at, expires_at) FROM stdin;
\.


--
-- Data for Name: webauthn_credentials; Type: TABLE DATA; Schema: auth; Owner: -
--

COPY auth.webauthn_credentials (id, user_id, credential_id, public_key, attestation_type, aaguid, sign_count, transports, backup_eligible, backed_up, friendly_name, created_at, updated_at, last_used_at) FROM stdin;
\.


--
-- Data for Name: admin_audit_logs; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.admin_audit_logs (id, actor_id, action, entity_type, entity_id, summary, metadata, ip_hint, created_at) FROM stdin;
d06d5ecc-a64f-4c49-9efb-e94084908b0c	b98a07b1-467f-4e20-ac14-da354b094637	order_payment_updated	order	fc062098-b9c7-459a-bddb-70903a5bf5b2	QA paid	{"qa": true}	\N	2026-08-03 09:52:01.652454+00
6c6fdea7-3f0a-4813-a662-ea3271079048	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order.updated	order	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	Status → confirmed	{"note": "paid", "status": "confirmed"}	\N	2026-08-04 06:28:20.481266+00
1ad380fb-bb10-4268-8c04-00fe4c1d6a5b	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order.updated	order	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	Status → ready_for_pickup	{"note": "paid", "status": "ready_for_pickup"}	\N	2026-08-04 06:28:35.091382+00
082f945f-7067-40f2-b218-d46398805789	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order.updated	order	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	Status → ready_for_pickup	{"note": "paid", "status": "ready_for_pickup"}	\N	2026-08-04 06:28:41.316554+00
9e18304a-bc9f-43a0-ac43-f62e5c8d93d3	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order.updated	order	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	Status → delivered	{"note": "paid", "status": "delivered"}	\N	2026-08-04 06:28:48.381341+00
\.


--
-- Data for Name: cart_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.cart_items (id, user_id, product_id, quantity, created_at) FROM stdin;
1ae5d6ac-04cc-46c7-af67-10ffee00a6ae	0615e227-eeae-4afe-b3e2-0acc74b7c439	a2000000-0000-4000-8000-000000000048	1	2026-09-12 23:37:53.134262
0913f85d-43f9-4378-b2c9-51f818c64094	50c6281a-69e0-4c36-a73b-58780a2c8acd	8638477e-f5a6-4c64-ae48-0743947ca67c	1	2026-07-20 12:50:29.811636
\.


--
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.categories (id, name, slug, created_at) FROM stdin;
a1000000-0000-4000-8000-000000000001	Fashion	fashion	2026-06-24 09:06:33.153
a1000000-0000-4000-8000-000000000002	Electronics	electronics	2026-06-24 09:06:33.153
a1000000-0000-4000-8000-000000000003	Home & Living	home-living	2026-06-24 09:06:33.153
a1000000-0000-4000-8000-000000000004	Toys & Kids	toys-kids	2026-06-24 09:06:33.153
a1000000-0000-4000-8000-000000000005	Beauty & Accessories	beauty-accessories	2026-06-24 09:06:33.153
\.


--
-- Data for Name: coupon_redemptions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.coupon_redemptions (id, coupon_id, user_id, order_id, discount_amount, created_at) FROM stdin;
ca108a6d-d791-4180-b80b-8d795b025f9c	4d419b94-7430-4bc7-bb72-e8ff0db0c644	91877d22-84c1-4253-9e57-13aa5a617b1c	fc062098-b9c7-459a-bddb-70903a5bf5b2	143.50	2026-08-03 09:51:54.352147+00
f6d6ccfd-e734-450d-9941-35128cee3308	9411038b-a789-48a2-acaa-5f57bac1b33c	91877d22-84c1-4253-9e57-13aa5a617b1c	0b01e434-5c12-4302-97c6-13910a84bf8e	0.00	2026-08-03 09:51:58.936228+00
036a83ca-e1e7-4093-8a28-09853c60858c	b1438f0a-4d47-4e2e-af1e-f43944ea231b	a2a071d2-da64-4571-9f17-288c5abd72dc	42db9ff7-2c64-4a03-8dce-f468db78d39a	200.00	2026-08-31 08:01:46.861171+00
b7c01f0a-1806-4bc7-9361-5f7c7c1184dd	9411038b-a789-48a2-acaa-5f57bac1b33c	a2a071d2-da64-4571-9f17-288c5abd72dc	f0f39871-54d9-4d80-9d91-9c5797386384	0.00	2026-08-31 08:01:48.675828+00
0643f471-a383-4c49-a6a0-806b462ee37a	4d419b94-7430-4bc7-bb72-e8ff0db0c644	1f33a52d-a5b9-475a-bf28-857045f4ad09	9a5dae2b-0b91-49fd-8ed2-a787e9a2d571	433.50	2026-08-31 08:06:15.826436+00
\.


--
-- Data for Name: coupons; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.coupons (id, code, name, description, discount_type, percent_off, amount_off, free_delivery, min_order_amount, max_discount_amount, usage_limit, usage_count, per_user_limit, is_one_time, is_active, starts_at, ends_at, promotion_id, created_at, updated_at) FROM stdin;
b1438f0a-4d47-4e2e-af1e-f43944ea231b	SAVE200	Save 200 KES	Fixed amount off	fixed	\N	200.00	f	1000.00	\N	500	1	2	f	t	2026-08-02 09:39:54.768035+00	2027-08-03 09:39:54.768035+00	\N	2026-08-03 09:39:54.768035+00	2026-08-31 08:01:46.861171+00
9411038b-a789-48a2-acaa-5f57bac1b33c	FREESHIP	Free delivery	Waives delivery fee	free_delivery	\N	\N	f	0.00	\N	\N	2	5	f	t	2026-08-02 09:39:54.768035+00	2027-08-03 09:39:54.768035+00	\N	2026-08-03 09:39:54.768035+00	2026-08-31 08:01:48.675828+00
4d419b94-7430-4bc7-bb72-e8ff0db0c644	WELCOME15	Welcome 15% off	New customer coupon	percentage	15.00	\N	f	500.00	\N	1000	2	1	f	t	2026-08-02 09:39:54.768035+00	2027-08-03 09:39:54.768035+00	\N	2026-08-03 09:39:54.768035+00	2026-08-31 08:06:15.826436+00
\.


--
-- Data for Name: customer_addresses; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customer_addresses (id, user_id, label, recipient_name, phone, county, town, street_address, additional_directions, is_default, created_at, updated_at) FROM stdin;
a4000000-0000-4000-8000-000000000001	91877d22-84c1-4253-9e57-13aa5a617b1c	home	Brian Mwangi	+254722111001	Nairobi	Kilimani	Argwings Kodhek Rd, Court 12 Apt B3	Gate code 4412	t	2026-08-03 08:54:24.165887+00	2026-08-03 09:06:35.213011+00
a4000000-0000-4000-8000-000000000002	ce11a1e1-39f2-471e-9c62-483ba6b04780	home	Wangechi Njeri	+254733222002	Nairobi	South B	Mukoma Road, House 7	\N	t	2026-08-03 08:54:24.626799+00	2026-08-03 09:06:36.021277+00
a4000000-0000-4000-8000-000000000003	ce11a1e1-39f2-471e-9c62-483ba6b04780	work	Wangechi Njeri	+254733222002	Nairobi	Upper Hill	Hospital Road, Suite 4	Reception will hold packages	f	2026-08-03 08:54:24.626799+00	2026-08-03 09:06:36.021277+00
a4000000-0000-4000-8000-000000000004	ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7	home	Kevin Ochieng	+254700333003	Kiambu	Ruiru	Eastern Bypass, Greenview Estate Block C	Ask for plot 18	t	2026-08-03 08:54:25.070648+00	2026-08-03 09:06:36.73207+00
a4000000-0000-4000-8000-000000000005	328a2e81-1496-404e-88c4-d7f45b72a1b6	home	Faith Wambui	+254711444004	Nairobi	Westlands	Ring Road Parklands, Flat 9A	\N	t	2026-08-03 08:54:25.498398+00	2026-08-03 09:06:37.248627+00
a4000000-0000-4000-8000-000000000006	1f33a52d-a5b9-475a-bf28-857045f4ad09	home	Daniel Kiprop	+254722555005	Nairobi	Lavington	James Gichuru Road, Villa 3	Security will call	t	2026-08-03 08:54:25.931218+00	2026-08-03 09:06:37.960782+00
a4000000-0000-4000-8000-000000000007	a9c07a6f-4063-4793-a3a0-129d96a50e02	home	Mercy Akinyi	+254733666006	Kajiado	Kitengela	Namanga Road, Acacia Courts	Unit 22	t	2026-08-03 08:54:26.397951+00	2026-08-03 09:06:38.585049+00
a4000000-0000-4000-8000-000000000008	a2a071d2-da64-4571-9f17-288c5abd72dc	other	James Mutiso	+254700777007	Nairobi	Eastleigh	1st Avenue, Shopfront collection	Prefer evening delivery	t	2026-08-03 08:54:26.85042+00	2026-08-03 09:06:39.0995+00
a4000000-0000-4000-8000-000000000009	d32dcbba-ff92-4df5-bb3e-089d16a5141e	home	Lucy Cherono	+254711888008	Nairobi	Karen	Bogani Road, Cottage 5	\N	t	2026-08-03 08:54:27.345405+00	2026-08-03 09:06:39.66714+00
\.


--
-- Data for Name: customer_preferences; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.customer_preferences (user_id, preferred_fulfillment, preferred_pickup_location_id, marketing_emails, sms_notifications, created_at, updated_at, email_notifications, order_updates, payment_updates) FROM stdin;
91877d22-84c1-4253-9e57-13aa5a617b1c	delivery	\N	t	f	2026-08-03 08:54:24.402525+00	2026-08-03 09:06:35.739451+00	t	t	t
ce11a1e1-39f2-471e-9c62-483ba6b04780	delivery	\N	t	f	2026-08-03 08:54:24.856659+00	2026-08-03 09:06:36.384377+00	t	t	t
ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7	delivery	\N	t	f	2026-08-03 08:54:25.29477+00	2026-08-03 09:06:36.961793+00	t	t	t
328a2e81-1496-404e-88c4-d7f45b72a1b6	delivery	\N	t	t	2026-08-03 08:54:25.718098+00	2026-08-03 09:06:37.69046+00	t	t	t
1f33a52d-a5b9-475a-bf28-857045f4ad09	delivery	\N	t	f	2026-08-03 08:54:26.194896+00	2026-08-03 09:06:38.25938+00	t	t	t
a9c07a6f-4063-4793-a3a0-129d96a50e02	delivery	\N	t	t	2026-08-03 08:54:26.620598+00	2026-08-03 09:06:38.822131+00	t	t	t
a2a071d2-da64-4571-9f17-288c5abd72dc	pickup	a3000000-0000-4000-8000-000000000001	t	f	2026-08-03 08:54:27.121372+00	2026-08-03 09:06:39.42151+00	t	t	t
d32dcbba-ff92-4df5-bb3e-089d16a5141e	pickup	a3000000-0000-4000-8000-000000000001	t	f	2026-08-03 08:54:27.573847+00	2026-08-03 09:06:40.042625+00	t	t	t
\.


--
-- Data for Name: gift_card_transactions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.gift_card_transactions (id, gift_card_id, user_id, order_id, tx_type, amount, balance_after, created_at) FROM stdin;
c6a7f246-6428-4227-bc37-10da15942b21	1c347475-1322-4b9a-b0b5-250fdcc0fb71	91877d22-84c1-4253-9e57-13aa5a617b1c	fc062098-b9c7-459a-bddb-70903a5bf5b2	redeem	20.00	30.00	2026-08-03 09:51:54.352147+00
\.


--
-- Data for Name: gift_cards; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.gift_cards (id, code, initial_balance, balance, currency, status, purchased_by, recipient_email, expires_at, created_at, updated_at) FROM stdin;
1b0301b8-3afc-46c5-84e9-ac6554890995	GIFT1000	1000.00	1000.00	KES	active	\N	\N	2027-08-03 09:39:54.768035+00	2026-08-03 09:39:54.768035+00	2026-08-03 09:39:54.768035+00
1c347475-1322-4b9a-b0b5-250fdcc0fb71	QA_GIFT_S2	50.00	30.00	KES	active	\N	\N	\N	2026-08-03 09:48:58.791933+00	2026-08-03 09:51:54.352147+00
\.


--
-- Data for Name: loyalty_accounts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.loyalty_accounts (user_id, points_balance, lifetime_earned, lifetime_redeemed, referral_code, tier, created_at, updated_at) FROM stdin;
b98a07b1-467f-4e20-ac14-da354b094637	0	0	0	355F42ED	member	2026-08-03 09:51:53.039132+00	2026-08-03 09:51:53.039132+00
91877d22-84c1-4253-9e57-13aa5a617b1c	157	257	100	DF60E248	member	2026-08-03 09:49:04.127243+00	2026-08-03 09:51:54.595048+00
c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	27	27	0	1C181DE2	member	2026-08-03 10:07:53.626097+00	2026-08-04 05:43:35.429028+00
7d487b08-c6f1-4726-a23b-cbb9f7647cbd	56	56	0	034AA906	member	2026-08-04 06:24:56.914922+00	2026-08-04 06:25:15.464617+00
eebd94c0-8179-4619-a527-218ac9f7d5c4	58	58	0	C48D0DA8	member	2026-08-13 05:59:56.586124+00	2026-08-13 13:08:22.80537+00
5a04e47f-c9d3-485b-8b23-3aa74d9d729e	37	37	0	CE1777CA	member	2026-08-13 15:10:27.402584+00	2026-08-13 15:11:46.911756+00
0615e227-eeae-4afe-b3e2-0acc74b7c439	0	0	0	85C2159A	member	2026-09-05 10:59:31.055116+00	2026-09-05 10:59:31.055116+00
\.


--
-- Data for Name: loyalty_rules; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.loyalty_rules (id, code, name, is_active, earn_points_per_currency, redeem_points_per_currency, free_delivery_points, min_redeem_points, max_redeem_percent, metadata, created_at, updated_at) FROM stdin;
84e2b99b-3dd0-4870-9421-dab8c8c62677	default	Default loyalty rules	t	0.0100	10.0000	500	100	50.00	{}	2026-08-03 09:39:54.768035+00	2026-08-03 09:39:54.768035+00
\.


--
-- Data for Name: loyalty_transactions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.loyalty_transactions (id, user_id, tx_type, points, balance_after, order_id, description, metadata, created_at) FROM stdin;
cc7b15d6-5a81-44a8-b03e-68449d394cd5	91877d22-84c1-4253-9e57-13aa5a617b1c	earn_purchase	10	10	fed1e53b-9c95-4d88-96b8-579367bb356c	Points earned from order	{}	2026-08-03 09:49:04.127243+00
1df1631b-a41a-4232-8a01-b52c8f16a7fe	91877d22-84c1-4253-9e57-13aa5a617b1c	redeem_discount	-100	150	fc062098-b9c7-459a-bddb-70903a5bf5b2	Redeemed at checkout	{}	2026-08-03 09:51:54.352147+00
1a2ea9ce-6187-4e6f-8591-5a735393c259	91877d22-84c1-4253-9e57-13aa5a617b1c	earn_purchase	7	157	fc062098-b9c7-459a-bddb-70903a5bf5b2	Points earned from order	{}	2026-08-03 09:51:54.595048+00
e10ece57-d429-42e1-987e-4292e0fca07b	c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	earn_purchase	27	27	a362d405-d226-4115-80f6-505fb3b49c21	Points earned from order	{}	2026-08-04 05:43:35.429028+00
0f883fd2-cc41-4e4c-a82d-93560f794ce0	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	earn_purchase	56	56	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	Points earned from order	{}	2026-08-04 06:25:15.464617+00
c62fb8d6-176c-4f14-83e2-122082b5c599	eebd94c0-8179-4619-a527-218ac9f7d5c4	earn_purchase	30	30	21ce8844-157e-4cd8-9e93-2c4d20256a76	Points earned from order	{}	2026-08-13 13:04:33.901031+00
28472552-fb12-4c5f-b903-77c12b12ad66	eebd94c0-8179-4619-a527-218ac9f7d5c4	earn_purchase	28	58	0fd23557-0657-4851-921a-ea57514435d3	Points earned from order	{}	2026-08-13 13:08:22.80537+00
63e4b204-48e9-482e-8897-f035640a862d	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	earn_purchase	37	37	f85d863c-b81e-49e9-8451-7980551af330	Points earned from order	{}	2026-08-13 15:11:46.911756+00
\.


--
-- Data for Name: notification_deliveries; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notification_deliveries (id, notification_id, user_id, event_type, channel, provider, status, retry_count, max_retries, external_id, error_message, payload, response, scheduled_at, sent_at, created_at, updated_at) FROM stdin;
fab1386e-2af8-42b9-bece-a0c73521c756	fe60e998-b297-4de9-8c98-7962646c52cc	c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	order_created	in_app	in_app	sent	0	3	\N	\N	{"body": "Order A362D405 was placed successfully. Total: 2727 KES.", "link": "/orders/a362d405-d226-4115-80f6-505fb3b49c21", "title": "Order A362D405 placed"}	{}	\N	2026-08-04 05:43:35.652+00	2026-08-04 05:43:35.775439+00	2026-08-04 05:43:35.775439+00
b1c14103-4d46-42ed-9c59-444434af1971	14fad145-01c3-4a8b-837c-5848c0273048	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order_created	in_app	in_app	sent	0	3	\N	\N	{"body": "Order AC2C4DAE was placed successfully. Total: 5661 KES.", "link": "/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "title": "Order AC2C4DAE placed"}	{}	\N	2026-08-04 06:25:15.772+00	2026-08-04 06:25:16.136639+00	2026-08-04 06:25:16.136639+00
08160395-7165-4aee-88aa-2f7012b38d09	d05bda9f-9bd5-4b02-a6fe-7e7294156005	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order_confirmed	in_app	in_app	sent	0	3	\N	\N	{"body": "Order AC2C4DAE has been confirmed and is being prepared.", "link": "/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "title": "Order AC2C4DAE confirmed"}	{}	\N	2026-08-04 06:28:21.475+00	2026-08-04 06:28:21.6105+00	2026-08-04 06:28:21.6105+00
176c14af-2693-438b-9ecf-f0963e4867f5	713d4a85-9883-47ae-8c7f-5e6b494d6beb	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order_ready_for_pickup	in_app	in_app	sent	0	3	\N	\N	{"body": "Order AC2C4DAE is ready for pickup at your selected boutique.", "link": "/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "title": "Order AC2C4DAE ready"}	{}	\N	2026-08-04 06:28:35.777+00	2026-08-04 06:28:35.911824+00	2026-08-04 06:28:35.911824+00
735e6a72-8954-4f73-a35c-35799bca4625	a17c9d7a-98c5-4a78-833c-d97a009912b6	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order_ready_for_pickup	in_app	in_app	sent	0	3	\N	\N	{"body": "Order AC2C4DAE is ready for pickup at your selected boutique.", "link": "/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "title": "Order AC2C4DAE ready"}	{}	\N	2026-08-04 06:28:42.363+00	2026-08-04 06:28:42.502143+00	2026-08-04 06:28:42.502143+00
dad915d4-b5ab-4ca0-9530-a9d9e6703bf6	057ecc10-b32b-4a7b-bff2-f7954537dcbb	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	delivered	in_app	in_app	sent	0	3	\N	\N	{"body": "Order AC2C4DAE has been delivered. Enjoy!", "link": "/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "title": "Order AC2C4DAE delivered"}	{}	\N	2026-08-04 06:28:49.345+00	2026-08-04 06:28:49.487261+00	2026-08-04 06:28:49.487261+00
fd190758-ca11-4cc6-a793-19331a6c39bf	3108d976-2fbd-4271-ae8a-d8895a4997a0	eebd94c0-8179-4619-a527-218ac9f7d5c4	welcome	in_app	in_app	sent	0	3	\N	\N	{"body": "welcome", "link": "/notifications", "title": "Welcome to Babees Place"}	{}	\N	2026-08-13 05:59:57.028+00	2026-08-13 05:59:57.211102+00	2026-08-13 05:59:57.211102+00
13379c8a-6885-4bbf-98a9-335405d49e62	d185cece-d9e4-4186-ab97-19a7dec54f5a	eebd94c0-8179-4619-a527-218ac9f7d5c4	account_registration	in_app	in_app	sent	0	3	\N	\N	{"body": "Welcome to Babees Place, Nestar Ambula! Your account is ready.", "link": "/notifications", "title": "Welcome aboard"}	{}	\N	2026-08-13 05:59:57.477+00	2026-08-13 05:59:57.661898+00	2026-08-13 05:59:57.661898+00
761a53c1-6f82-4caa-9661-989034e4002a	f5da43ca-cdeb-455c-a1e4-021ceac6d0f9	eebd94c0-8179-4619-a527-218ac9f7d5c4	order_created	in_app	in_app	sent	0	3	\N	\N	{"body": "Order 21CE8844 was placed successfully. Total: 3062 KES.", "link": "/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76", "title": "Order 21CE8844 placed"}	{}	\N	2026-08-13 13:04:30.483+00	2026-08-13 13:04:30.702474+00	2026-08-13 13:04:30.702474+00
295195f1-dddc-4326-bbe0-b10c5fa79008	2c3a2f3c-11ee-48b4-a7ab-d01cbd84b4c4	eebd94c0-8179-4619-a527-218ac9f7d5c4	payment_initiated	in_app	in_app	sent	0	3	\N	\N	{"body": "Payment of 3062 KES initiated for order 21CE8844. Check your phone for M-Pesa.", "link": "/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76", "title": "Payment initiated"}	{}	\N	2026-08-13 13:04:31.45+00	2026-08-13 13:04:31.3903+00	2026-08-13 13:04:31.3903+00
22378aff-4dcc-44ca-b642-f391f39d7429	4c11a47e-ecc6-4d5e-b425-392a991e65fb	eebd94c0-8179-4619-a527-218ac9f7d5c4	payment_successful	in_app	in_app	sent	0	3	\N	\N	{"body": "Payment received for order 21CE8844. Receipt: MOCK26273387.", "link": "/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76", "title": "Payment successful"}	{}	\N	2026-08-13 13:04:34.66+00	2026-08-13 13:04:34.616549+00	2026-08-13 13:04:34.616549+00
a4667131-4f00-4974-b5c7-0024c76a6b1b	c5d046c3-f6c6-4a5e-93a5-219f99ff90d1	eebd94c0-8179-4619-a527-218ac9f7d5c4	order_created	in_app	in_app	sent	0	3	\N	\N	{"body": "Order 0FD23557 was placed successfully. Total: 2862 KES.", "link": "/orders/0fd23557-0657-4851-921a-ea57514435d3", "title": "Order 0FD23557 placed"}	{}	\N	2026-08-13 13:08:23.071+00	2026-08-13 13:08:23.0184+00	2026-08-13 13:08:23.0184+00
3f6949de-d463-4def-819d-79be726679a8	6ab3a602-3862-467f-8f43-da6b1804e16a	eebd94c0-8179-4619-a527-218ac9f7d5c4	order_cancelled	in_app	in_app	sent	0	3	\N	\N	{"body": "Order 0FD23557 has been cancelled.", "link": "/orders/0fd23557-0657-4851-921a-ea57514435d3", "title": "Order 0FD23557 cancelled"}	{}	\N	2026-08-13 13:10:16.37+00	2026-08-13 13:10:16.320606+00	2026-08-13 13:10:16.320606+00
7252c638-b4bc-4526-ac71-7939f721b91c	0467b158-ee96-4e43-9be0-e87c61bfe02b	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	account_registration	in_app	in_app	sent	0	3	\N	\N	{"body": "Welcome to Babees Place, lillian! Your account is ready.", "link": "/notifications", "title": "Welcome aboard"}	{}	\N	2026-08-13 15:10:26.973+00	2026-08-13 15:10:28.342425+00	2026-08-13 15:10:28.342425+00
def3c79d-a8f0-4576-a1ef-050b9ace8af1	d8e82122-051a-40c0-a94b-b49f2a762b31	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	welcome	in_app	in_app	sent	0	3	\N	\N	{"body": "welcome", "link": "/notifications", "title": "Welcome to Babees Place"}	{}	\N	2026-08-13 15:10:26.993+00	2026-08-13 15:10:28.364971+00	2026-08-13 15:10:28.364971+00
c5bd7b86-6c56-4716-a274-6c21eb7dd2b1	23b4f10c-b9e8-4621-915a-3349fbf65881	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	order_created	in_app	in_app	sent	0	3	\N	\N	{"body": "Order F85D863C was placed successfully. Total: 3753 KES.", "link": "/orders/f85d863c-b81e-49e9-8451-7980551af330", "title": "Order F85D863C placed"}	{}	\N	2026-08-13 15:11:45.763+00	2026-08-13 15:11:47.220665+00	2026-08-13 15:11:47.220665+00
837847e7-edb1-4b5f-8302-6ac9275ceede	0ab6c42b-b8c9-463e-8060-2a5523f6a074	0615e227-eeae-4afe-b3e2-0acc74b7c439	welcome	in_app	in_app	sent	0	3	\N	\N	{"body": "welcome", "link": "/notifications", "title": "Welcome to Babees Place"}	{}	\N	2026-09-05 10:59:32.3+00	2026-09-05 10:59:32.555364+00	2026-09-05 10:59:32.555364+00
98638ff2-410d-469f-88bd-d9237e9551d8	9466dd33-195d-4bbc-8484-36bc817854a1	0615e227-eeae-4afe-b3e2-0acc74b7c439	account_registration	in_app	in_app	sent	0	3	\N	\N	{"body": "Welcome to Babees Place, Oscar Aseka! Your account is ready.", "link": "/notifications", "title": "Welcome aboard"}	{}	\N	2026-09-05 10:59:32.526+00	2026-09-05 10:59:32.683695+00	2026-09-05 10:59:32.683695+00
\.


--
-- Data for Name: notification_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notification_events (id, event_type, user_id, payload, result, created_at) FROM stdin;
fc108ee5-f353-4937-b504-558b5a787afe	order_created	91877d22-84c1-4253-9e57-13aa5a617b1c	{"orderId": "fc062098-b9c7-459a-bddb-70903a5bf5b2"}	{}	2026-08-03 09:51:54.838115+00
01f0d960-58f1-42a1-a8cc-2462adc01f3f	admin_new_order	\N	{"vars": {"name": "there", "stock": "", "amount": "2727", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "A362D405", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "amount": 2727, "orderId": "a362d405-d226-4115-80f6-505fb3b49c21", "currency": "KES", "notifyAdmins": true, "paymentMethod": "cod"}	{}	2026-08-04 05:43:34.88742+00
74d7fff5-9cb9-4aac-acbc-04e97c9d559b	order_created	c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	{"vars": {"name": "there", "stock": "", "amount": "2727", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "A362D405", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "amount": 2727, "userId": "c1f57dbb-e6f5-4a51-8985-188a6fd3a11b", "orderId": "a362d405-d226-4115-80f6-505fb3b49c21", "currency": "KES", "paymentMethod": "cod"}	{}	2026-08-04 05:43:34.896741+00
9b2e062e-c39c-4f03-b0e5-c8b57e97c464	admin_new_order.result	\N	{"amount": 2727, "orderId": "a362d405-d226-4115-80f6-505fb3b49c21", "currency": "KES", "notifyAdmins": true, "paymentMethod": "cod"}	{"eventType": "admin_new_order", "adminCount": 3, "deliveries": [], "notifications": []}	2026-08-04 05:43:35.438423+00
78df1bbe-52df-48ce-96d0-454ba987010e	order_created.result	c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	{"amount": 2727, "userId": "c1f57dbb-e6f5-4a51-8985-188a6fd3a11b", "orderId": "a362d405-d226-4115-80f6-505fb3b49c21", "currency": "KES", "paymentMethod": "cod"}	{"eventType": "order_created", "adminCount": 0, "deliveries": [{"reason": "missing_recipient", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "fe60e998-b297-4de9-8c98-7962646c52cc", "body": "Order A362D405 was placed successfully. Total: 2727 KES.", "link": "/orders/a362d405-d226-4115-80f6-505fb3b49c21", "title": "Order A362D405 placed", "readAt": null, "status": "unread", "userId": "c1f57dbb-e6f5-4a51-8985-188a6fd3a11b", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "a362d405-d226-4115-80f6-505fb3b49c21", "eventType": "order_created"}, "createdAt": "2026-08-04T05:43:35.556603+00:00", "eventType": "order_created", "updatedAt": "2026-08-04T05:43:35.556603+00:00", "archivedAt": null}]}	2026-08-04 05:43:35.982631+00
a38e9b54-8a64-425b-b359-3c4b70384d08	order_created	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{"vars": {"name": "there", "stock": "", "amount": "5661", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "AC2C4DAE", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "amount": 5661, "userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "currency": "KES", "paymentMethod": "cod"}	{}	2026-08-04 06:25:14.83803+00
ea9224a0-c400-4e32-b6db-c363916babf9	admin_new_order	\N	{"vars": {"name": "there", "stock": "", "amount": "5661", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "AC2C4DAE", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "amount": 5661, "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "currency": "KES", "notifyAdmins": true, "paymentMethod": "cod"}	{}	2026-08-04 06:25:14.83463+00
8c2859f6-e9d1-412f-ab10-a839e330cad2	admin_new_order.result	\N	{"amount": 5661, "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "currency": "KES", "notifyAdmins": true, "paymentMethod": "cod"}	{"eventType": "admin_new_order", "adminCount": 3, "deliveries": [], "notifications": []}	2026-08-04 06:25:15.521044+00
5f4f5aa4-c9ff-4300-863b-de52bf2d7d89	order_created.result	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{"amount": 5661, "userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "currency": "KES", "paymentMethod": "cod"}	{"eventType": "order_created", "adminCount": 0, "deliveries": [{"reason": "missing_recipient", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "14fad145-01c3-4a8b-837c-5848c0273048", "body": "Order AC2C4DAE was placed successfully. Total: 5661 KES.", "link": "/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "title": "Order AC2C4DAE placed", "readAt": null, "status": "unread", "userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "order_created"}, "createdAt": "2026-08-04T06:25:15.586153+00:00", "eventType": "order_created", "updatedAt": "2026-08-04T06:25:15.586153+00:00", "archivedAt": null}]}	2026-08-04 06:25:16.490664+00
075e0332-c02b-452d-812e-1fc53e8431b4	order_confirmed	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{"vars": {"name": "there", "stock": "", "amount": "", "currency": "KES", "location": "your selected boutique", "reset_link": "#", "verify_link": "#", "order_number": "AC2C4DAE", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "location": "your selected boutique"}	{}	2026-08-04 06:28:20.406254+00
dd21b9ef-c974-47c6-9e00-d92083bab6a8	order_confirmed.result	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{"userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "location": "your selected boutique"}	{"eventType": "order_confirmed", "adminCount": 0, "deliveries": [{"reason": "no_template", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "d05bda9f-9bd5-4b02-a6fe-7e7294156005", "body": "Order AC2C4DAE has been confirmed and is being prepared.", "link": "/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "title": "Order AC2C4DAE confirmed", "readAt": null, "status": "unread", "userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "order_confirmed"}, "createdAt": "2026-08-04T06:28:21.135059+00:00", "eventType": "order_confirmed", "updatedAt": "2026-08-04T06:28:21.135059+00:00", "archivedAt": null}]}	2026-08-04 06:28:21.914548+00
afa963c6-dfbd-49ef-a29b-62833bef2343	order_ready_for_pickup	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{"vars": {"name": "there", "stock": "", "amount": "", "currency": "KES", "location": "your selected boutique", "reset_link": "#", "verify_link": "#", "order_number": "AC2C4DAE", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "location": "your selected boutique"}	{}	2026-08-04 06:28:35.085708+00
90e40763-70df-4dca-b542-107612a3cce1	order_created	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"vars": {"name": "there", "stock": "", "amount": "3062", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "21CE8844", "product_name": "Product", "payment_method": "mpesa", "receipt_number": "—"}, "amount": 3062, "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "currency": "KES", "paymentMethod": "mpesa"}	{}	2026-08-13 13:04:29.656946+00
4babd6a8-cbac-4529-95ec-86199e2a7e8b	order_ready_for_pickup.result	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{"userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "location": "your selected boutique"}	{"eventType": "order_ready_for_pickup", "adminCount": 0, "deliveries": [{"reason": "no_template", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "713d4a85-9883-47ae-8c7f-5e6b494d6beb", "body": "Order AC2C4DAE is ready for pickup at your selected boutique.", "link": "/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "title": "Order AC2C4DAE ready", "readAt": null, "status": "unread", "userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "order_ready_for_pickup"}, "createdAt": "2026-08-04T06:28:35.643768+00:00", "eventType": "order_ready_for_pickup", "updatedAt": "2026-08-04T06:28:35.643768+00:00", "archivedAt": null}]}	2026-08-04 06:28:36.177869+00
9cd60d6f-8255-4399-88ac-d947a120f51d	order_ready_for_pickup	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{"vars": {"name": "there", "stock": "", "amount": "", "currency": "KES", "location": "your selected boutique", "reset_link": "#", "verify_link": "#", "order_number": "AC2C4DAE", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "location": "your selected boutique"}	{}	2026-08-04 06:28:41.315782+00
32b64b01-fd1c-49f6-b7be-6865a67faab8	order_ready_for_pickup.result	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{"userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "location": "your selected boutique"}	{"eventType": "order_ready_for_pickup", "adminCount": 0, "deliveries": [{"reason": "no_template", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "a17c9d7a-98c5-4a78-833c-d97a009912b6", "body": "Order AC2C4DAE is ready for pickup at your selected boutique.", "link": "/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "title": "Order AC2C4DAE ready", "readAt": null, "status": "unread", "userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "order_ready_for_pickup"}, "createdAt": "2026-08-04T06:28:42.011935+00:00", "eventType": "order_ready_for_pickup", "updatedAt": "2026-08-04T06:28:42.011935+00:00", "archivedAt": null}]}	2026-08-04 06:28:42.912186+00
126849b0-01dd-4631-b174-9e74402557d5	delivered	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{"vars": {"name": "there", "stock": "", "amount": "", "currency": "KES", "location": "your selected boutique", "reset_link": "#", "verify_link": "#", "order_number": "AC2C4DAE", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "location": "your selected boutique"}	{}	2026-08-04 06:28:48.369465+00
75713658-9348-41ed-9ef7-33bc3025cae3	delivered.result	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{"userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "location": "your selected boutique"}	{"eventType": "delivered", "adminCount": 0, "deliveries": [{"reason": "no_template", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "057ecc10-b32b-4a7b-bff2-f7954537dcbb", "body": "Order AC2C4DAE has been delivered. Enjoy!", "link": "/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "title": "Order AC2C4DAE delivered", "readAt": null, "status": "unread", "userId": "7d487b08-c6f1-4726-a23b-cbb9f7647cbd", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "delivered"}, "createdAt": "2026-08-04T06:28:49.166376+00:00", "eventType": "delivered", "updatedAt": "2026-08-04T06:28:49.166376+00:00", "archivedAt": null}]}	2026-08-04 06:28:49.783923+00
f6973bb4-5574-4aa8-87eb-01bf7dfdf5ba	account_registration	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"name": "Nestar Ambula", "vars": {"name": "Nestar Ambula", "stock": "", "amount": "", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "—", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "email": "nesambulaz@gmail.com", "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4"}	{}	2026-08-13 05:59:56.277574+00
246fffeb-2476-4a74-a6b8-11517a822fae	welcome	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"name": "Nestar Ambula", "vars": {"name": "Nestar Ambula", "stock": "", "amount": "", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "—", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "email": "nesambulaz@gmail.com", "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4"}	{}	2026-08-13 05:59:56.29148+00
8d032bb9-9efd-4902-9226-3e1678e41232	welcome.result	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"name": "Nestar Ambula", "email": "nesambulaz@gmail.com", "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4"}	{"eventType": "welcome", "adminCount": 0, "deliveries": [{"reason": "preference", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "3108d976-2fbd-4271-ae8a-d8895a4997a0", "body": "welcome", "link": "/notifications", "title": "Welcome to Babees Place", "readAt": null, "status": "unread", "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": null, "eventType": "welcome"}, "createdAt": "2026-08-13T05:59:56.94524+00:00", "eventType": "welcome", "updatedAt": "2026-08-13T05:59:56.94524+00:00", "archivedAt": null}]}	2026-08-13 05:59:57.467651+00
b0c1f059-7c40-4e32-a001-b3e410118b0e	account_registration.result	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"name": "Nestar Ambula", "email": "nesambulaz@gmail.com", "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4"}	{"eventType": "account_registration", "adminCount": 0, "deliveries": [{"reason": "no_template", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "d185cece-d9e4-4186-ab97-19a7dec54f5a", "body": "Welcome to Babees Place, Nestar Ambula! Your account is ready.", "link": "/notifications", "title": "Welcome aboard", "readAt": null, "status": "unread", "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": null, "eventType": "account_registration"}, "createdAt": "2026-08-13T05:59:57.360293+00:00", "eventType": "account_registration", "updatedAt": "2026-08-13T05:59:57.360293+00:00", "archivedAt": null}]}	2026-08-13 05:59:57.892771+00
3af0538c-79e1-40d2-a205-f19661857caf	admin_new_order	\N	{"vars": {"name": "there", "stock": "", "amount": "3062", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "21CE8844", "product_name": "Product", "payment_method": "mpesa", "receipt_number": "—"}, "amount": 3062, "orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "currency": "KES", "notifyAdmins": true, "paymentMethod": "mpesa"}	{}	2026-08-13 13:04:29.652262+00
ea5e02c5-474d-453e-8d6e-87a1184831e6	admin_new_order.result	\N	{"amount": 3062, "orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "currency": "KES", "notifyAdmins": true, "paymentMethod": "mpesa"}	{"eventType": "admin_new_order", "adminCount": 3, "deliveries": [], "notifications": []}	2026-08-13 13:04:30.164105+00
3da10b89-301d-41ba-b4ad-f396e1bd17ea	payment_initiated	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"vars": {"name": "there", "stock": "", "amount": "3062", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "21CE8844", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "phone": "254740845440", "amount": 3062, "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "currency": "KES"}	{}	2026-08-13 13:04:30.697138+00
b78ba4de-4007-4a20-898d-ff16125238c9	payment_successful	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"vars": {"name": "there", "stock": "", "amount": "3062", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "21CE8844", "product_name": "Product", "payment_method": "cod", "receipt_number": "MOCK26273387"}, "phone": "254740845440", "amount": 3062, "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "currency": "KES", "receiptNumber": "MOCK26273387"}	{}	2026-08-13 13:04:33.879383+00
7a3874ac-91b7-4ea1-bd59-e12a1bab0800	admin_payment_received.result	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"phone": "254740845440", "amount": 3062, "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "currency": "KES", "notifyAdmins": true, "receiptNumber": "MOCK26273387"}	{"eventType": "admin_payment_received", "adminCount": 3, "deliveries": [], "notifications": []}	2026-08-13 13:04:34.37136+00
1f7db7be-68ea-475c-ac2e-e0483f48818c	order_created.result	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"amount": 3062, "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "currency": "KES", "paymentMethod": "mpesa"}	{"eventType": "order_created", "adminCount": 0, "deliveries": [{"reason": "missing_recipient", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "f5da43ca-cdeb-455c-a1e4-021ceac6d0f9", "body": "Order 21CE8844 was placed successfully. Total: 3062 KES.", "link": "/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76", "title": "Order 21CE8844 placed", "readAt": null, "status": "unread", "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "order_created"}, "createdAt": "2026-08-13T13:04:30.192733+00:00", "eventType": "order_created", "updatedAt": "2026-08-13T13:04:30.192733+00:00", "archivedAt": null}]}	2026-08-13 13:04:30.937842+00
d79fec89-218f-4d71-aaa9-fb7546875d57	payment_initiated.result	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"phone": "254740845440", "amount": 3062, "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "currency": "KES"}	{"eventType": "payment_initiated", "adminCount": 0, "deliveries": [{"reason": "no_template", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "2c3a2f3c-11ee-48b4-a7ab-d01cbd84b4c4", "body": "Payment of 3062 KES initiated for order 21CE8844. Check your phone for M-Pesa.", "link": "/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76", "title": "Payment initiated", "readAt": null, "status": "unread", "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "payment_initiated"}, "createdAt": "2026-08-13T13:04:31.154424+00:00", "eventType": "payment_initiated", "updatedAt": "2026-08-13T13:04:31.154424+00:00", "archivedAt": null}]}	2026-08-13 13:04:31.623462+00
c9add66a-e876-4877-87f9-a1236a61a6cd	admin_payment_received	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"vars": {"name": "there", "stock": "", "amount": "3062", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "21CE8844", "product_name": "Product", "payment_method": "cod", "receipt_number": "MOCK26273387"}, "phone": "254740845440", "amount": 3062, "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "currency": "KES", "notifyAdmins": true, "receiptNumber": "MOCK26273387"}	{}	2026-08-13 13:04:33.880749+00
b788a57d-f144-45b9-b790-8ffcf115f66b	payment_successful.result	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"phone": "254740845440", "amount": 3062, "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "currency": "KES", "receiptNumber": "MOCK26273387"}	{"eventType": "payment_successful", "adminCount": 0, "deliveries": [{"reason": "missing_recipient", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "4c11a47e-ecc6-4d5e-b425-392a991e65fb", "body": "Payment received for order 21CE8844. Receipt: MOCK26273387.", "link": "/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76", "title": "Payment successful", "readAt": null, "status": "unread", "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "payment_successful"}, "createdAt": "2026-08-13T13:04:34.365651+00:00", "eventType": "payment_successful", "updatedAt": "2026-08-13T13:04:34.365651+00:00", "archivedAt": null}]}	2026-08-13 13:04:34.863732+00
b657c48e-31aa-46a3-ac1c-3bbdacab31b0	admin_new_order	\N	{"vars": {"name": "there", "stock": "", "amount": "2862", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "0FD23557", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "amount": 2862, "orderId": "0fd23557-0657-4851-921a-ea57514435d3", "currency": "KES", "notifyAdmins": true, "paymentMethod": "cod"}	{}	2026-08-13 13:08:22.283678+00
99bc180e-121b-4139-b326-7724c8c4e791	order_created	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"vars": {"name": "there", "stock": "", "amount": "2862", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "0FD23557", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "amount": 2862, "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "0fd23557-0657-4851-921a-ea57514435d3", "currency": "KES", "paymentMethod": "cod"}	{}	2026-08-13 13:08:22.307347+00
bb8d00e5-8099-4666-b21b-4fcf0542027b	admin_new_order.result	\N	{"amount": 2862, "orderId": "0fd23557-0657-4851-921a-ea57514435d3", "currency": "KES", "notifyAdmins": true, "paymentMethod": "cod"}	{"eventType": "admin_new_order", "adminCount": 3, "deliveries": [], "notifications": []}	2026-08-13 13:08:22.77859+00
0f52ab27-bcb7-4125-846a-900a40c01185	order_created.result	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"amount": 2862, "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "0fd23557-0657-4851-921a-ea57514435d3", "currency": "KES", "paymentMethod": "cod"}	{"eventType": "order_created", "adminCount": 0, "deliveries": [{"reason": "missing_recipient", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "c5d046c3-f6c6-4a5e-93a5-219f99ff90d1", "body": "Order 0FD23557 was placed successfully. Total: 2862 KES.", "link": "/orders/0fd23557-0657-4851-921a-ea57514435d3", "title": "Order 0FD23557 placed", "readAt": null, "status": "unread", "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "0fd23557-0657-4851-921a-ea57514435d3", "eventType": "order_created"}, "createdAt": "2026-08-13T13:08:22.782942+00:00", "eventType": "order_created", "updatedAt": "2026-08-13T13:08:22.782942+00:00", "archivedAt": null}]}	2026-08-13 13:08:23.256013+00
990c9d17-07a8-420e-bff0-b2fe1d574a7a	order_cancelled	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"vars": {"name": "there", "stock": "", "amount": "", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "0FD23557", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "0fd23557-0657-4851-921a-ea57514435d3"}	{}	2026-08-13 13:10:15.606744+00
aba4250d-e841-4b42-ae20-d986fa8f0c36	order_cancelled.result	eebd94c0-8179-4619-a527-218ac9f7d5c4	{"userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "orderId": "0fd23557-0657-4851-921a-ea57514435d3"}	{"eventType": "order_cancelled", "adminCount": 0, "deliveries": [{"reason": "no_template", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "6ab3a602-3862-467f-8f43-da6b1804e16a", "body": "Order 0FD23557 has been cancelled.", "link": "/orders/0fd23557-0657-4851-921a-ea57514435d3", "title": "Order 0FD23557 cancelled", "readAt": null, "status": "unread", "userId": "eebd94c0-8179-4619-a527-218ac9f7d5c4", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "0fd23557-0657-4851-921a-ea57514435d3", "eventType": "order_cancelled"}, "createdAt": "2026-08-13T13:10:16.082885+00:00", "eventType": "order_cancelled", "updatedAt": "2026-08-13T13:10:16.082885+00:00", "archivedAt": null}]}	2026-08-13 13:10:16.554133+00
2f424dbf-435d-46cc-b0c1-5ad339140853	account_registration	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	{"name": "lillian", "vars": {"name": "lillian", "stock": "", "amount": "", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "—", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "email": "minyoso@gmail", "userId": "5a04e47f-c9d3-485b-8b23-3aa74d9d729e"}	{}	2026-08-13 15:10:26.756083+00
d3d1841a-6007-47cb-b421-75e4b752c587	welcome	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	{"name": "lillian", "vars": {"name": "lillian", "stock": "", "amount": "", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "—", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "email": "minyoso@gmail", "userId": "5a04e47f-c9d3-485b-8b23-3aa74d9d729e"}	{}	2026-08-13 15:10:26.785143+00
3e385c09-eefe-4559-9dd3-b170bea3fcf3	account_registration.result	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	{"name": "lillian", "email": "minyoso@gmail", "userId": "5a04e47f-c9d3-485b-8b23-3aa74d9d729e"}	{"eventType": "account_registration", "adminCount": 0, "deliveries": [{"reason": "no_template", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "0467b158-ee96-4e43-9be0-e87c61bfe02b", "body": "Welcome to Babees Place, lillian! Your account is ready.", "link": "/notifications", "title": "Welcome aboard", "readAt": null, "status": "unread", "userId": "5a04e47f-c9d3-485b-8b23-3aa74d9d729e", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": null, "eventType": "account_registration"}, "createdAt": "2026-08-13T15:10:28.039303+00:00", "eventType": "account_registration", "updatedAt": "2026-08-13T15:10:28.039303+00:00", "archivedAt": null}]}	2026-08-13 15:10:28.604174+00
82cedbfe-a69f-40b8-8ced-31c933ea97c4	order_created.result	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	{"amount": 3753, "userId": "5a04e47f-c9d3-485b-8b23-3aa74d9d729e", "orderId": "f85d863c-b81e-49e9-8451-7980551af330", "currency": "KES", "paymentMethod": "cod"}	{"eventType": "order_created", "adminCount": 0, "deliveries": [{"reason": "missing_recipient", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "23b4f10c-b9e8-4621-915a-3349fbf65881", "body": "Order F85D863C was placed successfully. Total: 3753 KES.", "link": "/orders/f85d863c-b81e-49e9-8451-7980551af330", "title": "Order F85D863C placed", "readAt": null, "status": "unread", "userId": "5a04e47f-c9d3-485b-8b23-3aa74d9d729e", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": "f85d863c-b81e-49e9-8451-7980551af330", "eventType": "order_created"}, "createdAt": "2026-08-13T15:11:46.841377+00:00", "eventType": "order_created", "updatedAt": "2026-08-13T15:11:46.841377+00:00", "archivedAt": null}]}	2026-08-13 15:11:47.483034+00
42e4897e-2188-4b5a-94e3-400854bff210	welcome.result	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	{"name": "lillian", "email": "minyoso@gmail", "userId": "5a04e47f-c9d3-485b-8b23-3aa74d9d729e"}	{"eventType": "welcome", "adminCount": 0, "deliveries": [{"reason": "preference", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "d8e82122-051a-40c0-a94b-b49f2a762b31", "body": "welcome", "link": "/notifications", "title": "Welcome to Babees Place", "readAt": null, "status": "unread", "userId": "5a04e47f-c9d3-485b-8b23-3aa74d9d729e", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": null, "eventType": "welcome"}, "createdAt": "2026-08-13T15:10:28.064423+00:00", "eventType": "welcome", "updatedAt": "2026-08-13T15:10:28.064423+00:00", "archivedAt": null}]}	2026-08-13 15:10:28.615961+00
2b7664c0-bc0e-4445-befe-e536bf8d5bcb	order_created	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	{"vars": {"name": "there", "stock": "", "amount": "3753", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "F85D863C", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "amount": 3753, "userId": "5a04e47f-c9d3-485b-8b23-3aa74d9d729e", "orderId": "f85d863c-b81e-49e9-8451-7980551af330", "currency": "KES", "paymentMethod": "cod"}	{}	2026-08-13 15:11:45.67151+00
2ee52ce1-c693-470f-b9a3-19af0e0de389	admin_new_order	\N	{"vars": {"name": "there", "stock": "", "amount": "3753", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "F85D863C", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "amount": 3753, "orderId": "f85d863c-b81e-49e9-8451-7980551af330", "currency": "KES", "notifyAdmins": true, "paymentMethod": "cod"}	{}	2026-08-13 15:11:45.685133+00
d8b1b825-3517-42e1-aa15-2aeadb65434d	admin_new_order.result	\N	{"amount": 3753, "orderId": "f85d863c-b81e-49e9-8451-7980551af330", "currency": "KES", "notifyAdmins": true, "paymentMethod": "cod"}	{"eventType": "admin_new_order", "adminCount": 3, "deliveries": [], "notifications": []}	2026-08-13 15:11:46.475206+00
d50842ab-dfe7-40bf-b622-bb099fcf277f	account_registration	0615e227-eeae-4afe-b3e2-0acc74b7c439	{"name": "Oscar Aseka", "vars": {"name": "Oscar Aseka", "stock": "", "amount": "", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "—", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "email": "oscaraseka1111@gmail.com", "userId": "0615e227-eeae-4afe-b3e2-0acc74b7c439"}	{}	2026-09-05 10:59:30.688484+00
2d667d0b-2d8d-48d4-9adf-0e88f84436b8	welcome	0615e227-eeae-4afe-b3e2-0acc74b7c439	{"name": "Oscar Aseka", "vars": {"name": "Oscar Aseka", "stock": "", "amount": "", "currency": "KES", "location": "the boutique", "reset_link": "#", "verify_link": "#", "order_number": "—", "product_name": "Product", "payment_method": "cod", "receipt_number": "—"}, "email": "oscaraseka1111@gmail.com", "userId": "0615e227-eeae-4afe-b3e2-0acc74b7c439"}	{}	2026-09-05 10:59:30.708626+00
e519a459-efd9-4093-85e5-66c06684a5d7	welcome.result	0615e227-eeae-4afe-b3e2-0acc74b7c439	{"name": "Oscar Aseka", "email": "oscaraseka1111@gmail.com", "userId": "0615e227-eeae-4afe-b3e2-0acc74b7c439"}	{"eventType": "welcome", "adminCount": 0, "deliveries": [{"reason": "preference", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "0ab6c42b-b8c9-463e-8060-2a5523f6a074", "body": "welcome", "link": "/notifications", "title": "Welcome to Babees Place", "readAt": null, "status": "unread", "userId": "0615e227-eeae-4afe-b3e2-0acc74b7c439", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": null, "eventType": "welcome"}, "createdAt": "2026-09-05T10:59:32.158824+00:00", "eventType": "welcome", "updatedAt": "2026-09-05T10:59:32.158824+00:00", "archivedAt": null}]}	2026-09-05 10:59:32.912971+00
c13b0b8f-941a-477b-8bb1-e4d411e4bd43	account_registration.result	0615e227-eeae-4afe-b3e2-0acc74b7c439	{"name": "Oscar Aseka", "email": "oscaraseka1111@gmail.com", "userId": "0615e227-eeae-4afe-b3e2-0acc74b7c439"}	{"eventType": "account_registration", "adminCount": 0, "deliveries": [{"reason": "no_template", "channel": "email", "skipped": true}, {"reason": "preference", "channel": "sms", "skipped": true}], "notifications": [{"id": "9466dd33-195d-4bbc-8484-36bc817854a1", "body": "Welcome to Babees Place, Oscar Aseka! Your account is ready.", "link": "/notifications", "title": "Welcome aboard", "readAt": null, "status": "unread", "userId": "0615e227-eeae-4afe-b3e2-0acc74b7c439", "channel": "in_app", "audience": "customer", "isUnread": true, "metadata": {"orderId": null, "eventType": "account_registration"}, "createdAt": "2026-09-05T10:59:32.389669+00:00", "eventType": "account_registration", "updatedAt": "2026-09-05T10:59:32.389669+00:00", "archivedAt": null}]}	2026-09-05 10:59:33.030913+00
\.


--
-- Data for Name: notification_preferences; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notification_preferences (user_id, email_enabled, sms_enabled, in_app_enabled, push_enabled, marketing_emails, order_updates, payment_updates, created_at, updated_at) FROM stdin;
c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	t	f	t	f	f	t	t	2026-08-04 05:43:35.126211+00	2026-08-04 05:43:35.126211+00
7d487b08-c6f1-4726-a23b-cbb9f7647cbd	t	f	t	f	f	t	t	2026-08-04 06:23:25.717647+00	2026-08-04 06:23:25.717647+00
eebd94c0-8179-4619-a527-218ac9f7d5c4	t	f	t	f	f	t	t	2026-08-13 05:59:56.608057+00	2026-08-13 05:59:56.608057+00
5a04e47f-c9d3-485b-8b23-3aa74d9d729e	t	f	t	f	f	t	t	2026-08-13 15:10:27.434047+00	2026-08-13 15:10:27.434047+00
0615e227-eeae-4afe-b3e2-0acc74b7c439	t	f	t	f	f	t	t	2026-09-05 10:59:31.535192+00	2026-09-05 10:59:31.535192+00
\.


--
-- Data for Name: notification_templates; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notification_templates (id, code, channel, subject, body, description, is_active, created_at, updated_at) FROM stdin;
db6141fe-1dbb-4879-b92a-534d9d5d6d8f	account_registration	in_app	\N	Welcome to Babees Place, {{name}}! Your account is ready.	Account registration confirmation	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
2fe2ff1e-c500-4424-8885-e33de50b1566	welcome	email	Welcome to Babees Place	Hi {{name}},\\n\\nWelcome to Babees Place. Start exploring our collection today.	Welcome email	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
a938df70-d9a5-4d28-861b-40e37bd23ce5	password_reset	email	Reset your Babees Place password	Hi {{name}},\\n\\nUse this link to reset your password: {{reset_link}}\\n\\nIf you did not request this, ignore this email.	Password reset	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
5d1c120a-9bad-4a96-9aef-597b4d44df27	email_verification	email	Verify your Babees Place email	Hi {{name}},\\n\\nPlease verify your email: {{verify_link}}	Email verification	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
b690af32-ce48-4da4-94bb-95357c1a8c61	order_created	in_app	\N	Order {{order_number}} was placed successfully. Total: {{amount}} {{currency}}.	Customer order created	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
b6b6208d-38ef-4221-b273-69cc04ee5bcd	order_confirmed	in_app	\N	Order {{order_number}} has been confirmed and is being prepared.	Order confirmed	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
a2db9ee5-860e-49c7-914d-349dac94b104	order_cancelled	in_app	\N	Order {{order_number}} has been cancelled.	Order cancelled	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
9b536e4f-224a-46c7-908c-2f686baa6500	order_ready_for_pickup	in_app	\N	Order {{order_number}} is ready for pickup at {{location}}.	Ready for pickup	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
770715e1-b139-40cd-bd8d-b2313a167f5a	out_for_delivery	in_app	\N	Order {{order_number}} is out for delivery.	Out for delivery	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
bae4cfeb-85b2-482d-8804-ab4d312e2778	delivered	in_app	\N	Order {{order_number}} has been delivered. Enjoy!	Delivered	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
984e7294-130a-4e15-93f6-5fee7523af56	payment_initiated	in_app	\N	Payment of {{amount}} {{currency}} initiated for order {{order_number}}. Check your phone for M-Pesa.	Payment initiated	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
60a17610-1fbb-4501-b65b-3235bdd2382b	payment_successful	in_app	\N	Payment received for order {{order_number}}. Receipt: {{receipt_number}}.	Payment successful	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
1efc0e40-b869-4756-b155-37b5f210a979	payment_failed	in_app	\N	Payment for order {{order_number}} failed. You can retry from your order page.	Payment failed	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
b2110298-dfcf-4c82-b738-c223549170f8	payment_retry	in_app	\N	A new payment attempt was started for order {{order_number}}.	Payment retry	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
4e08733a-a37f-48e0-bbbf-974fad2580e8	admin_new_order	in_app	\N	New order {{order_number}} — {{amount}} {{currency}} ({{payment_method}}).	Admin new order	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
7cf59e6f-eb7c-49a4-a3ee-2f49b0607252	admin_low_inventory	in_app	\N	Low stock: {{product_name}} has {{stock}} units left.	Admin low inventory	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
52d262f4-b855-4f19-b1da-44c7db05d6bc	admin_payment_received	in_app	\N	Payment received for order {{order_number}}. Receipt: {{receipt_number}}.	Admin payment received	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
e01cb60b-da5c-4b84-9ea1-008a87dd24b2	order_created	email	Order confirmation — {{order_number}}	Hi {{name}},\\n\\nThanks for your order {{order_number}}. Total: {{amount}} {{currency}}.	Order confirmation email	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
69a49bd2-6345-4646-a85e-4111e907cd13	payment_successful	email	Payment received — {{order_number}}	Hi {{name}},\\n\\nWe received your payment for {{order_number}}. Receipt: {{receipt_number}}.	Payment success email	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
1de7dae9-c678-42f1-a2d8-47ec7c8ed4ba	payment_failed	email	Payment failed — {{order_number}}	Hi {{name}},\\n\\nPayment for {{order_number}} did not complete. Please retry from your orders.	Payment failed email	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
6157ba4e-18d3-4922-959b-7e0a06a8995c	order_ready_for_pickup	sms	\N	Babees Place: Order {{order_number}} is ready for pickup.	Pickup SMS	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
16aaae41-3b40-41b1-8b78-bdadb0c066ed	payment_successful	sms	\N	Babees Place: Payment confirmed for {{order_number}}. Receipt {{receipt_number}}.	Payment SMS	t	2026-08-03 09:39:54.215547+00	2026-08-03 09:39:54.215547+00
\.


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notifications (id, user_id, event_type, channel, title, body, link, metadata, status, audience, read_at, archived_at, created_at, updated_at) FROM stdin;
b6a1f99b-eb31-4016-9ff8-a73a36564ca0	91877d22-84c1-4253-9e57-13aa5a617b1c	order_created	in_app	Order placed	Order fc062098-b9c7-459a-bddb-70903a5bf5b2	/orders/fc062098-b9c7-459a-bddb-70903a5bf5b2	{"orderId": "fc062098-b9c7-459a-bddb-70903a5bf5b2"}	unread	customer	\N	\N	2026-08-03 09:51:55.166079+00	2026-08-03 09:51:55.166079+00
0d434750-5c8b-475a-bc07-04fe826a2f74	b98a07b1-467f-4e20-ac14-da354b094637	admin_new_order	in_app	New order	Order fc062098-b9c7-459a-bddb-70903a5bf5b2	/admin/orders/fc062098-b9c7-459a-bddb-70903a5bf5b2	{"orderId": "fc062098-b9c7-459a-bddb-70903a5bf5b2"}	unread	admin	\N	\N	2026-08-03 09:51:55.614063+00	2026-08-03 09:51:55.614063+00
87f75f49-85f7-4da6-8144-de194442fa9e	2c68a903-e68d-4f00-8586-d0efc6047b2b	admin_new_order	in_app	New order	Order fc062098-b9c7-459a-bddb-70903a5bf5b2	/admin/orders/fc062098-b9c7-459a-bddb-70903a5bf5b2	{"orderId": "fc062098-b9c7-459a-bddb-70903a5bf5b2"}	unread	admin	\N	\N	2026-08-03 09:51:55.614063+00	2026-08-03 09:51:55.614063+00
061beee8-20ed-4a7d-a808-2037a71db2b0	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	admin_new_order	in_app	New order	Order fc062098-b9c7-459a-bddb-70903a5bf5b2	/admin/orders/fc062098-b9c7-459a-bddb-70903a5bf5b2	{"orderId": "fc062098-b9c7-459a-bddb-70903a5bf5b2"}	unread	admin	\N	\N	2026-08-03 09:51:55.614063+00	2026-08-03 09:51:55.614063+00
2dc5a58f-0547-4fea-8aab-6fd910dd3152	2c68a903-e68d-4f00-8586-d0efc6047b2b	admin_new_order	in_app	New order A362D405	New order A362D405 — 2727 KES (cod).	/admin/orders/a362d405-d226-4115-80f6-505fb3b49c21	{"orderId": "a362d405-d226-4115-80f6-505fb3b49c21", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-04 05:43:35.130482+00	2026-08-04 05:43:35.130482+00
7848cd6f-1c32-4cb5-b74e-02a3988e604d	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	admin_new_order	in_app	New order A362D405	New order A362D405 — 2727 KES (cod).	/admin/orders/a362d405-d226-4115-80f6-505fb3b49c21	{"orderId": "a362d405-d226-4115-80f6-505fb3b49c21", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-04 05:43:35.130482+00	2026-08-04 05:43:35.130482+00
fe60e998-b297-4de9-8c98-7962646c52cc	c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	order_created	in_app	Order A362D405 placed	Order A362D405 was placed successfully. Total: 2727 KES.	/orders/a362d405-d226-4115-80f6-505fb3b49c21	{"orderId": "a362d405-d226-4115-80f6-505fb3b49c21", "eventType": "order_created"}	unread	customer	\N	\N	2026-08-04 05:43:35.556603+00	2026-08-04 05:43:35.556603+00
0233a0a2-0fe2-4f0c-b6b9-49dd1e13f039	b98a07b1-467f-4e20-ac14-da354b094637	admin_new_order	in_app	New order A362D405	New order A362D405 — 2727 KES (cod).	/admin/orders/a362d405-d226-4115-80f6-505fb3b49c21	{"orderId": "a362d405-d226-4115-80f6-505fb3b49c21", "eventType": "admin_new_order"}	read	admin	2026-08-04 06:20:49.197804+00	\N	2026-08-04 05:43:35.130482+00	2026-08-04 06:20:49.197804+00
44de47ef-4bb2-46cd-9e02-7beaf26a6be0	2c68a903-e68d-4f00-8586-d0efc6047b2b	admin_new_order	in_app	New order AC2C4DAE	New order AC2C4DAE — 5661 KES (cod).	/admin/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	{"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-04 06:25:15.246477+00	2026-08-04 06:25:15.246477+00
d2529ebe-5f55-48b8-9611-3f37f435c2ce	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	admin_new_order	in_app	New order AC2C4DAE	New order AC2C4DAE — 5661 KES (cod).	/admin/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	{"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-04 06:25:15.246477+00	2026-08-04 06:25:15.246477+00
98b4fab7-9dd0-4f75-b222-f7443e24e94a	b98a07b1-467f-4e20-ac14-da354b094637	admin_new_order	in_app	New order AC2C4DAE	New order AC2C4DAE — 5661 KES (cod).	/admin/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	{"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "admin_new_order"}	read	admin	2026-08-04 06:27:43.809486+00	\N	2026-08-04 06:25:15.246477+00	2026-08-04 06:27:43.809486+00
3108d976-2fbd-4271-ae8a-d8895a4997a0	eebd94c0-8179-4619-a527-218ac9f7d5c4	welcome	in_app	Welcome to Babees Place	welcome	/notifications	{"orderId": null, "eventType": "welcome"}	unread	customer	\N	\N	2026-08-13 05:59:56.94524+00	2026-08-13 05:59:56.94524+00
d185cece-d9e4-4186-ab97-19a7dec54f5a	eebd94c0-8179-4619-a527-218ac9f7d5c4	account_registration	in_app	Welcome aboard	Welcome to Babees Place, Nestar Ambula! Your account is ready.	/notifications	{"orderId": null, "eventType": "account_registration"}	unread	customer	\N	\N	2026-08-13 05:59:57.360293+00	2026-08-13 05:59:57.360293+00
7f42ce0e-f49a-4070-a8cf-731d9a054952	b98a07b1-467f-4e20-ac14-da354b094637	admin_new_order	in_app	New order 21CE8844	New order 21CE8844 — 3062 KES (mpesa).	/admin/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76	{"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-13 13:04:29.922603+00	2026-08-13 13:04:29.922603+00
33b4bd3a-ccc9-40b2-98f5-c68c549178e0	2c68a903-e68d-4f00-8586-d0efc6047b2b	admin_new_order	in_app	New order 21CE8844	New order 21CE8844 — 3062 KES (mpesa).	/admin/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76	{"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-13 13:04:29.922603+00	2026-08-13 13:04:29.922603+00
fd2bd99a-b252-4578-9acd-a5597f095a0f	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	admin_new_order	in_app	New order 21CE8844	New order 21CE8844 — 3062 KES (mpesa).	/admin/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76	{"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-13 13:04:29.922603+00	2026-08-13 13:04:29.922603+00
f5da43ca-cdeb-455c-a1e4-021ceac6d0f9	eebd94c0-8179-4619-a527-218ac9f7d5c4	order_created	in_app	Order 21CE8844 placed	Order 21CE8844 was placed successfully. Total: 3062 KES.	/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76	{"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "order_created"}	unread	customer	\N	\N	2026-08-13 13:04:30.192733+00	2026-08-13 13:04:30.192733+00
2c3a2f3c-11ee-48b4-a7ab-d01cbd84b4c4	eebd94c0-8179-4619-a527-218ac9f7d5c4	payment_initiated	in_app	Payment initiated	Payment of 3062 KES initiated for order 21CE8844. Check your phone for M-Pesa.	/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76	{"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "payment_initiated"}	unread	customer	\N	\N	2026-08-13 13:04:31.154424+00	2026-08-13 13:04:31.154424+00
c8443011-1c49-4668-9970-aa613d8d59ef	b98a07b1-467f-4e20-ac14-da354b094637	admin_payment_received	in_app	Payment received — 21CE8844	Payment received for order 21CE8844. Receipt: MOCK26273387.	/admin/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76	{"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "admin_payment_received"}	unread	admin	\N	\N	2026-08-13 13:04:34.128152+00	2026-08-13 13:04:34.128152+00
da23a400-b208-4484-8dac-188a84eaa311	2c68a903-e68d-4f00-8586-d0efc6047b2b	admin_payment_received	in_app	Payment received — 21CE8844	Payment received for order 21CE8844. Receipt: MOCK26273387.	/admin/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76	{"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "admin_payment_received"}	unread	admin	\N	\N	2026-08-13 13:04:34.128152+00	2026-08-13 13:04:34.128152+00
c334b8f0-150c-43fe-a314-964fce0faf92	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	admin_payment_received	in_app	Payment received — 21CE8844	Payment received for order 21CE8844. Receipt: MOCK26273387.	/admin/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76	{"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "admin_payment_received"}	unread	admin	\N	\N	2026-08-13 13:04:34.128152+00	2026-08-13 13:04:34.128152+00
4c11a47e-ecc6-4d5e-b425-392a991e65fb	eebd94c0-8179-4619-a527-218ac9f7d5c4	payment_successful	in_app	Payment successful	Payment received for order 21CE8844. Receipt: MOCK26273387.	/orders/21ce8844-157e-4cd8-9e93-2c4d20256a76	{"orderId": "21ce8844-157e-4cd8-9e93-2c4d20256a76", "eventType": "payment_successful"}	unread	customer	\N	\N	2026-08-13 13:04:34.365651+00	2026-08-13 13:04:34.365651+00
610ae0da-2428-4be6-b80a-b6af1cb96236	b98a07b1-467f-4e20-ac14-da354b094637	admin_new_order	in_app	New order 0FD23557	New order 0FD23557 — 2862 KES (cod).	/admin/orders/0fd23557-0657-4851-921a-ea57514435d3	{"orderId": "0fd23557-0657-4851-921a-ea57514435d3", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-13 13:08:22.533469+00	2026-08-13 13:08:22.533469+00
dfb352d8-64fb-4908-b5eb-7c4720423775	2c68a903-e68d-4f00-8586-d0efc6047b2b	admin_new_order	in_app	New order 0FD23557	New order 0FD23557 — 2862 KES (cod).	/admin/orders/0fd23557-0657-4851-921a-ea57514435d3	{"orderId": "0fd23557-0657-4851-921a-ea57514435d3", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-13 13:08:22.533469+00	2026-08-13 13:08:22.533469+00
7618b9f6-f893-45c5-815e-a6ba86586743	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	admin_new_order	in_app	New order 0FD23557	New order 0FD23557 — 2862 KES (cod).	/admin/orders/0fd23557-0657-4851-921a-ea57514435d3	{"orderId": "0fd23557-0657-4851-921a-ea57514435d3", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-13 13:08:22.533469+00	2026-08-13 13:08:22.533469+00
c5d046c3-f6c6-4a5e-93a5-219f99ff90d1	eebd94c0-8179-4619-a527-218ac9f7d5c4	order_created	in_app	Order 0FD23557 placed	Order 0FD23557 was placed successfully. Total: 2862 KES.	/orders/0fd23557-0657-4851-921a-ea57514435d3	{"orderId": "0fd23557-0657-4851-921a-ea57514435d3", "eventType": "order_created"}	unread	customer	\N	\N	2026-08-13 13:08:22.782942+00	2026-08-13 13:08:22.782942+00
6ab3a602-3862-467f-8f43-da6b1804e16a	eebd94c0-8179-4619-a527-218ac9f7d5c4	order_cancelled	in_app	Order 0FD23557 cancelled	Order 0FD23557 has been cancelled.	/orders/0fd23557-0657-4851-921a-ea57514435d3	{"orderId": "0fd23557-0657-4851-921a-ea57514435d3", "eventType": "order_cancelled"}	unread	customer	\N	\N	2026-08-13 13:10:16.082885+00	2026-08-13 13:10:16.082885+00
0d150b7d-8e82-46ca-8cdc-bfbfb00eb654	b98a07b1-467f-4e20-ac14-da354b094637	admin_new_order	in_app	New order F85D863C	New order F85D863C — 3753 KES (cod).	/admin/orders/f85d863c-b81e-49e9-8451-7980551af330	{"orderId": "f85d863c-b81e-49e9-8451-7980551af330", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-13 15:11:46.167914+00	2026-08-13 15:11:46.167914+00
b861d238-d7b3-4197-acb1-dab58556f3ac	2c68a903-e68d-4f00-8586-d0efc6047b2b	admin_new_order	in_app	New order F85D863C	New order F85D863C — 3753 KES (cod).	/admin/orders/f85d863c-b81e-49e9-8451-7980551af330	{"orderId": "f85d863c-b81e-49e9-8451-7980551af330", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-13 15:11:46.167914+00	2026-08-13 15:11:46.167914+00
142a1a5e-0db0-47c0-994d-462254b35ceb	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	admin_new_order	in_app	New order F85D863C	New order F85D863C — 3753 KES (cod).	/admin/orders/f85d863c-b81e-49e9-8451-7980551af330	{"orderId": "f85d863c-b81e-49e9-8451-7980551af330", "eventType": "admin_new_order"}	unread	admin	\N	\N	2026-08-13 15:11:46.167914+00	2026-08-13 15:11:46.167914+00
23b4f10c-b9e8-4621-915a-3349fbf65881	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	order_created	in_app	Order F85D863C placed	Order F85D863C was placed successfully. Total: 3753 KES.	/orders/f85d863c-b81e-49e9-8451-7980551af330	{"orderId": "f85d863c-b81e-49e9-8451-7980551af330", "eventType": "order_created"}	unread	customer	\N	\N	2026-08-13 15:11:46.841377+00	2026-08-13 15:11:46.841377+00
14fad145-01c3-4a8b-837c-5848c0273048	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order_created	in_app	Order AC2C4DAE placed	Order AC2C4DAE was placed successfully. Total: 5661 KES.	/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	{"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "order_created"}	read	customer	2026-08-21 15:01:47.141804+00	\N	2026-08-04 06:25:15.586153+00	2026-08-21 15:01:47.141804+00
d05bda9f-9bd5-4b02-a6fe-7e7294156005	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order_confirmed	in_app	Order AC2C4DAE confirmed	Order AC2C4DAE has been confirmed and is being prepared.	/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	{"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "order_confirmed"}	read	customer	2026-08-21 15:01:47.141804+00	\N	2026-08-04 06:28:21.135059+00	2026-08-21 15:01:47.141804+00
713d4a85-9883-47ae-8c7f-5e6b494d6beb	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order_ready_for_pickup	in_app	Order AC2C4DAE ready	Order AC2C4DAE is ready for pickup at your selected boutique.	/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	{"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "order_ready_for_pickup"}	read	customer	2026-08-21 15:01:47.141804+00	\N	2026-08-04 06:28:35.643768+00	2026-08-21 15:01:47.141804+00
a17c9d7a-98c5-4a78-833c-d97a009912b6	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	order_ready_for_pickup	in_app	Order AC2C4DAE ready	Order AC2C4DAE is ready for pickup at your selected boutique.	/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	{"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "order_ready_for_pickup"}	read	customer	2026-08-21 15:01:47.141804+00	\N	2026-08-04 06:28:42.011935+00	2026-08-21 15:01:47.141804+00
057ecc10-b32b-4a7b-bff2-f7954537dcbb	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	delivered	in_app	Order AC2C4DAE delivered	Order AC2C4DAE has been delivered. Enjoy!	/orders/ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	{"orderId": "ac2c4dae-27c1-41bb-8ac1-d7f352136d7a", "eventType": "delivered"}	read	customer	2026-08-21 15:01:47.141804+00	\N	2026-08-04 06:28:49.166376+00	2026-08-21 15:01:47.141804+00
d8e82122-051a-40c0-a94b-b49f2a762b31	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	welcome	in_app	Welcome to Babees Place	welcome	/notifications	{"orderId": null, "eventType": "welcome"}	read	customer	2026-08-26 22:41:12.682024+00	\N	2026-08-13 15:10:28.064423+00	2026-08-26 22:41:12.682024+00
0467b158-ee96-4e43-9be0-e87c61bfe02b	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	account_registration	in_app	Welcome aboard	Welcome to Babees Place, lillian! Your account is ready.	/notifications	{"orderId": null, "eventType": "account_registration"}	read	customer	2026-08-26 22:41:25.461079+00	\N	2026-08-13 15:10:28.039303+00	2026-08-26 22:41:25.461079+00
f5114a32-6a3d-47ae-9821-1af559f16476	b98a07b1-467f-4e20-ac14-da354b094637	audit_probe	in_app	audit probe	read-only audit probe	\N	{}	unread	admin	\N	\N	2026-08-31 07:49:12.820591+00	2026-08-31 07:49:12.820591+00
1190c212-fe9e-4c26-bbc6-262e55aa880b	2c68a903-e68d-4f00-8586-d0efc6047b2b	audit_probe	in_app	audit probe	read-only audit probe	\N	{}	unread	admin	\N	\N	2026-08-31 07:49:12.820591+00	2026-08-31 07:49:12.820591+00
ff8b6295-47da-4827-be05-6c302785d5c1	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	audit_probe	in_app	audit probe	read-only audit probe	\N	{}	unread	admin	\N	\N	2026-08-31 07:49:12.820591+00	2026-08-31 07:49:12.820591+00
2c494480-3548-4bd9-b76e-4446f60886e8	b98a07b1-467f-4e20-ac14-da354b094637	x	in_app	x	x	\N	{}	unread	admin	\N	\N	2026-08-31 08:01:24.500432+00	2026-08-31 08:01:24.500432+00
5d6243c6-5188-47fa-80ad-6f002755175e	2c68a903-e68d-4f00-8586-d0efc6047b2b	x	in_app	x	x	\N	{}	unread	admin	\N	\N	2026-08-31 08:01:24.500432+00	2026-08-31 08:01:24.500432+00
0d573fe8-542f-4bb8-81be-3ac54e2a8139	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	x	in_app	x	x	\N	{}	unread	admin	\N	\N	2026-08-31 08:01:24.500432+00	2026-08-31 08:01:24.500432+00
0ab6c42b-b8c9-463e-8060-2a5523f6a074	0615e227-eeae-4afe-b3e2-0acc74b7c439	welcome	in_app	Welcome to Babees Place	welcome	/notifications	{"orderId": null, "eventType": "welcome"}	unread	customer	\N	\N	2026-09-05 10:59:32.158824+00	2026-09-05 10:59:32.158824+00
9466dd33-195d-4bbc-8484-36bc817854a1	0615e227-eeae-4afe-b3e2-0acc74b7c439	account_registration	in_app	Welcome aboard	Welcome to Babees Place, Oscar Aseka! Your account is ready.	/notifications	{"orderId": null, "eventType": "account_registration"}	unread	customer	\N	\N	2026-09-05 10:59:32.389669+00	2026-09-05 10:59:32.389669+00
\.


--
-- Data for Name: order_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.order_events (id, order_id, event_type, payload, created_at) FROM stdin;
efbaa3c5-0156-4412-b557-83b1950f4747	bdbf4160-0027-43c9-a2b9-a1289e75b84c	order_placed	{"total": 60.00, "subtotal": 60.00, "delivery_fee": 0.00, "delivery_type": "pickup"}	2026-07-13 09:08:43.43044+00
a205e805-cb42-4b3c-af07-9501af707e6a	43cd4c98-d8f5-4575-bc44-0170a423543f	order_placed	{"total": 3560.00, "subtotal": 3560.00, "delivery_fee": 0.00, "delivery_type": "pickup"}	2026-07-13 09:24:46.827239+00
59fce679-ef5c-4ef7-9140-569520f3db47	43cd4c98-d8f5-4575-bc44-0170a423543f	status_changed	{"to": "confirmed", "from": "pending", "note": ""}	2026-07-13 09:25:48.420546+00
f85d2e40-ada1-47c3-a593-f8b8ab91af6b	43cd4c98-d8f5-4575-bc44-0170a423543f	payment_status_changed	{"to": "paid", "from": "pending"}	2026-07-13 09:26:16.606581+00
2fb47806-affa-46b7-94b2-6e2500569a49	43cd4c98-d8f5-4575-bc44-0170a423543f	payment_status_changed	{"to": "paid", "from": "paid"}	2026-07-13 09:26:25.205873+00
7a6b5e59-6468-4128-a6d2-047b3ed739dc	43cd4c98-d8f5-4575-bc44-0170a423543f	status_changed	{"to": "ready_for_pickup", "from": "confirmed", "note": ""}	2026-07-13 09:26:27.453053+00
d914e709-ef16-4021-9295-ecbef8190349	43cd4c98-d8f5-4575-bc44-0170a423543f	status_changed	{"to": "delivered", "from": "ready_for_pickup", "note": ""}	2026-07-13 09:26:37.972185+00
aa000000-0000-4000-8000-000000000019	a8000000-0000-4000-8000-000000000007	order_placed	{"total": 5680, "source": "demo-seed", "subtotal": 5680}	2026-07-18 09:06:41.735+00
aa000000-0000-4000-8000-000000000020	a8000000-0000-4000-8000-000000000007	status_changed	{"to": "delivered"}	2026-07-19 09:06:41.735+00
aa000000-0000-4000-8000-000000000021	a8000000-0000-4000-8000-000000000007	payment_status_changed	{"to": "paid"}	2026-07-19 09:06:41.735+00
aa000000-0000-4000-8000-000000000022	a8000000-0000-4000-8000-000000000008	order_placed	{"total": 6190, "source": "demo-seed", "subtotal": 5990}	2026-07-28 09:06:41.735+00
aa000000-0000-4000-8000-000000000023	a8000000-0000-4000-8000-000000000008	status_changed	{"to": "confirmed"}	2026-07-29 09:06:41.735+00
aa000000-0000-4000-8000-000000000024	a8000000-0000-4000-8000-000000000008	payment_status_changed	{"to": "paid"}	2026-07-29 09:06:41.735+00
aa000000-0000-4000-8000-000000000025	a8000000-0000-4000-8000-000000000009	order_placed	{"total": 5980, "source": "demo-seed", "subtotal": 5780}	2026-07-14 09:06:41.735+00
aa000000-0000-4000-8000-000000000026	a8000000-0000-4000-8000-000000000009	status_changed	{"to": "delivered"}	2026-07-15 09:06:41.735+00
aa000000-0000-4000-8000-000000000027	a8000000-0000-4000-8000-000000000009	payment_status_changed	{"to": "paid"}	2026-07-15 09:06:41.735+00
aa000000-0000-4000-8000-000000000028	a8000000-0000-4000-8000-000000000010	order_placed	{"total": 3400, "source": "demo-seed", "subtotal": 3200}	2026-07-30 09:06:41.735+00
aa000000-0000-4000-8000-000000000031	a8000000-0000-4000-8000-000000000011	order_placed	{"total": 1890, "source": "demo-seed", "subtotal": 1890}	2026-07-12 09:06:41.736+00
aa000000-0000-4000-8000-000000000032	a8000000-0000-4000-8000-000000000011	status_changed	{"to": "cancelled"}	2026-07-13 09:06:41.736+00
aa000000-0000-4000-8000-000000000034	a8000000-0000-4000-8000-000000000012	order_placed	{"total": 1940, "source": "demo-seed", "subtotal": 1940}	2026-07-23 09:06:41.736+00
aa000000-0000-4000-8000-000000000035	a8000000-0000-4000-8000-000000000012	status_changed	{"to": "ready_for_pickup"}	2026-07-24 09:06:41.736+00
aa000000-0000-4000-8000-000000000036	a8000000-0000-4000-8000-000000000012	payment_status_changed	{"to": "paid"}	2026-07-24 09:06:41.736+00
aa000000-0000-4000-8000-000000000037	a8000000-0000-4000-8000-000000000013	order_placed	{"total": 3380, "source": "demo-seed", "subtotal": 3180}	2026-07-19 09:06:41.736+00
aa000000-0000-4000-8000-000000000038	a8000000-0000-4000-8000-000000000013	status_changed	{"to": "delivered"}	2026-07-20 09:06:41.736+00
aa000000-0000-4000-8000-000000000039	a8000000-0000-4000-8000-000000000013	payment_status_changed	{"to": "paid"}	2026-07-20 09:06:41.736+00
aa000000-0000-4000-8000-000000000040	a8000000-0000-4000-8000-000000000014	order_placed	{"total": 4700, "source": "demo-seed", "subtotal": 4500}	2026-07-31 09:06:41.736+00
aa000000-0000-4000-8000-000000000041	a8000000-0000-4000-8000-000000000014	status_changed	{"to": "processing"}	2026-08-01 09:06:41.736+00
aa000000-0000-4000-8000-000000000042	a8000000-0000-4000-8000-000000000014	payment_status_changed	{"to": "paid"}	2026-08-01 09:06:41.736+00
aa000000-0000-4000-8000-000000000043	a8000000-0000-4000-8000-000000000015	order_placed	{"total": 3150, "source": "demo-seed", "subtotal": 2950}	2026-07-15 09:06:41.736+00
aa000000-0000-4000-8000-000000000044	a8000000-0000-4000-8000-000000000015	status_changed	{"to": "delivered"}	2026-07-16 09:06:41.736+00
aa000000-0000-4000-8000-000000000045	a8000000-0000-4000-8000-000000000015	payment_status_changed	{"to": "paid"}	2026-07-16 09:06:41.736+00
aa000000-0000-4000-8000-000000000046	a8000000-0000-4000-8000-000000000016	order_placed	{"total": 4490, "source": "demo-seed", "subtotal": 4290}	2026-07-26 09:06:41.736+00
aa000000-0000-4000-8000-000000000047	a8000000-0000-4000-8000-000000000016	status_changed	{"to": "shipped"}	2026-07-27 09:06:41.736+00
aa000000-0000-4000-8000-000000000048	a8000000-0000-4000-8000-000000000016	payment_status_changed	{"to": "paid"}	2026-07-27 09:06:41.736+00
aa000000-0000-4000-8000-000000000049	a8000000-0000-4000-8000-000000000017	order_placed	{"total": 5180, "source": "demo-seed", "subtotal": 5180}	2026-08-01 09:06:41.736+00
aa000000-0000-4000-8000-000000000052	a8000000-0000-4000-8000-000000000018	order_placed	{"total": 3800, "source": "demo-seed", "subtotal": 3600}	2026-08-02 09:06:41.736+00
aa000000-0000-4000-8000-000000000053	a8000000-0000-4000-8000-000000000018	status_changed	{"to": "confirmed"}	2026-08-03 09:06:41.736+00
aa000000-0000-4000-8000-000000000054	a8000000-0000-4000-8000-000000000018	payment_status_changed	{"to": "paid"}	2026-08-03 09:06:41.736+00
aa000000-0000-4000-8000-000000000055	a8000000-0000-4000-8000-000000000019	order_placed	{"total": 1890, "source": "demo-seed", "subtotal": 1890}	2026-07-29 09:06:41.736+00
aa000000-0000-4000-8000-000000000056	a8000000-0000-4000-8000-000000000019	status_changed	{"to": "cancelled"}	2026-07-30 09:06:41.736+00
aa000000-0000-4000-8000-000000000058	a8000000-0000-4000-8000-000000000020	order_placed	{"total": 5610, "source": "demo-seed", "subtotal": 5410}	2026-07-27 09:06:41.736+00
aa000000-0000-4000-8000-000000000059	a8000000-0000-4000-8000-000000000020	status_changed	{"to": "delivered"}	2026-07-28 09:06:41.736+00
aa000000-0000-4000-8000-000000000060	a8000000-0000-4000-8000-000000000020	payment_status_changed	{"to": "paid"}	2026-07-28 09:06:41.736+00
cb9c6af1-f202-4761-a96a-5d16c3667124	fc062098-b9c7-459a-bddb-70903a5bf5b2	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 143.50}	2026-08-03 09:51:54.352147+00
a814ecf2-c55a-4db8-9668-44fd029a8276	0b01e434-5c12-4302-97c6-13910a84bf8e	order_placed	{"delivery_type": "delivery", "payment_method": "cod", "discount_amount": 0.00}	2026-08-03 09:51:58.936228+00
b401e88c-25c3-4967-a102-6c5f673ccae1	fc062098-b9c7-459a-bddb-70903a5bf5b2	payment_status_changed	{"to": "paid", "from": "pending"}	2026-08-03 09:52:01.163083+00
9e27213d-b352-4068-a784-91d697db37ed	a362d405-d226-4115-80f6-505fb3b49c21	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 303.00}	2026-08-04 05:43:34.581033+00
dac297f1-65d2-43b8-87bb-9bdc7159b522	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	payment_status_changed	{"to": "paid", "from": "pending"}	2026-08-04 06:28:13.975674+00
bc4d275c-c9af-438d-a32d-6cbf01b331cb	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	status_changed	{"to": "ready_for_pickup", "from": "confirmed", "note": "paid"}	2026-08-04 06:28:34.327318+00
a74fe036-5330-4b54-b815-344a5e6a57a7	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	status_changed	{"to": "delivered", "from": "ready_for_pickup", "note": "paid"}	2026-08-04 06:28:47.464271+00
0763beb7-ff71-40c9-b9b0-df89089a4b08	21ce8844-157e-4cd8-9e93-2c4d20256a76	payment_status_changed	{"to": "paid", "from": "pending", "payment_id": "f263608a-3b96-4567-92e6-b7caed70e008", "receipt_number": "MOCK26273387"}	2026-08-13 13:04:33.598963+00
77bf6dd4-2d24-48d9-b0fe-859ac207bbf8	0fd23557-0657-4851-921a-ea57514435d3	order_cancelled	{"cancelled_by": "customer", "previous_status": "pending"}	2026-08-13 13:10:15.315081+00
69b6c37a-fd53-4e91-8cef-bb4ba9086700	cf7e6989-10b8-46dd-bc8b-ac01dd6b6c8a	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 0.00}	2026-08-31 08:01:17.544622+00
1daff5a6-3641-42d6-9f91-88bb9af070cb	cf7e6989-10b8-46dd-bc8b-ac01dd6b6c8a	order_cancelled	{"cancelled_by": "customer", "previous_status": "pending"}	2026-08-31 08:01:18.405392+00
0bda0eda-866c-416b-ae21-b395eb84e269	f710542d-9cd5-4ed9-b385-cfb566927894	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 289.00}	2026-08-31 08:01:22.45735+00
c8a7b770-9992-434e-8f3c-00babb15816a	f710542d-9cd5-4ed9-b385-cfb566927894	status_changed	{"to": "confirmed", "from": "pending", "note": null}	2026-08-31 08:01:22.700242+00
15cb62ed-ea7f-42cb-aadd-5f4e843559cd	f710542d-9cd5-4ed9-b385-cfb566927894	payment_status_changed	{"to": "paid", "from": "pending"}	2026-08-31 08:01:22.955314+00
e048fb18-3eaa-47e8-b11b-ef8bae7f1498	fed1e53b-9c95-4d88-96b8-579367bb356c	order_placed	{"delivery_type": "delivery", "payment_method": "cod", "discount_amount": 0.00}	2026-08-03 09:49:03.818326+00
4a138db6-43f1-4f8f-87ba-ac3fcaae801f	26372fc4-819d-4b5c-88bd-6eb628dbe1c4	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 0.00}	2026-08-03 09:49:09.610807+00
aa000000-0000-4000-8000-000000000001	a8000000-0000-4000-8000-000000000001	order_placed	{"total": 2970, "source": "demo-seed", "subtotal": 2770}	2026-07-06 09:06:41.735+00
aa000000-0000-4000-8000-000000000002	a8000000-0000-4000-8000-000000000001	status_changed	{"to": "delivered"}	2026-07-07 09:06:41.735+00
aa000000-0000-4000-8000-000000000003	a8000000-0000-4000-8000-000000000001	payment_status_changed	{"to": "paid"}	2026-07-07 09:06:41.735+00
aa000000-0000-4000-8000-000000000004	a8000000-0000-4000-8000-000000000002	order_placed	{"total": 2999, "source": "demo-seed", "subtotal": 2999}	2026-07-13 09:06:41.735+00
aa000000-0000-4000-8000-000000000005	a8000000-0000-4000-8000-000000000002	status_changed	{"to": "delivered"}	2026-07-14 09:06:41.735+00
aa000000-0000-4000-8000-000000000006	a8000000-0000-4000-8000-000000000002	payment_status_changed	{"to": "paid"}	2026-07-14 09:06:41.735+00
aa000000-0000-4000-8000-000000000007	a8000000-0000-4000-8000-000000000003	order_placed	{"total": 4580, "source": "demo-seed", "subtotal": 4380}	2026-07-09 09:06:41.735+00
aa000000-0000-4000-8000-000000000008	a8000000-0000-4000-8000-000000000003	status_changed	{"to": "delivered"}	2026-07-10 09:06:41.735+00
aa000000-0000-4000-8000-000000000009	a8000000-0000-4000-8000-000000000003	payment_status_changed	{"to": "paid"}	2026-07-10 09:06:41.735+00
aa000000-0000-4000-8000-000000000010	a8000000-0000-4000-8000-000000000004	order_placed	{"total": 6090, "source": "demo-seed", "subtotal": 5890}	2026-07-20 09:06:41.735+00
aa000000-0000-4000-8000-000000000011	a8000000-0000-4000-8000-000000000004	status_changed	{"to": "shipped"}	2026-07-21 09:06:41.735+00
aa000000-0000-4000-8000-000000000012	a8000000-0000-4000-8000-000000000004	payment_status_changed	{"to": "paid"}	2026-07-21 09:06:41.735+00
aa000000-0000-4000-8000-000000000013	a8000000-0000-4000-8000-000000000005	order_placed	{"total": 6190, "source": "demo-seed", "subtotal": 5990}	2026-07-16 09:06:41.735+00
aa000000-0000-4000-8000-000000000014	a8000000-0000-4000-8000-000000000005	status_changed	{"to": "delivered"}	2026-07-17 09:06:41.735+00
aa000000-0000-4000-8000-000000000015	a8000000-0000-4000-8000-000000000005	payment_status_changed	{"to": "paid"}	2026-07-17 09:06:41.735+00
aa000000-0000-4000-8000-000000000016	a8000000-0000-4000-8000-000000000006	order_placed	{"total": 9190, "source": "demo-seed", "subtotal": 8990}	2026-07-25 09:06:41.735+00
aa000000-0000-4000-8000-000000000017	a8000000-0000-4000-8000-000000000006	status_changed	{"to": "processing"}	2026-07-26 09:06:41.735+00
aa000000-0000-4000-8000-000000000018	a8000000-0000-4000-8000-000000000006	payment_status_changed	{"to": "paid"}	2026-07-26 09:06:41.735+00
f79259fe-d745-4558-a1d9-c264b6ea0c10	fc062098-b9c7-459a-bddb-70903a5bf5b2	status_changed	{"to": "confirmed", "from": "pending", "note": "qa"}	2026-08-03 09:52:35.769841+00
7ce3fe00-163a-41d6-aef9-23a73d1889d0	fc062098-b9c7-459a-bddb-70903a5bf5b2	status_changed	{"to": "ready_for_pickup", "from": "confirmed", "note": "qa"}	2026-08-03 09:52:36.052672+00
b738bd29-3046-45a8-9abe-1a02efc62447	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 629.00}	2026-08-04 06:25:14.343959+00
1e34dc56-1f66-4a3e-b67b-aec8c94843ca	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	status_changed	{"to": "confirmed", "from": "pending", "note": "paid"}	2026-08-04 06:28:19.777203+00
13bd83ec-056d-4b79-aa5f-aeee4235d2fc	21ce8844-157e-4cd8-9e93-2c4d20256a76	order_placed	{"delivery_type": "delivery", "payment_method": "mpesa", "discount_amount": 318.00}	2026-08-13 13:04:29.263909+00
f2222304-8c06-453d-9967-f467a9e83cc2	0fd23557-0657-4851-921a-ea57514435d3	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 318.00}	2026-08-13 13:08:22.004022+00
1ac2df78-b3fb-428f-923d-e2bd6285e203	f85d863c-b81e-49e9-8451-7980551af330	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 417.00}	2026-08-13 15:11:45.293916+00
4f56af14-ecc6-41df-ab64-9944ba442fd1	f710542d-9cd5-4ed9-b385-cfb566927894	order_cancelled	{"cancelled_by": "admin", "previous_status": "confirmed"}	2026-08-31 08:01:23.760515+00
e21f8a94-6eb0-45b9-a4dd-75abb94e7d5b	f9ba3141-6266-43c0-8d88-3b73872e1e04	order_placed	{"delivery_type": "delivery", "payment_method": "cod", "discount_amount": 289.00}	2026-08-31 08:01:44.999783+00
05416be2-1c45-42ef-8e8e-d1445a320819	f9ba3141-6266-43c0-8d88-3b73872e1e04	order_cancelled	{"cancelled_by": "customer", "previous_status": "pending"}	2026-08-31 08:01:45.593066+00
9267381f-e2a8-4352-93c3-850ea1105f39	42db9ff7-2c64-4a03-8dce-f468db78d39a	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 489.00}	2026-08-31 08:01:46.861171+00
3a54f58b-8e24-41f5-986c-01b08778bff3	42db9ff7-2c64-4a03-8dce-f468db78d39a	order_cancelled	{"cancelled_by": "customer", "previous_status": "pending"}	2026-08-31 08:01:47.657291+00
d495b0e9-56c2-4bd8-b4c9-f7564f166a44	f0f39871-54d9-4d80-9d91-9c5797386384	order_placed	{"delivery_type": "delivery", "payment_method": "cod", "discount_amount": 289.00}	2026-08-31 08:01:48.675828+00
6737b784-3776-4a23-b84d-486ef357ccec	f0f39871-54d9-4d80-9d91-9c5797386384	order_cancelled	{"cancelled_by": "customer", "previous_status": "pending"}	2026-08-31 08:01:49.584052+00
0ef69547-d299-4d4b-805d-0edd4b3a8641	9089649b-aa41-4a73-8d49-1dc2c7b7962a	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 289.00}	2026-08-31 08:01:51.191813+00
9b72546c-f5ea-4e00-b829-724308168122	9089649b-aa41-4a73-8d49-1dc2c7b7962a	order_cancelled	{"cancelled_by": "customer", "previous_status": "pending"}	2026-08-31 08:01:51.743373+00
a10a5fd6-c9ae-4fdc-b8fd-2e1fb74d5ef6	914ce1a1-8697-4df6-831c-960f820e95fb	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 289.00}	2026-08-31 08:04:37.242615+00
19d3e649-5d5f-4992-b752-53500ea18d7c	914ce1a1-8697-4df6-831c-960f820e95fb	order_cancelled	{"cancelled_by": "customer", "previous_status": "pending"}	2026-08-31 08:04:38.256036+00
a138f954-0a41-4d04-bcec-ff11a5a8ecdb	85012229-01dc-46f4-a019-327397f8169c	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 289.00}	2026-08-31 08:04:43.820448+00
84595a7d-b2a6-43b1-9e5b-bc57e9fbb3cc	85012229-01dc-46f4-a019-327397f8169c	status_changed	{"to": "confirmed", "from": "pending", "note": null}	2026-08-31 08:04:44.428873+00
81023ffa-a693-4f48-92b7-1cc4b4b74a6d	85012229-01dc-46f4-a019-327397f8169c	order_cancelled	{"cancelled_by": "admin", "previous_status": "confirmed"}	2026-08-31 08:04:46.016305+00
d8b8d2ae-c39f-4517-a819-47ec3bcd7390	482bcf5a-fb88-44f1-bda9-b219d8d84373	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 289.00}	2026-08-31 08:05:43.962896+00
fe0c1155-83fc-4f84-a8e2-5b520dd439a1	482bcf5a-fb88-44f1-bda9-b219d8d84373	payment_status_changed	{"to": "paid", "from": "pending"}	2026-08-31 08:05:44.389276+00
b36f75e6-595c-4855-9dba-2f14545559d6	482bcf5a-fb88-44f1-bda9-b219d8d84373	order_cancelled	{"cancelled_by": "admin", "previous_status": "pending"}	2026-08-31 08:05:46.048609+00
81a605f7-b0ae-4f85-b35e-8d84c3a7dd93	9a5dae2b-0b91-49fd-8ed2-a787e9a2d571	order_placed	{"delivery_type": "pickup", "payment_method": "cod", "discount_amount": 722.50}	2026-08-31 08:06:15.826436+00
d7c5d960-1630-43ff-9dbc-2cc9933c5105	9a5dae2b-0b91-49fd-8ed2-a787e9a2d571	order_cancelled	{"cancelled_by": "customer", "previous_status": "pending"}	2026-08-31 08:06:16.552568+00
\.


--
-- Data for Name: order_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.order_items (id, order_id, product_id, quantity, price, name, image_url, created_at) FROM stdin;
981ab893-2718-42bc-bc93-e923bf16f075	bdbf4160-0027-43c9-a2b9-a1289e75b84c	8638477e-f5a6-4c64-ae48-0743947ca67c	3	20.00	t-shirt	https://qfcygrxrfszcdltangec.supabase.co/storage/v1/object/public/products/products/8638477e-f5a6-4c64-ae48-0743947ca67c/d1402a3c-d4f0-4d45-96f7-d7f946ebb56c.jpeg	2026-07-13 09:08:43.43044+00
bf612061-b89a-478e-9f29-947baa46a9b5	43cd4c98-d8f5-4575-bc44-0170a423543f	3ee87063-de7d-4e6c-b91c-177e9c1a4946	1	3500	Kalimba Pro 17'	\N	2026-07-13 09:24:46.827239+00
cb71da2e-1eb2-4225-b652-988f096a024d	43cd4c98-d8f5-4575-bc44-0170a423543f	8638477e-f5a6-4c64-ae48-0743947ca67c	3	20.00	t-shirt	https://qfcygrxrfszcdltangec.supabase.co/storage/v1/object/public/products/products/8638477e-f5a6-4c64-ae48-0743947ca67c/d1402a3c-d4f0-4d45-96f7-d7f946ebb56c.jpeg	2026-07-13 09:24:46.827239+00
a9000000-0000-4000-8000-000000000061	a8000000-0000-4000-8000-000000000007	a2000000-0000-4000-8000-000000000003	1	2890	Fleece Hoodie — Charcoal	placeholders/hoodie-charcoal.jpg	2026-07-18 09:06:41.735+00
a9000000-0000-4000-8000-000000000062	a8000000-0000-4000-8000-000000000007	a2000000-0000-4000-8000-000000000007	1	2790	Slim Fit Jeans — Indigo	placeholders/jeans-indigo.jpg	2026-07-18 09:06:41.735+00
a9000000-0000-4000-8000-000000000071	a8000000-0000-4000-8000-000000000008	a2000000-0000-4000-8000-000000000030	1	1790	Ceramic Coffee Mug Set (4)	placeholders/mugs-set-4.jpg	2026-07-28 09:06:41.735+00
a9000000-0000-4000-8000-000000000072	a8000000-0000-4000-8000-000000000008	a2000000-0000-4000-8000-000000000034	2	2100	Food Storage Containers (6-Pack)	placeholders/containers-food-6.jpg	2026-07-28 09:06:41.735+00
a9000000-0000-4000-8000-000000000081	a8000000-0000-4000-8000-000000000009	a2000000-0000-4000-8000-000000000044	1	3490	Everyday Backpack — Slate	placeholders/backpack-slate.jpg	2026-07-14 09:06:41.735+00
a9000000-0000-4000-8000-000000000082	a8000000-0000-4000-8000-000000000009	a2000000-0000-4000-8000-000000000045	1	2290	Leather Wallet — Cognac	placeholders/wallet-cognac.jpg	2026-07-14 09:06:41.735+00
a9000000-0000-4000-8000-000000000091	a8000000-0000-4000-8000-000000000010	a2000000-0000-4000-8000-000000000018	1	3200	Power Bank 20,000 mAh	placeholders/powerbank-20000.jpg	2026-07-30 09:06:41.735+00
a9000000-0000-4000-8000-000000000101	a8000000-0000-4000-8000-000000000011	a2000000-0000-4000-8000-000000000013	1	1890	Leather Slide Sandals — Tan	placeholders/sandals-tan.jpg	2026-07-12 09:06:41.735+00
a9000000-0000-4000-8000-000000000111	a8000000-0000-4000-8000-000000000012	a2000000-0000-4000-8000-000000000037	1	1290	Stuffed Bear — Honey	placeholders/bear-stuffed-honey.jpg	2026-07-23 09:06:41.736+00
a9000000-0000-4000-8000-000000000112	a8000000-0000-4000-8000-000000000012	a2000000-0000-4000-8000-000000000040	1	650	Educational Flash Cards	placeholders/cards-educational.jpg	2026-07-23 09:06:41.736+00
a9000000-0000-4000-8000-000000000121	a8000000-0000-4000-8000-000000000013	a2000000-0000-4000-8000-000000000024	1	990	Portable Desk Fan — Mini	placeholders/fan-portable-mini.jpg	2026-07-19 09:06:41.736+00
a9000000-0000-4000-8000-000000000122	a8000000-0000-4000-8000-000000000013	a2000000-0000-4000-8000-000000000025	1	2190	LED Desk Lamp — Warm White	placeholders/desk-lamp-led.jpg	2026-07-19 09:06:41.736+00
a9000000-0000-4000-8000-000000000131	a8000000-0000-4000-8000-000000000014	a2000000-0000-4000-8000-000000000005	1	4500	Light Bomber Jacket — Black	placeholders/jacket-bomber-black.jpg	2026-07-31 09:06:41.736+00
a9000000-0000-4000-8000-000000000141	a8000000-0000-4000-8000-000000000015	a2000000-0000-4000-8000-000000000031	1	1450	Kitchen Drawer Organizer	placeholders/kitchen-organizer.jpg	2026-07-15 09:06:41.736+00
a9000000-0000-4000-8000-000000000142	a8000000-0000-4000-8000-000000000015	a2000000-0000-4000-8000-000000000048	2	750	Gentle Care Shampoo 350ml	placeholders/shampoo-gentle-350.jpg	2026-07-15 09:06:41.736+00
a9000000-0000-4000-8000-000000000151	a8000000-0000-4000-8000-000000000016	a2000000-0000-4000-8000-000000000050	1	4290	Weekend Travel Bag — Navy	placeholders/travel-bag-navy.jpg	2026-07-26 09:06:41.736+00
a9000000-0000-4000-8000-000000000161	a8000000-0000-4000-8000-000000000017	a2000000-0000-4000-8000-000000000021	1	1290	Wireless Mouse — Graphite	placeholders/mouse-graphite.jpg	2026-08-01 09:06:41.736+00
a9000000-0000-4000-8000-000000000162	a8000000-0000-4000-8000-000000000017	a2000000-0000-4000-8000-000000000022	1	3890	USB-C Hub 7-in-1	placeholders/usb-hub-7in1.jpg	2026-08-01 09:06:41.736+00
a9000000-0000-4000-8000-000000000171	a8000000-0000-4000-8000-000000000018	a2000000-0000-4000-8000-000000000002	3	1200	Graphic Tee — City Lines	placeholders/tee-graphic-navy.jpg	2026-08-02 09:06:41.736+00
a9000000-0000-4000-8000-000000000181	a8000000-0000-4000-8000-000000000019	a2000000-0000-4000-8000-000000000042	1	1890	Junior Basketball Size 5	placeholders/basketball-size5.jpg	2026-07-29 09:06:41.736+00
a9000000-0000-4000-8000-000000000191	a8000000-0000-4000-8000-000000000020	a2000000-0000-4000-8000-000000000027	2	890	Throw Pillow Cover — Terracotta	placeholders/pillow-terracotta.jpg	2026-07-27 09:06:41.736+00
a9000000-0000-4000-8000-000000000192	a8000000-0000-4000-8000-000000000020	a2000000-0000-4000-8000-000000000028	2	1590	Silent Wall Clock — Oak Frame	placeholders/clock-oak.jpg	2026-07-27 09:06:41.736+00
a9000000-0000-4000-8000-000000000193	a8000000-0000-4000-8000-000000000020	a2000000-0000-4000-8000-000000000043	1	450	Skipping Rope — Adjustable	placeholders/rope-skipping.jpg	2026-07-27 09:06:41.736+00
11045ec0-6519-494e-afd6-e8598afe7d1e	fed1e53b-9c95-4d88-96b8-579367bb356c	a2000000-0000-4000-8000-000000000001	1	890	Essential Cotton Tee — White	placeholders/tee-white.jpg	2026-08-03 09:49:03.818326+00
73990fcc-7196-4007-823e-e022bcb828ef	26372fc4-819d-4b5c-88bd-6eb628dbe1c4	a2000000-0000-4000-8000-000000000001	1	890	Essential Cotton Tee — White	placeholders/tee-white.jpg	2026-08-03 09:49:09.610807+00
1bc0f12c-baa7-47a7-8632-809698a7fe7e	fc062098-b9c7-459a-bddb-70903a5bf5b2	a2000000-0000-4000-8000-000000000001	1	890	Essential Cotton Tee — White	placeholders/tee-white.jpg	2026-08-03 09:51:54.352147+00
b8460f8c-7ded-428c-8b87-77d0ab810fc6	0b01e434-5c12-4302-97c6-13910a84bf8e	a2000000-0000-4000-8000-000000000001	1	890	Essential Cotton Tee — White	placeholders/tee-white.jpg	2026-08-03 09:51:58.936228+00
87dcc3ae-031c-48cd-80f4-34d585620688	a362d405-d226-4115-80f6-505fb3b49c21	a2000000-0000-4000-8000-000000000028	1	1590	Silent Wall Clock — Oak Frame	https://images.unsplash.com/photo-1563861826100-9cb668332e1b?auto=format&fit=crop&w=1200&q=80	2026-08-04 05:43:34.581033+00
50bcf18e-9500-458f-bed0-bfea848bf458	a362d405-d226-4115-80f6-505fb3b49c21	a2000000-0000-4000-8000-000000000043	1	450	Skipping Rope — Adjustable	https://images.unsplash.com/photo-1599058917212-d750089bc07e?auto=format&fit=crop&w=1200&q=80	2026-08-04 05:43:34.581033+00
dc3d07f5-c4c7-4673-8d2d-ec6513c910f9	a362d405-d226-4115-80f6-505fb3b49c21	a2000000-0000-4000-8000-000000000035	1	990	Desk Organizer Tray	https://images.unsplash.com/photo-1593062096033-9a26b09da705?auto=format&fit=crop&w=1200&q=80	2026-08-04 05:43:34.581033+00
fce60cf1-7eb6-4ffb-bf7e-deaeb558df33	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	a2000000-0000-4000-8000-000000000001	1	890	Essential Cotton Tee — White	https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=1200&q=80	2026-08-04 06:25:14.343959+00
1947d654-d1e5-4942-8d6c-dd7a9f887a2e	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	a2000000-0000-4000-8000-000000000002	1	1200.00	Graphic Tee — City Lines	https://images.unsplash.com/photo-1576566588028-4147f3842f27?auto=format&fit=crop&w=1200&q=80	2026-08-04 06:25:14.343959+00
f608a43c-6e59-4c2d-a531-4fb410695b03	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	a2000000-0000-4000-8000-000000000011	1	4200	Urban Runner Sneakers — White	https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=1200&q=80	2026-08-04 06:25:14.343959+00
a9000000-0000-4000-8000-000000000001	a8000000-0000-4000-8000-000000000001	a2000000-0000-4000-8000-000000000001	2	890	Essential Cotton Tee — White	placeholders/tee-white.jpg	2026-07-06 09:06:41.734+00
a9000000-0000-4000-8000-000000000002	a8000000-0000-4000-8000-000000000001	a2000000-0000-4000-8000-000000000015	1	990	Structured Cap — Black	placeholders/cap-black.jpg	2026-07-06 09:06:41.734+00
a9000000-0000-4000-8000-000000000011	a8000000-0000-4000-8000-000000000002	a2000000-0000-4000-8000-000000000016	1	2999	Wireless Earbuds — Pearl White	placeholders/earbuds-white.jpg	2026-07-13 09:06:41.735+00
a9000000-0000-4000-8000-000000000021	a8000000-0000-4000-8000-000000000003	a2000000-0000-4000-8000-000000000009	1	3490	Linen Midi Dress — Sand	placeholders/dress-sand.jpg	2026-07-09 09:06:41.735+00
a9000000-0000-4000-8000-000000000022	a8000000-0000-4000-8000-000000000003	a2000000-0000-4000-8000-000000000047	1	890	Shea Body Lotion 400ml	placeholders/lotion-shea-400.jpg	2026-07-09 09:06:41.735+00
a9000000-0000-4000-8000-000000000031	a8000000-0000-4000-8000-000000000004	a2000000-0000-4000-8000-000000000011	1	4200	Urban Runner Sneakers — White	placeholders/sneakers-white.jpg	2026-07-20 09:06:41.735+00
a9000000-0000-4000-8000-000000000032	a8000000-0000-4000-8000-000000000004	a2000000-0000-4000-8000-000000000033	1	1690	Insulated Water Bottle 750ml	placeholders/bottle-750-steel.jpg	2026-07-20 09:06:41.735+00
a9000000-0000-4000-8000-000000000041	a8000000-0000-4000-8000-000000000005	a2000000-0000-4000-8000-000000000017	1	4500	Bluetooth Speaker — Midnight	placeholders/speaker-midnight.jpg	2026-07-16 09:06:41.735+00
a9000000-0000-4000-8000-000000000042	a8000000-0000-4000-8000-000000000005	a2000000-0000-4000-8000-000000000019	1	1490	USB-C Fast Phone Charger 30W	placeholders/charger-usbc-30w.jpg	2026-07-16 09:06:41.735+00
a9000000-0000-4000-8000-000000000051	a8000000-0000-4000-8000-000000000006	a2000000-0000-4000-8000-000000000020	1	6500	Smart Watch — Active Fit	placeholders/smartwatch-active.jpg	2026-07-25 09:06:41.735+00
a9000000-0000-4000-8000-000000000052	a8000000-0000-4000-8000-000000000006	a2000000-0000-4000-8000-000000000023	1	2490	Aluminium Laptop Stand	placeholders/laptop-stand-silver.jpg	2026-07-25 09:06:41.735+00
3b31d15f-d625-4fa8-a7b2-c0298090dd8e	21ce8844-157e-4cd8-9e93-2c4d20256a76	a2000000-0000-4000-8000-000000000045	1	2290	Leather Wallet — Cognac	https://images.unsplash.com/photo-1627123424574-724758594e93?auto=format&fit=crop&w=1200&q=80	2026-08-13 13:04:29.263909+00
b7c04be9-282c-4eb1-86f4-8d299288d478	21ce8844-157e-4cd8-9e93-2c4d20256a76	a2000000-0000-4000-8000-000000000027	1	890	Throw Pillow Cover — Terracotta	https://images.unsplash.com/photo-1584100936595-c0654b55a2e2?auto=format&fit=crop&w=1200&q=80	2026-08-13 13:04:29.263909+00
d1fcd705-b66f-45e6-b872-fcf44e55fb39	0fd23557-0657-4851-921a-ea57514435d3	a2000000-0000-4000-8000-000000000045	1	2290	Leather Wallet — Cognac	https://images.unsplash.com/photo-1627123424574-724758594e93?auto=format&fit=crop&w=1200&q=80	2026-08-13 13:08:22.004022+00
f81faccc-d6d4-4ee1-b069-62cbbc05d28e	0fd23557-0657-4851-921a-ea57514435d3	a2000000-0000-4000-8000-000000000027	1	890	Throw Pillow Cover — Terracotta	https://images.unsplash.com/photo-1584100936595-c0654b55a2e2?auto=format&fit=crop&w=1200&q=80	2026-08-13 13:08:22.004022+00
85972ca3-d353-4930-817d-e74e918664a4	f85d863c-b81e-49e9-8451-7980551af330	a2000000-0000-4000-8000-000000000046	1	1990.00	Polarized Sunglasses — Tortoise	https://images.unsplash.com/photo-1511499767150-a48a237f0083?auto=format&fit=crop&w=1200&q=80	2026-08-13 15:11:45.293916+00
b4c9daeb-4d12-492c-a422-14c35fcc7118	f85d863c-b81e-49e9-8451-7980551af330	a2000000-0000-4000-8000-000000000029	1	1290	Collapsible Laundry Basket	https://images.unsplash.com/photo-1582735689369-4fe89db7114c?auto=format&fit=crop&w=1200&q=80	2026-08-13 15:11:45.293916+00
1b729d6d-7a03-4025-9ddc-c34c8b42dafe	f85d863c-b81e-49e9-8451-7980551af330	a2000000-0000-4000-8000-000000000047	1	890	Shea Body Lotion 400ml	https://images.unsplash.com/photo-1556228578-0d85b1a4d571?auto=format&fit=crop&w=1200&q=80	2026-08-13 15:11:45.293916+00
6be15abe-e8c8-450a-98a3-6a9227194060	cf7e6989-10b8-46dd-bc8b-ac01dd6b6c8a	a2000000-0000-4000-8000-000000000043	1	450	Skipping Rope — Adjustable	https://images.unsplash.com/photo-1599058917212-d750089bc07e?auto=format&fit=crop&w=1200&q=80	2026-08-31 08:01:17.544622+00
16c8d707-5d65-4807-aeb2-887f5b88ea3f	f710542d-9cd5-4ed9-b385-cfb566927894	a2000000-0000-4000-8000-000000000003	1	2890	Fleece Hoodie — Charcoal	https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1200&q=80	2026-08-31 08:01:22.45735+00
03787906-f465-4faa-b058-56253cd3157d	f9ba3141-6266-43c0-8d88-3b73872e1e04	a2000000-0000-4000-8000-000000000003	1	2890	Fleece Hoodie — Charcoal	https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1200&q=80	2026-08-31 08:01:44.999783+00
40c4b003-e4a0-4f52-af66-5104d7e93b17	42db9ff7-2c64-4a03-8dce-f468db78d39a	a2000000-0000-4000-8000-000000000003	1	2890	Fleece Hoodie — Charcoal	https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1200&q=80	2026-08-31 08:01:46.861171+00
428e5384-c983-4d30-8a3e-55418a256093	f0f39871-54d9-4d80-9d91-9c5797386384	a2000000-0000-4000-8000-000000000003	1	2890	Fleece Hoodie — Charcoal	https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1200&q=80	2026-08-31 08:01:48.675828+00
35e6d31e-1f07-44e8-b530-2b6a0219d6f6	9089649b-aa41-4a73-8d49-1dc2c7b7962a	a2000000-0000-4000-8000-000000000003	1	2890	Fleece Hoodie — Charcoal	https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1200&q=80	2026-08-31 08:01:51.191813+00
8bab1afd-97ab-4407-a548-50be8ba0b8a0	914ce1a1-8697-4df6-831c-960f820e95fb	a2000000-0000-4000-8000-000000000003	1	2890	Fleece Hoodie — Charcoal	https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1200&q=80	2026-08-31 08:04:37.242615+00
a9a32bd6-7fc4-4f49-96b0-4ea2dfaa1bca	85012229-01dc-46f4-a019-327397f8169c	a2000000-0000-4000-8000-000000000003	1	2890	Fleece Hoodie — Charcoal	https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1200&q=80	2026-08-31 08:04:43.820448+00
92780033-ead4-4735-b81a-1d93064df604	482bcf5a-fb88-44f1-bda9-b219d8d84373	a2000000-0000-4000-8000-000000000003	1	2890	Fleece Hoodie — Charcoal	https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1200&q=80	2026-08-31 08:05:43.962896+00
feb95d00-5b6a-4c70-9c66-b2d3827dc895	9a5dae2b-0b91-49fd-8ed2-a787e9a2d571	a2000000-0000-4000-8000-000000000003	1	2890	Fleece Hoodie — Charcoal	https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1200&q=80	2026-08-31 08:06:15.826436+00
\.


--
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.orders (id, user_id, total, status, created_at, payment_status, note, updated_at, delivery_type, pickup_location_id, delivery_address, delivery_fee, customer_note, payment_method, mpesa_receipt_number, discount_amount, coupon_code, loyalty_points_redeemed, gift_card_amount, free_delivery, promotions_applied, referral_code) FROM stdin;
bdbf4160-0027-43c9-a2b9-a1289e75b84c	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	60.00	pending	2026-07-13 09:08:43.43044	pending	\N	2026-07-13 09:08:43.43044+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
43cd4c98-d8f5-4575-bc44-0170a423543f	b98a07b1-467f-4e20-ac14-da354b094637	3560.00	delivered	2026-07-13 09:24:46.827239	paid	\N	2026-07-13 09:26:37.972185+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000001	91877d22-84c1-4253-9e57-13aa5a617b1c	2970	delivered	2026-07-06 09:06:41.735	paid	demo-seed-v1	2026-07-07 09:06:41.735+00	delivery	\N	{"city": "Kilimani", "line1": "Argwings Kodhek Rd, Court 12 Apt B3", "phone": "+254722111001", "county": "Nairobi", "recipient": "Brian Mwangi"}	200.00	Please call on arrival	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000002	91877d22-84c1-4253-9e57-13aa5a617b1c	2999	delivered	2026-07-13 09:06:41.735	paid	demo-seed-v1	2026-07-14 09:06:41.735+00	pickup	a3000000-0000-4000-8000-000000000001	\N	0.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000003	ce11a1e1-39f2-471e-9c62-483ba6b04780	4580	delivered	2026-07-09 09:06:41.735	paid	demo-seed-v1	2026-07-10 09:06:41.735+00	delivery	\N	{"city": "South B", "line1": "Mukoma Road, House 7", "phone": "+254733222002", "county": "Nairobi", "recipient": "Wangechi Njeri"}	200.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000004	ce11a1e1-39f2-471e-9c62-483ba6b04780	6090	shipped	2026-07-20 09:06:41.735	paid	demo-seed-v1	2026-07-21 09:06:41.735+00	delivery	\N	{"city": "South B", "line1": "Mukoma Road, House 7", "phone": "+254733222002", "county": "Nairobi", "recipient": "Wangechi Njeri"}	200.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000005	ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7	6190	delivered	2026-07-16 09:06:41.735	paid	demo-seed-v1	2026-07-17 09:06:41.735+00	delivery	\N	{"city": "Ruiru", "line1": "Eastern Bypass, Greenview Estate Block C", "phone": "+254700333003", "county": "Kiambu", "recipient": "Kevin Ochieng"}	200.00	Please call on arrival	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000006	ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7	9190	processing	2026-07-25 09:06:41.735	paid	demo-seed-v1	2026-07-26 09:06:41.735+00	delivery	\N	{"city": "Ruiru", "line1": "Eastern Bypass, Greenview Estate Block C", "phone": "+254700333003", "county": "Kiambu", "recipient": "Kevin Ochieng"}	200.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000007	328a2e81-1496-404e-88c4-d7f45b72a1b6	5680	delivered	2026-07-18 09:06:41.735	paid	demo-seed-v1	2026-07-19 09:06:41.735+00	pickup	a3000000-0000-4000-8000-000000000002	\N	0.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000008	328a2e81-1496-404e-88c4-d7f45b72a1b6	6190	confirmed	2026-07-28 09:06:41.735	paid	demo-seed-v1	2026-07-29 09:06:41.735+00	delivery	\N	{"city": "Westlands", "line1": "Ring Road Parklands, Flat 9A", "phone": "+254711444004", "county": "Nairobi", "recipient": "Faith Wambui"}	200.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000009	1f33a52d-a5b9-475a-bf28-857045f4ad09	5980	delivered	2026-07-14 09:06:41.735	paid	demo-seed-v1	2026-07-15 09:06:41.735+00	delivery	\N	{"city": "Lavington", "line1": "James Gichuru Road, Villa 3", "phone": "+254722555005", "county": "Nairobi", "recipient": "Daniel Kiprop"}	200.00	Please call on arrival	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000010	1f33a52d-a5b9-475a-bf28-857045f4ad09	3400	pending	2026-07-30 09:06:41.735	pending	demo-seed-v1	2026-07-31 09:06:41.735+00	delivery	\N	{"city": "Lavington", "line1": "James Gichuru Road, Villa 3", "phone": "+254722555005", "county": "Nairobi", "recipient": "Daniel Kiprop"}	200.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000011	a9c07a6f-4063-4793-a3a0-129d96a50e02	1890	cancelled	2026-07-12 09:06:41.735	refunded	demo-seed-v1	2026-07-13 09:06:41.735+00	delivery	\N	{"city": "Kitengela", "line1": "Namanga Road, Acacia Courts", "phone": "+254733666006", "county": "Kajiado", "recipient": "Mercy Akinyi"}	0.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000012	a9c07a6f-4063-4793-a3a0-129d96a50e02	1940	ready_for_pickup	2026-07-23 09:06:41.736	paid	demo-seed-v1	2026-07-24 09:06:41.736+00	pickup	a3000000-0000-4000-8000-000000000001	\N	0.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000013	a2a071d2-da64-4571-9f17-288c5abd72dc	3380	delivered	2026-07-19 09:06:41.736	paid	demo-seed-v1	2026-07-20 09:06:41.736+00	delivery	\N	{"city": "Eastleigh", "line1": "1st Avenue, Shopfront collection", "phone": "+254700777007", "county": "Nairobi", "recipient": "James Mutiso"}	200.00	Please call on arrival	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000014	a2a071d2-da64-4571-9f17-288c5abd72dc	4700	processing	2026-07-31 09:06:41.736	paid	demo-seed-v1	2026-08-01 09:06:41.736+00	delivery	\N	{"city": "Eastleigh", "line1": "1st Avenue, Shopfront collection", "phone": "+254700777007", "county": "Nairobi", "recipient": "James Mutiso"}	200.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000015	d32dcbba-ff92-4df5-bb3e-089d16a5141e	3150	delivered	2026-07-15 09:06:41.736	paid	demo-seed-v1	2026-07-16 09:06:41.736+00	delivery	\N	{"city": "Karen", "line1": "Bogani Road, Cottage 5", "phone": "+254711888008", "county": "Nairobi", "recipient": "Lucy Cherono"}	200.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000016	d32dcbba-ff92-4df5-bb3e-089d16a5141e	4490	shipped	2026-07-26 09:06:41.736	paid	demo-seed-v1	2026-07-27 09:06:41.736+00	delivery	\N	{"city": "Karen", "line1": "Bogani Road, Cottage 5", "phone": "+254711888008", "county": "Nairobi", "recipient": "Lucy Cherono"}	200.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000017	91877d22-84c1-4253-9e57-13aa5a617b1c	5180	pending	2026-08-01 09:06:41.736	pending	demo-seed-v1	2026-08-02 09:06:41.736+00	pickup	a3000000-0000-4000-8000-000000000003	\N	0.00	Please call on arrival	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000018	ce11a1e1-39f2-471e-9c62-483ba6b04780	3800	confirmed	2026-08-02 09:06:41.736	paid	demo-seed-v1	2026-08-03 09:06:41.736+00	delivery	\N	{"city": "South B", "line1": "Mukoma Road, House 7", "phone": "+254733222002", "county": "Nairobi", "recipient": "Wangechi Njeri"}	200.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000019	ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7	1890	cancelled	2026-07-29 09:06:41.736	failed	demo-seed-v1	2026-07-30 09:06:41.736+00	delivery	\N	{"city": "Ruiru", "line1": "Eastern Bypass, Greenview Estate Block C", "phone": "+254700333003", "county": "Kiambu", "recipient": "Kevin Ochieng"}	0.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
a8000000-0000-4000-8000-000000000020	328a2e81-1496-404e-88c4-d7f45b72a1b6	5610	delivered	2026-07-27 09:06:41.736	paid	demo-seed-v1	2026-07-28 09:06:41.736+00	delivery	\N	{"city": "Westlands", "line1": "Ring Road Parklands, Flat 9A", "phone": "+254711444004", "county": "Nairobi", "recipient": "Faith Wambui"}	200.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
fed1e53b-9c95-4d88-96b8-579367bb356c	91877d22-84c1-4253-9e57-13aa5a617b1c	1090.00	pending	2026-08-03 09:49:03.818326	pending	\N	2026-08-03 09:49:03.818326+00	delivery	\N	{"city": "Nairobi", "line1": "12 QA Street", "line2": "Apt 2", "notes": "gate blue", "phone": "0712345678"}	200.00	QA sprint2 delivery note	cod	\N	0.00	\N	0	0.00	f	[]	\N
26372fc4-819d-4b5c-88bd-6eb628dbe1c4	91877d22-84c1-4253-9e57-13aa5a617b1c	890.00	pending	2026-08-03 09:49:09.610807	pending	\N	2026-08-03 09:49:09.610807+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	frontend-signature-smoke	cod	\N	0.00	\N	0	0.00	f	[]	\N
0b01e434-5c12-4302-97c6-13910a84bf8e	91877d22-84c1-4253-9e57-13aa5a617b1c	890.00	pending	2026-08-03 09:51:58.936228	pending	\N	2026-08-03 09:51:58.936228+00	delivery	\N	{"city": "Nairobi", "line1": "99 Test Rd", "phone": "0700000000"}	0.00	freeship test	cod	\N	0.00	FREESHIP	0	0.00	t	[{"code": "FREESHIP", "type": "coupon"}]	\N
fc062098-b9c7-459a-bddb-70903a5bf5b2	91877d22-84c1-4253-9e57-13aa5a617b1c	726.50	ready_for_pickup	2026-08-03 09:51:54.352147	paid	qa	2026-08-03 09:52:36.052672+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	QA pickup rewards	cod	\N	143.50	WELCOME15	100	20.00	f	[{"code": "WELCOME15", "type": "coupon"}]	355F42ED
a362d405-d226-4115-80f6-505fb3b49c21	c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	2727.00	pending	2026-08-04 05:43:34.581033	pending	\N	2026-08-04 05:43:34.581033+00	pickup	a3000000-0000-4000-8000-000000000002	\N	0.00	\N	cod	\N	303.00	\N	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 303, "promoType": "storewide", "freeDelivery": false}]	\N
ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	5661.00	delivered	2026-08-04 06:25:14.343959	paid	paid	2026-08-04 06:28:47.464271+00	pickup	a3000000-0000-4000-8000-000000000003	\N	0.00	\N	cod	\N	629.00	\N	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 629, "promoType": "storewide", "freeDelivery": false}]	\N
914ce1a1-8697-4df6-831c-960f820e95fb	91877d22-84c1-4253-9e57-13aa5a617b1c	2601.00	cancelled	2026-08-31 08:04:37.242615	pending	\N	2026-08-31 08:04:38.256036+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	\N	cod	\N	289.00	\N	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 289.00, "promoType": "storewide", "freeDelivery": false}]	\N
21ce8844-157e-4cd8-9e93-2c4d20256a76	eebd94c0-8179-4619-a527-218ac9f7d5c4	3062.00	pending	2026-08-13 13:04:29.263909	paid	\N	2026-08-13 13:04:33.598963+00	delivery	\N	{"city": "KAKAMEGA", "line1": "105", "line2": "223", "notes": "", "phone": "+254740845440"}	200.00	Deliver promptly	mpesa	MOCK26273387	318.00	\N	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 318, "promoType": "storewide", "freeDelivery": false}]	\N
0fd23557-0657-4851-921a-ea57514435d3	eebd94c0-8179-4619-a527-218ac9f7d5c4	2862.00	cancelled	2026-08-13 13:08:22.004022	pending	\N	2026-08-13 13:10:15.315081+00	pickup	a3000000-0000-4000-8000-000000000002	\N	0.00	\N	cod	\N	318.00	\N	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 318, "promoType": "storewide", "freeDelivery": false}]	\N
f85d863c-b81e-49e9-8451-7980551af330	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	3753.00	pending	2026-08-13 15:11:45.293916	pending	\N	2026-08-13 15:11:45.293916+00	pickup	a3000000-0000-4000-8000-000000000002	\N	0.00	\N	cod	\N	417.00	\N	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 417, "promoType": "storewide", "freeDelivery": false}]	\N
cf7e6989-10b8-46dd-bc8b-ac01dd6b6c8a	91877d22-84c1-4253-9e57-13aa5a617b1c	450.00	cancelled	2026-08-31 08:01:17.544622	pending	\N	2026-08-31 08:01:18.405392+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	\N	cod	\N	0.00	\N	0	0.00	f	[]	\N
85012229-01dc-46f4-a019-327397f8169c	91877d22-84c1-4253-9e57-13aa5a617b1c	2601.00	cancelled	2026-08-31 08:04:43.820448	pending	\N	2026-08-31 08:04:46.016305+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	\N	cod	\N	289.00	\N	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 289.00, "promoType": "storewide", "freeDelivery": false}]	\N
f710542d-9cd5-4ed9-b385-cfb566927894	91877d22-84c1-4253-9e57-13aa5a617b1c	2601.00	cancelled	2026-08-31 08:01:22.45735	refunded	acceptance test note	2026-08-31 08:01:23.760515+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	\N	cod	\N	289.00	\N	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 289.00, "promoType": "storewide", "freeDelivery": false}]	\N
482bcf5a-fb88-44f1-bda9-b219d8d84373	91877d22-84c1-4253-9e57-13aa5a617b1c	2601.00	cancelled	2026-08-31 08:05:43.962896	refunded	acceptance note	2026-08-31 08:05:46.048609+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	\N	cod	\N	289.00	\N	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 289.00, "promoType": "storewide", "freeDelivery": false}]	\N
f9ba3141-6266-43c0-8d88-3b73872e1e04	a2a071d2-da64-4571-9f17-288c5abd72dc	2801.00	cancelled	2026-08-31 08:01:44.999783	pending	\N	2026-08-31 08:01:45.593066+00	delivery	\N	{"city": "Nairobi", "label": "Test", "line1": "123 Test St", "phone": "0712345678"}	200.00	\N	cod	\N	289.00	\N	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 289.00, "promoType": "storewide", "freeDelivery": false}]	\N
42db9ff7-2c64-4a03-8dce-f468db78d39a	a2a071d2-da64-4571-9f17-288c5abd72dc	2401.00	cancelled	2026-08-31 08:01:46.861171	pending	\N	2026-08-31 08:01:47.657291+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	\N	cod	\N	489.00	SAVE200	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 289.00, "promoType": "storewide", "freeDelivery": false}, {"id": "b1438f0a-4d47-4e2e-af1e-f43944ea231b", "code": "SAVE200", "name": "Save 200 KES", "discount": 200.00, "promoType": "coupon", "freeDelivery": false}]	\N
9a5dae2b-0b91-49fd-8ed2-a787e9a2d571	1f33a52d-a5b9-475a-bf28-857045f4ad09	2167.50	cancelled	2026-08-31 08:06:15.826436	pending	\N	2026-08-31 08:06:16.552568+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	\N	cod	\N	722.50	WELCOME15	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 289.00, "promoType": "storewide", "freeDelivery": false}, {"id": "4d419b94-7430-4bc7-bb72-e8ff0db0c644", "code": "WELCOME15", "name": "Welcome 15% off", "discount": 433.50, "promoType": "coupon", "freeDelivery": false}]	\N
f0f39871-54d9-4d80-9d91-9c5797386384	a2a071d2-da64-4571-9f17-288c5abd72dc	2601.00	cancelled	2026-08-31 08:01:48.675828	pending	\N	2026-08-31 08:01:49.584052+00	delivery	\N	{"city": "Nairobi", "line1": "123 Test St", "phone": "0712345678"}	0.00	\N	cod	\N	289.00	FREESHIP	0	0.00	t	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 289.00, "promoType": "storewide", "freeDelivery": false}, {"id": "9411038b-a789-48a2-acaa-5f57bac1b33c", "code": "FREESHIP", "name": "Free delivery", "discount": 0.00, "promoType": "coupon", "freeDelivery": true}]	\N
9089649b-aa41-4a73-8d49-1dc2c7b7962a	a2a071d2-da64-4571-9f17-288c5abd72dc	2601.00	cancelled	2026-08-31 08:01:51.191813	pending	\N	2026-08-31 08:01:51.743373+00	pickup	acc6941a-7f05-49e6-8293-7607e35d14dc	\N	0.00	\N	cod	\N	289.00	\N	0	0.00	f	[{"id": "69f53b0c-3dcd-413c-a52b-7e78642b6d2d", "code": "STORE10", "name": "Storewide 10% off", "discount": 289.00, "promoType": "storewide", "freeDelivery": false}]	\N
\.


--
-- Data for Name: payment_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payment_events (id, payment_id, event_type, payload, created_at) FROM stdin;
36819963-b9fe-42e0-aa2a-4ee4bb0d2a65	f263608a-3b96-4567-92e6-b7caed70e008	payment_created	{"amount": 3062.00, "method": "mpesa", "provider": "mock_mpesa"}	2026-08-13 13:04:30.120761+00
b536765a-cec5-4139-aa75-a1b34b3573be	f263608a-3b96-4567-92e6-b7caed70e008	stk_initiated	{"checkout_request_id": "ws_chk_1786626270423_ygwzpulh", "merchant_request_id": "ws_mer_1786626270423_zfnbmx0u"}	2026-08-13 13:04:30.395349+00
6b954464-2a7e-4f84-a606-4da2f68aec27	f263608a-3b96-4567-92e6-b7caed70e008	payment_paid	{"mock": true, "ResultCode": 0, "ResultDesc": "The service request is processed successfully.", "CheckoutRequestID": "ws_chk_1786626270423_ygwzpulh"}	2026-08-13 13:04:33.598963+00
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payments (id, order_id, user_id, provider, method, status, amount, currency, phone_number, transaction_reference, checkout_request_id, merchant_request_id, receipt_number, failure_reason, raw_request, raw_response, raw_callback, expires_at, paid_at, created_at, updated_at) FROM stdin;
f263608a-3b96-4567-92e6-b7caed70e008	21ce8844-157e-4cd8-9e93-2c4d20256a76	eebd94c0-8179-4619-a527-218ac9f7d5c4	mock_mpesa	mpesa	paid	3062.00	KES	254740845440	ws_chk_1786626270423_ygwzpulh	ws_chk_1786626270423_ygwzpulh	ws_mer_1786626270423_zfnbmx0u	MOCK26273387	\N	{}	{"mock": true, "ResponseCode": "0", "CustomerMessage": "Success. Request accepted for processing", "CheckoutRequestID": "ws_chk_1786626270423_ygwzpulh", "MerchantRequestID": "ws_mer_1786626270423_zfnbmx0u", "ResponseDescription": "Success. Request accepted for processing"}	{"mock": true, "ResultCode": 0, "ResultDesc": "The service request is processed successfully.", "CheckoutRequestID": "ws_chk_1786626270423_ygwzpulh"}	2026-08-13 13:09:30.120761+00	2026-08-13 13:04:33.598963+00	2026-08-13 13:04:30.120761+00	2026-08-13 13:04:33.598963+00
\.


--
-- Data for Name: pickup_locations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.pickup_locations (id, name, building, description, operating_hours, is_active, created_at, updated_at) FROM stdin;
acc6941a-7f05-49e6-8293-7607e35d14dc	Babees Place Main	Primary Boutique	Default pickup hub	{"weekdays": {"open": "08:00", "close": "18:00"}, "weekends": {"open": "09:00", "close": "15:00"}}	t	2026-07-12 18:45:13.777223+00	2026-07-12 18:45:13.777223+00
a3000000-0000-4000-8000-000000000001	Babees Place — Westlands Hub	Sarit Centre, Ground Floor Collection Point	Weekday pickup 10:00–19:00. Bring your order SMS.	{"sat": "10:00-17:00", "sun": "closed", "mon_fri": "10:00-19:00"}	t	2026-08-03 08:52:50.449531+00	2026-08-03 08:52:50.449531+00
a3000000-0000-4000-8000-000000000002	Babees Place — CBD Counter	Kencom House, Mezzanine	Central Nairobi pickup desk near Kencom bus stage.	{"sat": "09:00-14:00", "sun": "closed", "mon_fri": "09:00-18:00"}	t	2026-08-03 08:52:50.449531+00	2026-08-03 08:52:50.449531+00
a3000000-0000-4000-8000-000000000003	Babees Place — Rongai Lockers	Galleria Mall service corridor	Self-serve lockers. Code sent when order is ready.	{"mon_sun": "08:00-20:00"}	t	2026-08-03 08:52:50.449531+00	2026-08-03 08:52:50.449531+00
\.


--
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.products (id, name, slug, price, category, category_id, featured, created_at, description, stock, discount_price, image_url, images, is_active, updated_at) FROM stdin;
a2000000-0000-4000-8000-000000000003	Fleece Hoodie — Charcoal	bp-fsh-003	2890	Fashion	a1000000-0000-4000-8000-000000000001	t	2026-06-29 09:06:33.665	Mid-weight fleece hoodie with kangaroo pocket and drawstring hood.	38	\N	https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1200&q=80	[{"alt": "Fleece Hoodie — Charcoal — primary product photo", "url": "https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-003/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Fleece Hoodie — Charcoal — gallery view 2", "url": "https://images.unsplash.com/photo-1578768079052-aa76e52ff62e?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-003/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Fleece Hoodie — Charcoal — gallery view 3", "url": "https://images.unsplash.com/photo-1620799140408-edc6dcb6d633?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-003/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Fleece Hoodie — Charcoal — thumbnail", "url": "https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-003/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-31 08:06:16.552568+00
a2000000-0000-4000-8000-000000000006	Denim Jacket — Classic Blue	bp-fsh-006	3990	Fashion	a1000000-0000-4000-8000-000000000001	f	2026-06-29 09:06:33.665	Stone-washed denim jacket with metal buttons and chest pockets.	22	\N	https://images.unsplash.com/photo-1576995853123-5a10305d93c0?auto=format&fit=crop&w=1200&q=80	[{"alt": "Denim Jacket — Classic Blue — primary product photo", "url": "https://images.unsplash.com/photo-1576995853123-5a10305d93c0?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-006/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Denim Jacket — Classic Blue — gallery view 2", "url": "https://images.unsplash.com/photo-1551028719-00167b16eac5?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-006/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Denim Jacket — Classic Blue — gallery view 3", "url": "https://images.unsplash.com/photo-1601333144130-8cbb312386b6?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-006/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Denim Jacket — Classic Blue — thumbnail", "url": "https://images.unsplash.com/photo-1576995853123-5a10305d93c0?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-006/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:37.13204+00
a2000000-0000-4000-8000-000000000002	Graphic Tee — City Lines	bp-fsh-002	1490	Fashion	a1000000-0000-4000-8000-000000000001	f	2026-06-29 09:06:33.665	Relaxed-fit tee with a subtle city print. Pre-shrunk cotton blend.	44	1200.00	https://images.unsplash.com/photo-1576566588028-4147f3842f27?auto=format&fit=crop&w=1200&q=80	[{"alt": "Graphic Tee — City Lines — primary product photo", "url": "https://images.unsplash.com/photo-1576566588028-4147f3842f27?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-002/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Graphic Tee — City Lines — gallery view 2", "url": "https://images.unsplash.com/photo-1503342217505-b0a15ec3261c?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-002/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Graphic Tee — City Lines — gallery view 3", "url": "https://images.unsplash.com/photo-1529374255404-311a2a4f1fd9?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-002/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Graphic Tee — City Lines — thumbnail", "url": "https://images.unsplash.com/photo-1576566588028-4147f3842f27?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-002/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 06:25:14.343959+00
a2000000-0000-4000-8000-000000000048	Gentle Care Shampoo 350ml	bp-bty-048	750	Beauty & Accessories	a1000000-0000-4000-8000-000000000005	f	2026-07-04 09:06:34.074	Sulphate-free shampoo for everyday cleansing and softness.	68	\N	https://images.unsplash.com/photo-1535585209827-a15fcdbc4c2d?auto=format&fit=crop&w=1200&q=80	[{"alt": "Gentle Care Shampoo 350ml — primary product photo", "url": "https://images.unsplash.com/photo-1535585209827-a15fcdbc4c2d?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-bty-048/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Gentle Care Shampoo 350ml — gallery view 2", "url": "https://images.unsplash.com/photo-1522338242992-e1a54906a8da?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-048/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Gentle Care Shampoo 350ml — gallery view 3", "url": "https://images.unsplash.com/photo-1571875257727-256c39da42af?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-048/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Gentle Care Shampoo 350ml — thumbnail", "url": "https://images.unsplash.com/photo-1535585209827-a15fcdbc4c2d?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-bty-048/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:32.731726+00
a2000000-0000-4000-8000-000000000049	Foaming Face Cleanser 150ml	bp-bty-049	980	Beauty & Accessories	a1000000-0000-4000-8000-000000000005	f	2026-07-04 09:06:34.074	Mild foaming cleanser that removes oil without stripping skin.	52	\N	https://images.unsplash.com/photo-1556228720-195a672e8a03?auto=format&fit=crop&w=1200&q=80	[{"alt": "Foaming Face Cleanser 150ml — primary product photo", "url": "https://images.unsplash.com/photo-1556228720-195a672e8a03?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-bty-049/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Foaming Face Cleanser 150ml — gallery view 2", "url": "https://images.unsplash.com/photo-1570194065650-d99fb4b38b17?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-049/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Foaming Face Cleanser 150ml — gallery view 3", "url": "https://images.unsplash.com/photo-1598440947619-2c35fc9aa908?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-049/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Foaming Face Cleanser 150ml — thumbnail", "url": "https://images.unsplash.com/photo-1556228720-195a672e8a03?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-bty-049/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:33.009026+00
a2000000-0000-4000-8000-000000000050	Weekend Travel Bag — Navy	bp-bty-050	4290	Beauty & Accessories	a1000000-0000-4000-8000-000000000005	f	2026-07-04 09:06:34.074	Duffel-style travel bag with shoe compartment and shoulder strap.	13	\N	https://images.unsplash.com/photo-1548036328-c9fa89d128fa?auto=format&fit=crop&w=1200&q=80	[{"alt": "Weekend Travel Bag — Navy — primary product photo", "url": "https://images.unsplash.com/photo-1548036328-c9fa89d128fa?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-bty-050/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Weekend Travel Bag — Navy — gallery view 2", "url": "https://images.unsplash.com/photo-1553062407-98eeb64c6a62?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-050/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Weekend Travel Bag — Navy — gallery view 3", "url": "https://images.unsplash.com/photo-1581605405669-fbf945cd739e?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-050/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Weekend Travel Bag — Navy — thumbnail", "url": "https://images.unsplash.com/photo-1548036328-c9fa89d128fa?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-bty-050/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:33.311561+00
a2000000-0000-4000-8000-000000000018	Power Bank 20,000 mAh	bp-elc-018	3200	Electronics	a1000000-0000-4000-8000-000000000002	f	2026-06-29 09:06:33.665	Dual-output power bank with fast charge support for phones and tablets.	55	\N	https://images.unsplash.com/photo-1609091839311-b9b6d73f2f4d?auto=format&fit=crop&w=1200&q=80	[{"alt": "Power Bank 20,000 mAh — primary product photo", "url": "https://images.unsplash.com/photo-1609091839311-b9b6d73f2f4d?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-elc-018/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Power Bank 20,000 mAh — gallery view 2", "url": "https://images.unsplash.com/photo-1625794084867-8ddd23996b58?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-018/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Power Bank 20,000 mAh — gallery view 3", "url": "https://images.unsplash.com/photo-1583863788434-e58a36330cf0?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-018/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Power Bank 20,000 mAh — thumbnail", "url": "https://images.unsplash.com/photo-1609091839311-b9b6d73f2f4d?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-elc-018/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:34.023175+00
a2000000-0000-4000-8000-000000000019	USB-C Fast Phone Charger 30W	bp-elc-019	1490	Electronics	a1000000-0000-4000-8000-000000000002	f	2026-06-29 09:06:33.665	Compact wall charger with USB-C PD for modern smartphones.	80	\N	https://images.unsplash.com/photo-1583863788434-e58a36330cf0?auto=format&fit=crop&w=1200&q=80	[{"alt": "USB-C Fast Phone Charger 30W — primary product photo", "url": "https://images.unsplash.com/photo-1583863788434-e58a36330cf0?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-elc-019/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "USB-C Fast Phone Charger 30W — gallery view 2", "url": "https://images.unsplash.com/photo-1625948515291-69613efd103f?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-019/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "USB-C Fast Phone Charger 30W — gallery view 3", "url": "https://images.unsplash.com/photo-1609091839311-b9b6d73f2f4d?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-019/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "USB-C Fast Phone Charger 30W — thumbnail", "url": "https://images.unsplash.com/photo-1583863788434-e58a36330cf0?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-elc-019/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:34.223752+00
a2000000-0000-4000-8000-000000000021	Wireless Mouse — Graphite	bp-elc-021	1290	Electronics	a1000000-0000-4000-8000-000000000002	f	2026-06-29 09:06:33.665	Quiet-click wireless mouse with USB receiver and long battery life.	62	\N	https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?auto=format&fit=crop&w=1200&q=80	[{"alt": "Wireless Mouse — Graphite — primary product photo", "url": "https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-elc-021/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Wireless Mouse — Graphite — gallery view 2", "url": "https://images.unsplash.com/photo-1615663245857-ac93bb7c39e7?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-021/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Wireless Mouse — Graphite — gallery view 3", "url": "https://images.unsplash.com/photo-1563297007-0686b7003af7?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-021/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Wireless Mouse — Graphite — thumbnail", "url": "https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-elc-021/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:34.630578+00
a2000000-0000-4000-8000-000000000022	USB-C Hub 7-in-1	bp-elc-022	3890	Electronics	a1000000-0000-4000-8000-000000000002	f	2026-06-29 09:06:33.665	HDMI, USB-A, SD, and charging passthrough for laptops on the go.	19	\N	https://images.unsplash.com/photo-1625948515291-69613efd103f?auto=format&fit=crop&w=1200&q=80	[{"alt": "USB-C Hub 7-in-1 — primary product photo", "url": "https://images.unsplash.com/photo-1625948515291-69613efd103f?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-elc-022/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "USB-C Hub 7-in-1 — gallery view 2", "url": "https://images.unsplash.com/photo-1593640408182-31c70c8268f1?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-022/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "USB-C Hub 7-in-1 — gallery view 3", "url": "https://images.unsplash.com/photo-1587825140708-dfaf72ae4b04?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-022/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "USB-C Hub 7-in-1 — thumbnail", "url": "https://images.unsplash.com/photo-1625948515291-69613efd103f?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-elc-022/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:34.816743+00
a2000000-0000-4000-8000-000000000023	Aluminium Laptop Stand	bp-elc-023	2490	Electronics	a1000000-0000-4000-8000-000000000002	f	2026-06-29 09:06:33.665	Adjustable laptop stand that improves posture and cooling.	34	\N	https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?auto=format&fit=crop&w=1200&q=80	[{"alt": "Aluminium Laptop Stand — primary product photo", "url": "https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-elc-023/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Aluminium Laptop Stand — gallery view 2", "url": "https://images.unsplash.com/photo-1496181133206-80ce9b88a853?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-023/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Aluminium Laptop Stand — gallery view 3", "url": "https://images.unsplash.com/photo-1587825140708-dfaf72ae4b04?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-023/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Aluminium Laptop Stand — thumbnail", "url": "https://images.unsplash.com/photo-1527864550417-7fd91fc51a46?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-elc-023/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:35.153474+00
a2000000-0000-4000-8000-000000000025	LED Desk Lamp — Warm White	bp-elc-025	2190	Electronics	a1000000-0000-4000-8000-000000000002	f	2026-06-29 09:06:33.665	Touch-dimmable LED desk lamp with flexible arm and USB power.	30	\N	https://images.unsplash.com/photo-1507473885765-e6ed057f782c?auto=format&fit=crop&w=1200&q=80	[{"alt": "LED Desk Lamp — Warm White — primary product photo", "url": "https://images.unsplash.com/photo-1507473885765-e6ed057f782c?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-elc-025/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "LED Desk Lamp — Warm White — gallery view 2", "url": "https://images.unsplash.com/photo-1513506003901-1e6a229e2d15?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-025/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "LED Desk Lamp — Warm White — gallery view 3", "url": "https://images.unsplash.com/photo-1534073828943-f801091bb18c?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-025/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "LED Desk Lamp — Warm White — thumbnail", "url": "https://images.unsplash.com/photo-1507473885765-e6ed057f782c?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-elc-025/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:35.768822+00
a2000000-0000-4000-8000-000000000004	Zip Hoodie — Olive	bp-fsh-004	3200	Fashion	a1000000-0000-4000-8000-000000000001	f	2026-06-29 09:06:33.665	Full-zip hoodie with ribbed cuffs. Ideal for cool evenings.	28	\N	https://images.unsplash.com/photo-1620799140188-3b2a02fd9a77?auto=format&fit=crop&w=1200&q=80	[{"alt": "Zip Hoodie — Olive — primary product photo", "url": "https://images.unsplash.com/photo-1620799140188-3b2a02fd9a77?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-004/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Zip Hoodie — Olive — gallery view 2", "url": "https://images.unsplash.com/photo-1556821840-3a63f95609a7?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-004/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Zip Hoodie — Olive — gallery view 3", "url": "https://images.unsplash.com/photo-1618354691373-d851c5c3a990?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-004/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Zip Hoodie — Olive — thumbnail", "url": "https://images.unsplash.com/photo-1620799140188-3b2a02fd9a77?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-004/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:36.689289+00
a2000000-0000-4000-8000-000000000010	Shirt Dress — Navy Stripe	bp-fsh-010	3290	Fashion	a1000000-0000-4000-8000-000000000001	f	2026-06-29 09:06:33.665	Button-front shirt dress with side pockets and a removable belt.	14	\N	https://images.unsplash.com/photo-1572804013309-59a88b7e92f1?auto=format&fit=crop&w=1200&q=80	[{"alt": "Shirt Dress — Navy Stripe — primary product photo", "url": "https://images.unsplash.com/photo-1572804013309-59a88b7e92f1?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-010/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Shirt Dress — Navy Stripe — gallery view 2", "url": "https://images.unsplash.com/photo-1585487000160-6ebcfceb0d03?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-010/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Shirt Dress — Navy Stripe — gallery view 3", "url": "https://images.unsplash.com/photo-1594633312681-425c7b97ccd1?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-010/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Shirt Dress — Navy Stripe — thumbnail", "url": "https://images.unsplash.com/photo-1572804013309-59a88b7e92f1?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-010/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:37.997564+00
a2000000-0000-4000-8000-000000000001	Essential Cotton Tee — White	bp-fsh-001	890	Fashion	a1000000-0000-4000-8000-000000000001	t	2026-06-29 09:06:33.665	Soft crew-neck t-shirt in breathable cotton. Everyday fit for Nairobi weather.	67	\N	https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=1200&q=80	[{"alt": "Essential Cotton Tee — White — primary product photo", "url": "https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-001/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Essential Cotton Tee — White — gallery view 2", "url": "https://images.unsplash.com/photo-1583743814966-8936f5b7be1a?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-001/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Essential Cotton Tee — White — gallery view 3", "url": "https://images.unsplash.com/photo-1562157873-818bc0726f68?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-001/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Essential Cotton Tee — White — thumbnail", "url": "https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-001/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 06:25:14.343959+00
a2000000-0000-4000-8000-000000000005	Light Bomber Jacket — Black	bp-fsh-005	5200	Fashion	a1000000-0000-4000-8000-000000000001	t	2026-06-29 09:06:33.665	Water-resistant bomber with a clean silhouette and inner pocket.	18	4500.00	https://images.unsplash.com/photo-1591047139829-d91aecb6caea?auto=format&fit=crop&w=1200&q=80	[{"alt": "Light Bomber Jacket — Black — primary product photo", "url": "https://images.unsplash.com/photo-1591047139829-d91aecb6caea?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-005/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Light Bomber Jacket — Black — gallery view 2", "url": "https://images.unsplash.com/photo-1548126032-079a0fb0099d?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-005/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Light Bomber Jacket — Black — gallery view 3", "url": "https://images.unsplash.com/photo-1495105787522-5334e3ffa0ef?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-005/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Light Bomber Jacket — Black — thumbnail", "url": "https://images.unsplash.com/photo-1591047139829-d91aecb6caea?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-005/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:36.89456+00
a2000000-0000-4000-8000-000000000007	Slim Fit Jeans — Indigo	bp-fsh-007	2790	Fashion	a1000000-0000-4000-8000-000000000001	f	2026-06-29 09:06:33.665	Stretch denim slim jeans with a mid rise and clean finish.	54	\N	https://images.unsplash.com/photo-1542272604-787c3835535d?auto=format&fit=crop&w=1200&q=80	[{"alt": "Slim Fit Jeans — Indigo — primary product photo", "url": "https://images.unsplash.com/photo-1542272604-787c3835535d?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-007/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Slim Fit Jeans — Indigo — gallery view 2", "url": "https://images.unsplash.com/photo-1604176354204-9268737828e4?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-007/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Slim Fit Jeans — Indigo — gallery view 3", "url": "https://images.unsplash.com/photo-1582418702059-97ebafb35d09?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-007/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Slim Fit Jeans — Indigo — thumbnail", "url": "https://images.unsplash.com/photo-1542272604-787c3835535d?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-007/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:37.40765+00
a2000000-0000-4000-8000-000000000008	Straight Jeans — Washed Grey	bp-fsh-008	2590	Fashion	a1000000-0000-4000-8000-000000000001	f	2026-06-29 09:06:33.665	Straight-leg jeans in a soft washed grey. Comfortable all-day wear.	41	\N	https://images.unsplash.com/photo-1475178626620-a4d074967337?auto=format&fit=crop&w=1200&q=80	[{"alt": "Straight Jeans — Washed Grey — primary product photo", "url": "https://images.unsplash.com/photo-1475178626620-a4d074967337?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-008/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Straight Jeans — Washed Grey — gallery view 2", "url": "https://images.unsplash.com/photo-1541099649105-f69ad21f3246?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-008/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Straight Jeans — Washed Grey — gallery view 3", "url": "https://images.unsplash.com/photo-1542272604-787c3835535d?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-008/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Straight Jeans — Washed Grey — thumbnail", "url": "https://images.unsplash.com/photo-1475178626620-a4d074967337?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-008/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:37.602635+00
a2000000-0000-4000-8000-000000000037	Stuffed Bear — Honey	bp-toy-037	1290	Toys & Kids	a1000000-0000-4000-8000-000000000004	f	2026-07-04 09:06:34.074	Soft plush bear with embroidered eyes. Suitable for ages 3+.	47	\N	https://images.unsplash.com/photo-1559454403-b1fb1002ea1e?auto=format&fit=crop&w=1200&q=80	[{"alt": "Stuffed Bear — Honey — primary product photo", "url": "https://images.unsplash.com/photo-1559454403-b1fb1002ea1e?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-toy-037/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Stuffed Bear — Honey — gallery view 2", "url": "https://images.unsplash.com/photo-1530325553241-4f6e9f7a0f1c?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-037/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Stuffed Bear — Honey — gallery view 3", "url": "https://images.unsplash.com/photo-1566576912321-d58ddd7a6088?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-037/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Stuffed Bear — Honey — thumbnail", "url": "https://images.unsplash.com/photo-1559454403-b1fb1002ea1e?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-toy-037/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:41.396147+00
a2000000-0000-4000-8000-000000000040	Educational Flash Cards	bp-toy-040	650	Toys & Kids	a1000000-0000-4000-8000-000000000004	f	2026-07-04 09:06:34.074	Alphabet and number cards for early learning at home.	70	\N	https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4?auto=format&fit=crop&w=1200&q=80	[{"alt": "Educational Flash Cards — primary product photo", "url": "https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-toy-040/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Educational Flash Cards — gallery view 2", "url": "https://images.unsplash.com/photo-1503454537195-1dcabb73ffb9?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-040/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Educational Flash Cards — gallery view 3", "url": "https://images.unsplash.com/photo-1587654780291-39c9404d746b?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-040/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Educational Flash Cards — thumbnail", "url": "https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-toy-040/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:42.121049+00
a2000000-0000-4000-8000-000000000016	Wireless Earbuds — Pearl White	bp-elc-016	3499	Electronics	a1000000-0000-4000-8000-000000000002	t	2026-06-29 09:06:33.665	True wireless earbuds with charging case and clear call mic.	48	2999.00	https://images.unsplash.com/photo-1590658268037-6bf12165a8df?auto=format&fit=crop&w=1200&q=80	[{"alt": "Wireless Earbuds — Pearl White — primary product photo", "url": "https://images.unsplash.com/photo-1590658268037-6bf12165a8df?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-elc-016/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Wireless Earbuds — Pearl White — gallery view 2", "url": "https://images.unsplash.com/photo-1606220945770-b5b6c2c55bf1?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-016/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Wireless Earbuds — Pearl White — gallery view 3", "url": "https://images.unsplash.com/photo-1618366712010-f4ae9c647dcb?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-016/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Wireless Earbuds — Pearl White — thumbnail", "url": "https://images.unsplash.com/photo-1590658268037-6bf12165a8df?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-elc-016/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:33.519763+00
a2000000-0000-4000-8000-000000000017	Bluetooth Speaker — Midnight	bp-elc-017	4500	Electronics	a1000000-0000-4000-8000-000000000002	t	2026-06-29 09:06:33.665	Portable speaker with rich bass and 10-hour battery life.	26	\N	https://images.unsplash.com/photo-1608043152269-423dbba4e7e1?auto=format&fit=crop&w=1200&q=80	[{"alt": "Bluetooth Speaker — Midnight — primary product photo", "url": "https://images.unsplash.com/photo-1608043152269-423dbba4e7e1?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-elc-017/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Bluetooth Speaker — Midnight — gallery view 2", "url": "https://images.unsplash.com/photo-1545454675-3531b543be5d?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-017/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Bluetooth Speaker — Midnight — gallery view 3", "url": "https://images.unsplash.com/photo-1589003077984-894e133dabab?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-017/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Bluetooth Speaker — Midnight — thumbnail", "url": "https://images.unsplash.com/photo-1608043152269-423dbba4e7e1?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-elc-017/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:33.818946+00
a2000000-0000-4000-8000-000000000020	Smart Watch — Active Fit	bp-elc-020	6500	Electronics	a1000000-0000-4000-8000-000000000002	t	2026-06-29 09:06:33.665	Fitness smart watch with heart-rate tracking and message alerts.	21	\N	https://images.unsplash.com/photo-1579586337278-3befd40fd17a?auto=format&fit=crop&w=1200&q=80	[{"alt": "Smart Watch — Active Fit — primary product photo", "url": "https://images.unsplash.com/photo-1579586337278-3befd40fd17a?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-elc-020/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Smart Watch — Active Fit — gallery view 2", "url": "https://images.unsplash.com/photo-1434494878577-86c23bcb06b9?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-020/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Smart Watch — Active Fit — gallery view 3", "url": "https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-020/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Smart Watch — Active Fit — thumbnail", "url": "https://images.unsplash.com/photo-1579586337278-3befd40fd17a?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-elc-020/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:34.433648+00
a2000000-0000-4000-8000-000000000024	Portable Desk Fan — Mini	bp-elc-024	990	Electronics	a1000000-0000-4000-8000-000000000002	f	2026-06-29 09:06:33.665	USB-powered portable fan with three speeds for desk or travel.	6	\N	https://images.unsplash.com/photo-1558618666-fcd25c85cd64?auto=format&fit=crop&w=1200&q=80	[{"alt": "Portable Desk Fan — Mini — primary product photo", "url": "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-elc-024/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Portable Desk Fan — Mini — gallery view 2", "url": "https://images.unsplash.com/photo-1505740420928-5e560c06d30e?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-024/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Portable Desk Fan — Mini — gallery view 3", "url": "https://images.unsplash.com/photo-1513506003901-1e6a229e2d15?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-elc-024/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Portable Desk Fan — Mini — thumbnail", "url": "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-elc-024/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:35.326209+00
a2000000-0000-4000-8000-000000000028	Silent Wall Clock — Oak Frame	bp-hom-028	1590	Home & Living	a1000000-0000-4000-8000-000000000003	f	2026-07-04 09:06:34.074	Quiet quartz wall clock with a warm oak-look frame.	22	\N	https://images.unsplash.com/photo-1563861826100-9cb668332e1b?auto=format&fit=crop&w=1200&q=80	[{"alt": "Silent Wall Clock — Oak Frame — primary product photo", "url": "https://images.unsplash.com/photo-1563861826100-9cb668332e1b?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-hom-028/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Silent Wall Clock — Oak Frame — gallery view 2", "url": "https://images.unsplash.com/photo-1509042239860-f550ce710b93?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-028/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Silent Wall Clock — Oak Frame — gallery view 3", "url": "https://images.unsplash.com/photo-1493663284031-b7e3aefcae8e?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-028/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Silent Wall Clock — Oak Frame — thumbnail", "url": "https://images.unsplash.com/photo-1563861826100-9cb668332e1b?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-hom-028/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:43:34.581033+00
a2000000-0000-4000-8000-000000000044	Everyday Backpack — Slate	bp-bty-044	3490	Beauty & Accessories	a1000000-0000-4000-8000-000000000005	f	2026-07-04 09:06:34.074	Padded laptop sleeve backpack with water-resistant exterior.	32	\N	https://images.unsplash.com/photo-1553062407-98eeb64c6a62?auto=format&fit=crop&w=1200&q=80	[{"alt": "Everyday Backpack — Slate — primary product photo", "url": "https://images.unsplash.com/photo-1553062407-98eeb64c6a62?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-bty-044/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Everyday Backpack — Slate — gallery view 2", "url": "https://images.unsplash.com/photo-1622560480605-d83c8532435e?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-044/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Everyday Backpack — Slate — gallery view 3", "url": "https://images.unsplash.com/photo-1590874103328-eac38a683ce0?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-044/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Everyday Backpack — Slate — thumbnail", "url": "https://images.unsplash.com/photo-1553062407-98eeb64c6a62?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-bty-044/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:31.248079+00
a2000000-0000-4000-8000-000000000046	Polarized Sunglasses — Tortoise	bp-bty-046	2490	Beauty & Accessories	a1000000-0000-4000-8000-000000000005	f	2026-07-04 09:06:34.074	UV400 polarized lenses in a lightweight tortoise frame.	19	1990.00	https://images.unsplash.com/photo-1511499767150-a48a237f0083?auto=format&fit=crop&w=1200&q=80	[{"alt": "Polarized Sunglasses — Tortoise — primary product photo", "url": "https://images.unsplash.com/photo-1511499767150-a48a237f0083?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-bty-046/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Polarized Sunglasses — Tortoise — gallery view 2", "url": "https://images.unsplash.com/photo-1572635196237-14b3f281503f?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-046/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Polarized Sunglasses — Tortoise — gallery view 3", "url": "https://images.unsplash.com/photo-1473496169904-658ba7c44d8a?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-046/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Polarized Sunglasses — Tortoise — thumbnail", "url": "https://images.unsplash.com/photo-1511499767150-a48a237f0083?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-bty-046/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-13 15:11:45.293916+00
a2000000-0000-4000-8000-000000000009	Linen Midi Dress — Sand	bp-fsh-009	3490	Fashion	a1000000-0000-4000-8000-000000000001	t	2026-06-29 09:06:33.665	Breathable linen-blend midi dress with a soft A-line cut.	16	\N	https://images.unsplash.com/photo-1595777457583-95e059d581b8?auto=format&fit=crop&w=1200&q=80	[{"alt": "Linen Midi Dress — Sand — primary product photo", "url": "https://images.unsplash.com/photo-1595777457583-95e059d581b8?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-009/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Linen Midi Dress — Sand — gallery view 2", "url": "https://images.unsplash.com/photo-1515372039744-b8f02a3ae446?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-009/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Linen Midi Dress — Sand — gallery view 3", "url": "https://images.unsplash.com/photo-1496747611176-843222e1e57c?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-009/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Linen Midi Dress — Sand — thumbnail", "url": "https://images.unsplash.com/photo-1595777457583-95e059d581b8?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-009/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:37.815934+00
a2000000-0000-4000-8000-000000000045	Leather Wallet — Cognac	bp-bty-045	2290	Beauty & Accessories	a1000000-0000-4000-8000-000000000005	f	2026-07-04 09:06:34.074	Slim bifold wallet in genuine leather with RFID card slots.	23	\N	https://images.unsplash.com/photo-1627123424574-724758594e93?auto=format&fit=crop&w=1200&q=80	[{"alt": "Leather Wallet — Cognac — primary product photo", "url": "https://images.unsplash.com/photo-1627123424574-724758594e93?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-bty-045/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Leather Wallet — Cognac — gallery view 2", "url": "https://images.unsplash.com/photo-1553062407-98eeb64c6a62?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-045/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Leather Wallet — Cognac — gallery view 3", "url": "https://images.unsplash.com/photo-1601924994987-69e26d50dc26?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-045/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Leather Wallet — Cognac — thumbnail", "url": "https://images.unsplash.com/photo-1627123424574-724758594e93?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-bty-045/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-13 13:10:15.315081+00
a2000000-0000-4000-8000-000000000012	Court Sneakers — Black/Gum	bp-fsh-012	4590	Fashion	a1000000-0000-4000-8000-000000000001	f	2026-06-29 09:06:33.665	Low-top court sneakers with gum sole and padded collar.	7	3990.00	https://images.unsplash.com/photo-1600185365483-26d7a4cc7519?auto=format&fit=crop&w=1200&q=80	[{"alt": "Court Sneakers — Black/Gum — primary product photo", "url": "https://images.unsplash.com/photo-1600185365483-26d7a4cc7519?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-012/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Court Sneakers — Black/Gum — gallery view 2", "url": "https://images.unsplash.com/photo-1595950653106-6c9ebd614d3a?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-012/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Court Sneakers — Black/Gum — gallery view 3", "url": "https://images.unsplash.com/photo-1549298916-b41d501d3772?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-012/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Court Sneakers — Black/Gum — thumbnail", "url": "https://images.unsplash.com/photo-1600185365483-26d7a4cc7519?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-012/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:38.448695+00
a2000000-0000-4000-8000-000000000013	Leather Slide Sandals — Tan	bp-fsh-013	1890	Fashion	a1000000-0000-4000-8000-000000000001	f	2026-06-29 09:06:33.665	Open-toe leather slides with a contoured footbed.	40	\N	https://images.unsplash.com/photo-1603487742131-4160ec999306?auto=format&fit=crop&w=1200&q=80	[{"alt": "Leather Slide Sandals — Tan — primary product photo", "url": "https://images.unsplash.com/photo-1603487742131-4160ec999306?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-013/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Leather Slide Sandals — Tan — gallery view 2", "url": "https://images.unsplash.com/photo-1562273138-f46be4ebdf33?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-013/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Leather Slide Sandals — Tan — gallery view 3", "url": "https://images.unsplash.com/photo-1603808033192-082d59554583?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-013/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Leather Slide Sandals — Tan — thumbnail", "url": "https://images.unsplash.com/photo-1603487742131-4160ec999306?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-013/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:38.68102+00
a2000000-0000-4000-8000-000000000014	Canvas Crossbody Bag — Khaki	bp-fsh-014	1650	Fashion	a1000000-0000-4000-8000-000000000001	f	2026-06-29 09:06:33.665	Compact crossbody with adjustable strap and zippered main pocket.	29	\N	https://images.unsplash.com/photo-1548036328-c9fa89d128fa?auto=format&fit=crop&w=1200&q=80	[{"alt": "Canvas Crossbody Bag — Khaki — primary product photo", "url": "https://images.unsplash.com/photo-1548036328-c9fa89d128fa?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-014/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Canvas Crossbody Bag — Khaki — gallery view 2", "url": "https://images.unsplash.com/photo-1590874103328-eac38a683ce0?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-014/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Canvas Crossbody Bag — Khaki — gallery view 3", "url": "https://images.unsplash.com/photo-1553062407-98eeb64c6a62?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-014/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Canvas Crossbody Bag — Khaki — thumbnail", "url": "https://images.unsplash.com/photo-1548036328-c9fa89d128fa?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-014/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:38.866293+00
a2000000-0000-4000-8000-000000000015	Structured Cap — Black	bp-fsh-015	990	Fashion	a1000000-0000-4000-8000-000000000001	f	2026-06-29 09:06:33.665	Six-panel cotton cap with embroidered Babees mark.	65	\N	https://images.unsplash.com/photo-1588850561407-ed78c282e89b?auto=format&fit=crop&w=1200&q=80	[{"alt": "Structured Cap — Black — primary product photo", "url": "https://images.unsplash.com/photo-1588850561407-ed78c282e89b?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-015/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Structured Cap — Black — gallery view 2", "url": "https://images.unsplash.com/photo-1521369909029-2afed882baee?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-015/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Structured Cap — Black — gallery view 3", "url": "https://images.unsplash.com/photo-1575428652377-a2d80e2277b0?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-015/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Structured Cap — Black — thumbnail", "url": "https://images.unsplash.com/photo-1588850561407-ed78c282e89b?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-015/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:39.043919+00
a2000000-0000-4000-8000-000000000026	Woven Storage Basket — Large	bp-hom-026	1890	Home & Living	a1000000-0000-4000-8000-000000000003	f	2026-07-04 09:06:34.073	Sturdy woven basket for blankets, toys, or laundry overflow.	27	\N	https://images.unsplash.com/photo-1616046220798-a697b87c2b0c?auto=format&fit=crop&w=1200&q=80	[{"alt": "Woven Storage Basket — Large — primary product photo", "url": "https://images.unsplash.com/photo-1616046220798-a697b87c2b0c?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-hom-026/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Woven Storage Basket — Large — gallery view 2", "url": "https://images.unsplash.com/photo-1586023492125-27b2c045efd7?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-026/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Woven Storage Basket — Large — gallery view 3", "url": "https://images.unsplash.com/photo-1555041469-a586c61ea9bc?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-026/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Woven Storage Basket — Large — thumbnail", "url": "https://images.unsplash.com/photo-1616046220798-a697b87c2b0c?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-hom-026/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:39.253592+00
a2000000-0000-4000-8000-000000000030	Ceramic Coffee Mug Set (4)	bp-hom-030	1790	Home & Living	a1000000-0000-4000-8000-000000000003	f	2026-07-04 09:06:34.074	Four stackable stoneware mugs in mixed earth tones.	42	\N	https://images.unsplash.com/photo-1514228742587-6b1558fcc36f?auto=format&fit=crop&w=1200&q=80	[{"alt": "Ceramic Coffee Mug Set (4) — primary product photo", "url": "https://images.unsplash.com/photo-1514228742587-6b1558fcc36f?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-hom-030/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Ceramic Coffee Mug Set (4) — gallery view 2", "url": "https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-030/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Ceramic Coffee Mug Set (4) — gallery view 3", "url": "https://images.unsplash.com/photo-1577937928226-c0c6a1c6b4e1?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-030/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Ceramic Coffee Mug Set (4) — thumbnail", "url": "https://images.unsplash.com/photo-1514228742587-6b1558fcc36f?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-hom-030/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:39.985496+00
a2000000-0000-4000-8000-000000000031	Kitchen Drawer Organizer	bp-hom-031	1450	Home & Living	a1000000-0000-4000-8000-000000000003	f	2026-07-04 09:06:34.074	Adjustable bamboo organizer for cutlery and utensils.	31	\N	https://images.unsplash.com/photo-1556911220-bff31c875d1f?auto=format&fit=crop&w=1200&q=80	[{"alt": "Kitchen Drawer Organizer — primary product photo", "url": "https://images.unsplash.com/photo-1556911220-bff31c875d1f?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-hom-031/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Kitchen Drawer Organizer — gallery view 2", "url": "https://images.unsplash.com/photo-1581578731548-c64695cc6952?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-031/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Kitchen Drawer Organizer — gallery view 3", "url": "https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-031/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Kitchen Drawer Organizer — thumbnail", "url": "https://images.unsplash.com/photo-1556911220-bff31c875d1f?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-hom-031/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:40.182513+00
a2000000-0000-4000-8000-000000000032	Cotton Bed Sheet Set — Queen	bp-hom-032	4590	Home & Living	a1000000-0000-4000-8000-000000000003	f	2026-07-04 09:06:34.074	Breathable cotton sheet set with pillowcases. Soft wash finish.	17	3990.00	https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?auto=format&fit=crop&w=1200&q=80	[{"alt": "Cotton Bed Sheet Set — Queen — primary product photo", "url": "https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-hom-032/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Cotton Bed Sheet Set — Queen — gallery view 2", "url": "https://images.unsplash.com/photo-1631049307264-da0ec9d70304?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-032/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Cotton Bed Sheet Set — Queen — gallery view 3", "url": "https://images.unsplash.com/photo-1616594039964-ae9021a400a0?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-032/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Cotton Bed Sheet Set — Queen — thumbnail", "url": "https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-hom-032/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:40.37328+00
a2000000-0000-4000-8000-000000000033	Insulated Water Bottle 750ml	bp-hom-033	1690	Home & Living	a1000000-0000-4000-8000-000000000003	f	2026-07-04 09:06:34.074	Stainless bottle that keeps drinks cold for hours. Leak-resistant lid.	58	\N	https://images.unsplash.com/photo-1602143407151-7111542de6e8?auto=format&fit=crop&w=1200&q=80	[{"alt": "Insulated Water Bottle 750ml — primary product photo", "url": "https://images.unsplash.com/photo-1602143407151-7111542de6e8?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-hom-033/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Insulated Water Bottle 750ml — gallery view 2", "url": "https://images.unsplash.com/photo-1523362628745-0c100150b504?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-033/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Insulated Water Bottle 750ml — gallery view 3", "url": "https://images.unsplash.com/photo-1602143407151-7111542de6e8?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-033/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Insulated Water Bottle 750ml — thumbnail", "url": "https://images.unsplash.com/photo-1602143407151-7111542de6e8?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-hom-033/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:40.554426+00
a2000000-0000-4000-8000-000000000029	Collapsible Laundry Basket	bp-hom-029	1290	Home & Living	a1000000-0000-4000-8000-000000000003	f	2026-07-04 09:06:34.074	Space-saving laundry basket that folds flat when not in use.	35	\N	https://images.unsplash.com/photo-1582735689369-4fe89db7114c?auto=format&fit=crop&w=1200&q=80	[{"alt": "Collapsible Laundry Basket — primary product photo", "url": "https://images.unsplash.com/photo-1582735689369-4fe89db7114c?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-hom-029/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Collapsible Laundry Basket — gallery view 2", "url": "https://images.unsplash.com/photo-1556911220-bff31c875d1f?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-029/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Collapsible Laundry Basket — gallery view 3", "url": "https://images.unsplash.com/photo-1581578731548-c64695cc6952?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-029/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Collapsible Laundry Basket — thumbnail", "url": "https://images.unsplash.com/photo-1582735689369-4fe89db7114c?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-hom-029/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-13 15:11:45.293916+00
a2000000-0000-4000-8000-000000000034	Food Storage Containers (6-Pack)	bp-hom-034	2100	Home & Living	a1000000-0000-4000-8000-000000000003	f	2026-07-04 09:06:34.074	Airtight containers in nested sizes for meal prep and leftovers.	39	\N	https://images.unsplash.com/photo-1584568694244-14fbdf83bd30?auto=format&fit=crop&w=1200&q=80	[{"alt": "Food Storage Containers (6-Pack) — primary product photo", "url": "https://images.unsplash.com/photo-1584568694244-14fbdf83bd30?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-hom-034/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Food Storage Containers (6-Pack) — gallery view 2", "url": "https://images.unsplash.com/photo-1600585154340-be6161a56a0c?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-034/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Food Storage Containers (6-Pack) — gallery view 3", "url": "https://images.unsplash.com/photo-1556911220-bff31c875d1f?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-034/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Food Storage Containers (6-Pack) — thumbnail", "url": "https://images.unsplash.com/photo-1584568694244-14fbdf83bd30?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-hom-034/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:40.732452+00
a2000000-0000-4000-8000-000000000036	Wooden Building Blocks (60 pcs)	bp-toy-036	2490	Toys & Kids	a1000000-0000-4000-8000-000000000004	f	2026-07-04 09:06:34.074	Smooth wooden blocks in bright colours for open-ended play.	25	\N	https://images.unsplash.com/photo-1587654780291-39c9404d746b?auto=format&fit=crop&w=1200&q=80	[{"alt": "Wooden Building Blocks (60 pcs) — primary product photo", "url": "https://images.unsplash.com/photo-1587654780291-39c9404d746b?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-toy-036/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Wooden Building Blocks (60 pcs) — gallery view 2", "url": "https://images.unsplash.com/photo-1566576912321-d58ddd7a6088?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-036/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Wooden Building Blocks (60 pcs) — gallery view 3", "url": "https://images.unsplash.com/photo-1596461404969-9ae70f2830c1?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-036/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Wooden Building Blocks (60 pcs) — thumbnail", "url": "https://images.unsplash.com/photo-1587654780291-39c9404d746b?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-toy-036/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:41.195937+00
a2000000-0000-4000-8000-000000000038	Remote Control Car — Rally	bp-toy-038	3590	Toys & Kids	a1000000-0000-4000-8000-000000000004	f	2026-07-04 09:06:34.074	Rechargeable RC car with responsive controls for indoor/outdoor fun.	15	\N	https://images.unsplash.com/photo-1558618666-fcd25c85cd64?auto=format&fit=crop&w=1200&q=80	[{"alt": "Remote Control Car — Rally — primary product photo", "url": "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-toy-038/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Remote Control Car — Rally — gallery view 2", "url": "https://images.unsplash.com/photo-1594787318284-a5e3c0e0b1a0?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-038/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Remote Control Car — Rally — gallery view 3", "url": "https://images.unsplash.com/photo-1566576912321-d58ddd7a6088?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-038/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Remote Control Car — Rally — thumbnail", "url": "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-toy-038/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:41.599218+00
a2000000-0000-4000-8000-000000000039	Family Puzzle Set — 500 pcs	bp-toy-039	1190	Toys & Kids	a1000000-0000-4000-8000-000000000004	f	2026-07-04 09:06:34.074	Colourful 500-piece puzzle with a sturdy poster guide.	33	\N	https://images.unsplash.com/photo-1606092195730-5d7b9af1efc5?auto=format&fit=crop&w=1200&q=80	[{"alt": "Family Puzzle Set — 500 pcs — primary product photo", "url": "https://images.unsplash.com/photo-1606092195730-5d7b9af1efc5?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-toy-039/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Family Puzzle Set — 500 pcs — gallery view 2", "url": "https://images.unsplash.com/photo-1515488042361-ee00e0ddd4e4?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-039/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Family Puzzle Set — 500 pcs — gallery view 3", "url": "https://images.unsplash.com/photo-1587654780291-39c9404d746b?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-039/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Family Puzzle Set — 500 pcs — thumbnail", "url": "https://images.unsplash.com/photo-1606092195730-5d7b9af1efc5?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-toy-039/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:41.849573+00
a2000000-0000-4000-8000-000000000041	Play Kitchen Set — Mini Chef	bp-toy-041	4990	Toys & Kids	a1000000-0000-4000-8000-000000000004	f	2026-07-04 09:06:34.074	Compact play kitchen with pots, utensils, and clickable knobs.	9	\N	https://images.unsplash.com/photo-1558877385-1c5b0b1c0c5e?auto=format&fit=crop&w=1200&q=80	[{"alt": "Play Kitchen Set — Mini Chef — primary product photo", "url": "https://images.unsplash.com/photo-1558877385-1c5b0b1c0c5e?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-toy-041/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Play Kitchen Set — Mini Chef — gallery view 2", "url": "https://images.unsplash.com/photo-1566576912321-d58ddd7a6088?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-041/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Play Kitchen Set — Mini Chef — gallery view 3", "url": "https://images.unsplash.com/photo-1596461404969-9ae70f2830c1?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-041/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Play Kitchen Set — Mini Chef — thumbnail", "url": "https://images.unsplash.com/photo-1558877385-1c5b0b1c0c5e?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-toy-041/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:42.435856+00
a2000000-0000-4000-8000-000000000042	Junior Basketball Size 5	bp-toy-042	1890	Toys & Kids	a1000000-0000-4000-8000-000000000004	f	2026-07-04 09:06:34.074	Durable indoor/outdoor basketball sized for kids and teens.	28	\N	https://images.unsplash.com/photo-1519861531473-9200262188bf?auto=format&fit=crop&w=1200&q=80	[{"alt": "Junior Basketball Size 5 — primary product photo", "url": "https://images.unsplash.com/photo-1519861531473-9200262188bf?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-toy-042/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Junior Basketball Size 5 — gallery view 2", "url": "https://images.unsplash.com/photo-1574629810360-7efbbe195018?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-042/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Junior Basketball Size 5 — gallery view 3", "url": "https://images.unsplash.com/photo-1546519638-68e109498ffc?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-042/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Junior Basketball Size 5 — thumbnail", "url": "https://images.unsplash.com/photo-1519861531473-9200262188bf?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-toy-042/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:36:42.651878+00
3ee87063-de7d-4e6c-b91c-177e9c1a4946	Kalimba Pro 17'	kalimba-pro-17	3500	instruments	\N	f	2026-06-15 10:32:57.103194	High quality kalimba for professionals	19	\N	https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&w=1200&q=80	[{"alt": "Kalimba Pro 17' — primary product photo", "url": "https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&w=1200&q=80", "path": "media/products/kalimba-pro-17/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Kalimba Pro 17' — gallery view 2", "url": "https://images.unsplash.com/photo-1472851294608-062f824d29cc?auto=format&fit=crop&w=1000&q=80", "path": "media/products/kalimba-pro-17/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Kalimba Pro 17' — gallery view 3", "url": "https://images.unsplash.com/photo-1483985988355-763728e1935b?auto=format&fit=crop&w=1000&q=80", "path": "media/products/kalimba-pro-17/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Kalimba Pro 17' — thumbnail", "url": "https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&w=600&q=80", "path": "media/products/kalimba-pro-17/thumb.jpg", "role": "thumb", "isPrimary": false}]	f	2026-08-04 05:36:43.131926+00
8638477e-f5a6-4c64-ae48-0743947ca67c	t-shirt	t-shirt	100	\N	\N	f	2026-07-13 08:43:29.194438	cool tee shirt	24	20.00	https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&w=1200&q=80	[{"alt": "t-shirt — primary product photo", "url": "https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&w=1200&q=80", "path": "media/products/t-shirt/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "t-shirt — gallery view 2", "url": "https://images.unsplash.com/photo-1472851294608-062f824d29cc?auto=format&fit=crop&w=1000&q=80", "path": "media/products/t-shirt/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "t-shirt — gallery view 3", "url": "https://images.unsplash.com/photo-1483985988355-763728e1935b?auto=format&fit=crop&w=1000&q=80", "path": "media/products/t-shirt/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "t-shirt — thumbnail", "url": "https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&w=600&q=80", "path": "media/products/t-shirt/thumb.jpg", "role": "thumb", "isPrimary": false}]	f	2026-08-04 05:36:43.340962+00
a2000000-0000-4000-8000-000000000035	Desk Organizer Tray	bp-hom-035	990	Home & Living	a1000000-0000-4000-8000-000000000003	f	2026-07-04 09:06:34.074	Multi-compartment desk tray for pens, chargers, and sticky notes.	43	\N	https://images.unsplash.com/photo-1593062096033-9a26b09da705?auto=format&fit=crop&w=1200&q=80	[{"alt": "Desk Organizer Tray — primary product photo", "url": "https://images.unsplash.com/photo-1593062096033-9a26b09da705?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-hom-035/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Desk Organizer Tray — gallery view 2", "url": "https://images.unsplash.com/photo-1497366216548-37526070297c?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-035/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Desk Organizer Tray — gallery view 3", "url": "https://images.unsplash.com/photo-1587825140708-dfaf72ae4b04?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-035/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Desk Organizer Tray — thumbnail", "url": "https://images.unsplash.com/photo-1593062096033-9a26b09da705?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-hom-035/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 05:43:34.581033+00
a2000000-0000-4000-8000-000000000011	Urban Runner Sneakers — White	bp-fsh-011	4200	Fashion	a1000000-0000-4000-8000-000000000001	t	2026-06-29 09:06:33.665	Lightweight sneakers with cushioned soles for daily walks and commute.	32	\N	https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=1200&q=80	[{"alt": "Urban Runner Sneakers — White — primary product photo", "url": "https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-fsh-011/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Urban Runner Sneakers — White — gallery view 2", "url": "https://images.unsplash.com/photo-1606107557195-0e29a4b5b4aa?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-011/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Urban Runner Sneakers — White — gallery view 3", "url": "https://images.unsplash.com/photo-1460353581641-37baddab0fa2?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-fsh-011/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Urban Runner Sneakers — White — thumbnail", "url": "https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-fsh-011/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-04 06:25:14.343959+00
a2000000-0000-4000-8000-000000000027	Throw Pillow Cover — Terracotta	bp-hom-027	890	Home & Living	a1000000-0000-4000-8000-000000000003	f	2026-07-04 09:06:34.074	Soft cushion cover with hidden zip. Insert sold separately.	49	\N	https://images.unsplash.com/photo-1584100936595-c0654b55a2e2?auto=format&fit=crop&w=1200&q=80	[{"alt": "Throw Pillow Cover — Terracotta — primary product photo", "url": "https://images.unsplash.com/photo-1584100936595-c0654b55a2e2?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-hom-027/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Throw Pillow Cover — Terracotta — gallery view 2", "url": "https://images.unsplash.com/photo-1631889993959-41b4e9c6e3c5?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-027/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Throw Pillow Cover — Terracotta — gallery view 3", "url": "https://images.unsplash.com/photo-1616486338812-3dadae4b4ace?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-hom-027/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Throw Pillow Cover — Terracotta — thumbnail", "url": "https://images.unsplash.com/photo-1584100936595-c0654b55a2e2?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-hom-027/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-13 13:10:15.315081+00
a2000000-0000-4000-8000-000000000047	Shea Body Lotion 400ml	bp-bty-047	890	Beauty & Accessories	a1000000-0000-4000-8000-000000000005	f	2026-07-04 09:06:34.074	Daily moisturising lotion with shea butter for dry skin.	59	\N	https://images.unsplash.com/photo-1556228578-0d85b1a4d571?auto=format&fit=crop&w=1200&q=80	[{"alt": "Shea Body Lotion 400ml — primary product photo", "url": "https://images.unsplash.com/photo-1556228578-0d85b1a4d571?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-bty-047/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Shea Body Lotion 400ml — gallery view 2", "url": "https://images.unsplash.com/photo-1570194065650-d99fb4b38b17?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-047/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Shea Body Lotion 400ml — gallery view 3", "url": "https://images.unsplash.com/photo-1598440947619-2c35fc9aa908?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-bty-047/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Shea Body Lotion 400ml — thumbnail", "url": "https://images.unsplash.com/photo-1556228578-0d85b1a4d571?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-bty-047/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-13 15:11:45.293916+00
a2000000-0000-4000-8000-000000000043	Skipping Rope — Adjustable	bp-toy-043	450	Toys & Kids	a1000000-0000-4000-8000-000000000004	f	2026-07-04 09:06:34.074	Adjustable skipping rope with comfortable foam grips.	84	\N	https://images.unsplash.com/photo-1599058917212-d750089bc07e?auto=format&fit=crop&w=1200&q=80	[{"alt": "Skipping Rope — Adjustable — primary product photo", "url": "https://images.unsplash.com/photo-1599058917212-d750089bc07e?auto=format&fit=crop&w=1200&q=80", "path": "media/products/bp-toy-043/01.jpg", "role": "primary", "isPrimary": true}, {"alt": "Skipping Rope — Adjustable — gallery view 2", "url": "https://images.unsplash.com/photo-1518611012118-696072aa579a?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-043/02.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Skipping Rope — Adjustable — gallery view 3", "url": "https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?auto=format&fit=crop&w=1000&q=80", "path": "media/products/bp-toy-043/03.jpg", "role": "gallery", "isPrimary": false}, {"alt": "Skipping Rope — Adjustable — thumbnail", "url": "https://images.unsplash.com/photo-1599058917212-d750089bc07e?auto=format&fit=crop&w=600&q=80", "path": "media/products/bp-toy-043/thumb.jpg", "role": "thumb", "isPrimary": false}]	t	2026-08-31 08:01:18.405392+00
\.


--
-- Data for Name: profiles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.profiles (id, email, role, created_at, phone, full_name, updated_at) FROM stdin;
b98a07b1-467f-4e20-ac14-da354b094637	admin@babeesplace.com	admin	2026-07-13 08:19:54.73174+00	+254712345001	Amina Otieno	2026-08-03 09:06:27.276525+00
91877d22-84c1-4253-9e57-13aa5a617b1c	customer@babeesplace.com	customer	2026-07-13 08:19:55.971601+00	+254722111001	Brian Mwangi	2026-08-03 09:06:28.271593+00
ce11a1e1-39f2-471e-9c62-483ba6b04780	wangechi.njeri@babeesplace.demo	customer	2026-08-03 08:52:46.55073+00	+254733222002	Wangechi Njeri	2026-08-03 09:06:28.974677+00
ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7	kevin.ochieng@babeesplace.demo	customer	2026-08-03 08:52:47.092069+00	+254700333003	Kevin Ochieng	2026-08-03 09:06:29.698337+00
328a2e81-1496-404e-88c4-d7f45b72a1b6	faith.wambui@babeesplace.demo	customer	2026-08-03 08:52:47.628967+00	+254711444004	Faith Wambui	2026-08-03 09:06:30.332746+00
1f33a52d-a5b9-475a-bf28-857045f4ad09	daniel.kiprop@babeesplace.demo	customer	2026-08-03 08:52:48.163573+00	+254722555005	Daniel Kiprop	2026-08-03 09:06:30.923555+00
a9c07a6f-4063-4793-a3a0-129d96a50e02	mercy.akinyi@babeesplace.demo	customer	2026-08-03 08:52:48.694168+00	+254733666006	Mercy Akinyi	2026-08-03 09:06:31.643301+00
a2a071d2-da64-4571-9f17-288c5abd72dc	james.mutiso@babeesplace.demo	customer	2026-08-03 08:52:49.235858+00	+254700777007	James Mutiso	2026-08-03 09:06:32.358736+00
d32dcbba-ff92-4df5-bb3e-089d16a5141e	lucy.cherono@babeesplace.demo	customer	2026-08-03 08:52:49.765777+00	+254711888008	Lucy Cherono	2026-08-03 09:06:32.975953+00
eebd94c0-8179-4619-a527-218ac9f7d5c4	nesambulaz@gmail.com	customer	2026-08-13 05:59:54.931587+00	+254740845440	Nestar Ambula	2026-08-13 05:59:54.931587+00
5a04e47f-c9d3-485b-8b23-3aa74d9d729e	minyoso@gmail	customer	2026-08-13 15:10:24.698263+00	+2547555555555	lillian	2026-08-13 15:10:24.698263+00
0615e227-eeae-4afe-b3e2-0acc74b7c439	oscaraseka1111@gmail.com	customer	2026-09-05 10:59:29.011962+00	+254712944345	Oscar Aseka	2026-09-05 10:59:29.011962+00
2c68a903-e68d-4f00-8586-d0efc6047b2b	admin@test.com	admin	2026-06-18 15:16:41.602395+00	+254...	\N	2026-07-12 16:55:40.025782+00
7d487b08-c6f1-4726-a23b-cbb9f7647cbd	samoraedwin603@gmail.com	admin	2026-06-18 23:22:51+00	+254793563731	\N	2026-07-12 16:55:40.025782+00
e47efb2a-278c-4420-b294-87a16e9be730	user1@gmail.com	customer	2026-06-18 15:16:41.602395+00	+254...	\N	2026-07-12 16:55:40.025782+00
323a7849-cfa6-4f19-95a0-2f5f82491436	audit-test-1783930754107@example.com	customer	2026-07-13 08:19:15.006847+00	+254712345678	Audit Test	2026-07-13 08:19:15.006847+00
c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	samoraedwin101@gmail.com	customer	2026-07-13 17:16:52.34404+00			2026-07-13 17:16:52.34404+00
50c6281a-69e0-4c36-a73b-58780a2c8acd	ghostprompt101@gmail.com	customer	2026-07-20 12:50:01.008203+00	+254712345678	ghost	2026-07-20 12:50:01.008203+00
\.


--
-- Data for Name: promotion_rules; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.promotion_rules (id, promotion_id, rule_type, rule_value, created_at) FROM stdin;
\.


--
-- Data for Name: promotions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.promotions (id, code, name, description, promo_type, status, priority, stackable, percent_off, amount_off, buy_quantity, get_quantity, category_id, product_id, min_order_amount, max_discount_amount, usage_limit, usage_count, per_user_limit, starts_at, ends_at, eligibility, metadata, created_at, updated_at) FROM stdin;
69f53b0c-3dcd-413c-a52b-7e78642b6d2d	STORE10	Storewide 10% off	Automatic 10% off orders over 2000 KES	storewide	active	50	f	10.00	\N	\N	\N	\N	\N	2000.00	\N	\N	0	\N	2026-08-02 09:39:54.768035+00	2027-01-30 09:39:54.768035+00	{}	{}	2026-08-03 09:39:54.768035+00	2026-08-03 09:39:54.768035+00
\.


--
-- Data for Name: referrals; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.referrals (id, referrer_user_id, referred_user_id, referral_code, status, reward_points, referred_reward_points, order_id, rewarded_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: reward_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reward_events (id, user_id, order_id, event_type, payload, created_at) FROM stdin;
c30ab3a0-8161-45b3-8f4c-503f22ef0f65	91877d22-84c1-4253-9e57-13aa5a617b1c	fed1e53b-9c95-4d88-96b8-579367bb356c	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 0.00, "gift_card": 0.00, "free_delivery": false}	2026-08-03 09:49:03.818326+00
09b9d300-ad1b-4da6-929d-bd14ee8be5bf	91877d22-84c1-4253-9e57-13aa5a617b1c	26372fc4-819d-4b5c-88bd-6eb628dbe1c4	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 0.00, "gift_card": 0.00, "free_delivery": false}	2026-08-03 09:49:09.610807+00
c67a734d-f92b-458b-8fd1-85acdb3b4ce5	91877d22-84c1-4253-9e57-13aa5a617b1c	fc062098-b9c7-459a-bddb-70903a5bf5b2	checkout_rewards_applied	{"coupon": "WELCOME15", "points": 100, "discount": 143.50, "gift_card": 20.00, "free_delivery": false}	2026-08-03 09:51:54.352147+00
a5f602fc-b3cf-452b-82c4-c167b4214a24	91877d22-84c1-4253-9e57-13aa5a617b1c	0b01e434-5c12-4302-97c6-13910a84bf8e	checkout_rewards_applied	{"coupon": "FREESHIP", "points": 0, "discount": 0.00, "gift_card": 0.00, "free_delivery": true}	2026-08-03 09:51:58.936228+00
470bee07-8f98-4022-907c-cc701a12951b	c1f57dbb-e6f5-4a51-8985-188a6fd3a11b	a362d405-d226-4115-80f6-505fb3b49c21	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 303.00, "gift_card": 0.00, "free_delivery": false}	2026-08-04 05:43:34.581033+00
8595480f-411c-4d9e-9137-1c245eae1374	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	ac2c4dae-27c1-41bb-8ac1-d7f352136d7a	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 629.00, "gift_card": 0.00, "free_delivery": false}	2026-08-04 06:25:14.343959+00
182f066d-a7a4-48a2-a6be-6ea3e7c6352e	eebd94c0-8179-4619-a527-218ac9f7d5c4	21ce8844-157e-4cd8-9e93-2c4d20256a76	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 318.00, "gift_card": 0.00, "free_delivery": false}	2026-08-13 13:04:29.263909+00
64798467-bbcc-4796-bb78-f23ecd9e5d9c	eebd94c0-8179-4619-a527-218ac9f7d5c4	0fd23557-0657-4851-921a-ea57514435d3	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 318.00, "gift_card": 0.00, "free_delivery": false}	2026-08-13 13:08:22.004022+00
b1cd5b54-07e8-4aca-87f4-352d6686bbd3	5a04e47f-c9d3-485b-8b23-3aa74d9d729e	f85d863c-b81e-49e9-8451-7980551af330	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 417.00, "gift_card": 0.00, "free_delivery": false}	2026-08-13 15:11:45.293916+00
3a4341f5-fe8d-4356-a0b2-a7da445a1447	91877d22-84c1-4253-9e57-13aa5a617b1c	cf7e6989-10b8-46dd-bc8b-ac01dd6b6c8a	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 0.00, "gift_card": 0.00, "free_delivery": false, "client_discount_ignored": 99999, "client_free_delivery_ignored": true}	2026-08-31 08:01:17.544622+00
79fbe318-4b62-40e0-8fa3-77491b02ba73	91877d22-84c1-4253-9e57-13aa5a617b1c	f710542d-9cd5-4ed9-b385-cfb566927894	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 289.00, "gift_card": 0.00, "free_delivery": false, "client_discount_ignored": 0, "client_free_delivery_ignored": false}	2026-08-31 08:01:22.45735+00
0aecdca9-d767-403a-892a-ece5e5630451	a2a071d2-da64-4571-9f17-288c5abd72dc	f9ba3141-6266-43c0-8d88-3b73872e1e04	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 289.00, "gift_card": 0.00, "free_delivery": false, "client_discount_ignored": 5000, "client_free_delivery_ignored": true}	2026-08-31 08:01:44.999783+00
c950f081-5dbd-4ff8-880f-71023e830789	a2a071d2-da64-4571-9f17-288c5abd72dc	42db9ff7-2c64-4a03-8dce-f468db78d39a	checkout_rewards_applied	{"coupon": "SAVE200", "points": 0, "discount": 489.00, "gift_card": 0.00, "free_delivery": false, "client_discount_ignored": 1, "client_free_delivery_ignored": false}	2026-08-31 08:01:46.861171+00
2ce63232-5196-4c1f-9976-b265df1dfe71	a2a071d2-da64-4571-9f17-288c5abd72dc	f0f39871-54d9-4d80-9d91-9c5797386384	checkout_rewards_applied	{"coupon": "FREESHIP", "points": 0, "discount": 289.00, "gift_card": 0.00, "free_delivery": true, "client_discount_ignored": 0, "client_free_delivery_ignored": false}	2026-08-31 08:01:48.675828+00
a2f71bbe-dfb8-4ef8-a0bc-5a3630c0dfaf	a2a071d2-da64-4571-9f17-288c5abd72dc	9089649b-aa41-4a73-8d49-1dc2c7b7962a	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 289.00, "gift_card": 0.00, "free_delivery": false, "client_discount_ignored": 9999, "client_free_delivery_ignored": false}	2026-08-31 08:01:51.191813+00
4d3b20d6-20ad-4d9d-a4b8-e78c41d1c529	91877d22-84c1-4253-9e57-13aa5a617b1c	914ce1a1-8697-4df6-831c-960f820e95fb	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 289.00, "gift_card": 0.00, "free_delivery": false, "client_discount_ignored": 99999, "client_free_delivery_ignored": true}	2026-08-31 08:04:37.242615+00
047b7f3e-03ec-4f0b-bab5-2e933025101d	91877d22-84c1-4253-9e57-13aa5a617b1c	85012229-01dc-46f4-a019-327397f8169c	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 289.00, "gift_card": 0.00, "free_delivery": false, "client_discount_ignored": 0, "client_free_delivery_ignored": false}	2026-08-31 08:04:43.820448+00
01648e74-3b03-4920-9e17-b6c53a274be7	91877d22-84c1-4253-9e57-13aa5a617b1c	482bcf5a-fb88-44f1-bda9-b219d8d84373	checkout_rewards_applied	{"coupon": null, "points": 0, "discount": 289.00, "gift_card": 0.00, "free_delivery": false, "client_discount_ignored": 0, "client_free_delivery_ignored": false}	2026-08-31 08:05:43.962896+00
ecd2d6a7-99ca-4c68-be0c-b656ad48c565	1f33a52d-a5b9-475a-bf28-857045f4ad09	9a5dae2b-0b91-49fd-8ed2-a787e9a2d571	checkout_rewards_applied	{"coupon": "WELCOME15", "points": 0, "discount": 722.50, "gift_card": 0.00, "free_delivery": false, "client_discount_ignored": 1, "client_free_delivery_ignored": false}	2026-08-31 08:06:15.826436+00
\.


--
-- Data for Name: wishlists; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.wishlists (id, user_id, product_id, created_at) FROM stdin;
9f90e6c1-59e1-4de8-b40d-7b0b3286d960	b98a07b1-467f-4e20-ac14-da354b094637	3ee87063-de7d-4e6c-b91c-177e9c1a4946	2026-07-13 09:09:40.370531
a7000000-0000-4000-8000-000000000001	91877d22-84c1-4253-9e57-13aa5a617b1c	a2000000-0000-4000-8000-000000000004	2026-07-22 09:06:40.52
a7000000-0000-4000-8000-000000000002	91877d22-84c1-4253-9e57-13aa5a617b1c	a2000000-0000-4000-8000-000000000017	2026-07-23 09:06:40.52
a7000000-0000-4000-8000-000000000003	91877d22-84c1-4253-9e57-13aa5a617b1c	a2000000-0000-4000-8000-000000000021	2026-07-24 09:06:40.52
a7000000-0000-4000-8000-000000000004	ce11a1e1-39f2-471e-9c62-483ba6b04780	a2000000-0000-4000-8000-000000000010	2026-07-25 09:06:40.52
a7000000-0000-4000-8000-000000000005	ce11a1e1-39f2-471e-9c62-483ba6b04780	a2000000-0000-4000-8000-000000000045	2026-07-26 09:06:40.52
a7000000-0000-4000-8000-000000000006	ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7	a2000000-0000-4000-8000-000000000012	2026-07-27 09:06:40.52
a7000000-0000-4000-8000-000000000007	ff3e7a8a-04e8-45bb-b2bb-d9d41361c3e7	a2000000-0000-4000-8000-000000000018	2026-07-28 09:06:40.52
a7000000-0000-4000-8000-000000000008	328a2e81-1496-404e-88c4-d7f45b72a1b6	a2000000-0000-4000-8000-000000000006	2026-07-29 09:06:40.52
a7000000-0000-4000-8000-000000000009	328a2e81-1496-404e-88c4-d7f45b72a1b6	a2000000-0000-4000-8000-000000000031	2026-07-30 09:06:40.52
a7000000-0000-4000-8000-000000000010	1f33a52d-a5b9-475a-bf28-857045f4ad09	a2000000-0000-4000-8000-000000000019	2026-07-31 09:06:40.52
a7000000-0000-4000-8000-000000000011	1f33a52d-a5b9-475a-bf28-857045f4ad09	a2000000-0000-4000-8000-000000000046	2026-07-22 09:06:40.52
a7000000-0000-4000-8000-000000000012	a9c07a6f-4063-4793-a3a0-129d96a50e02	a2000000-0000-4000-8000-000000000002	2026-07-23 09:06:40.52
a7000000-0000-4000-8000-000000000013	a9c07a6f-4063-4793-a3a0-129d96a50e02	a2000000-0000-4000-8000-000000000038	2026-07-24 09:06:40.52
a7000000-0000-4000-8000-000000000014	a2a071d2-da64-4571-9f17-288c5abd72dc	a2000000-0000-4000-8000-000000000024	2026-07-25 09:06:40.52
a7000000-0000-4000-8000-000000000015	a2a071d2-da64-4571-9f17-288c5abd72dc	a2000000-0000-4000-8000-000000000034	2026-07-26 09:06:40.52
a7000000-0000-4000-8000-000000000016	d32dcbba-ff92-4df5-bb3e-089d16a5141e	a2000000-0000-4000-8000-000000000047	2026-07-27 09:06:40.52
a7000000-0000-4000-8000-000000000017	d32dcbba-ff92-4df5-bb3e-089d16a5141e	a2000000-0000-4000-8000-000000000050	2026-07-28 09:06:40.52
a7000000-0000-4000-8000-000000000018	d32dcbba-ff92-4df5-bb3e-089d16a5141e	a2000000-0000-4000-8000-000000000013	2026-07-29 09:06:40.52
69f4bf07-ba28-45de-b918-1bea67e48d42	eebd94c0-8179-4619-a527-218ac9f7d5c4	a2000000-0000-4000-8000-000000000035	2026-08-13 13:01:08.630399
\.


--
-- Data for Name: messages_2026_09_21; Type: TABLE DATA; Schema: realtime; Owner: -
--

COPY realtime.messages_2026_09_21 (topic, extension, payload, event, private, updated_at, inserted_at, id, binary_payload, skip_broadcast) FROM stdin;
\.


--
-- Data for Name: messages_2026_09_22; Type: TABLE DATA; Schema: realtime; Owner: -
--

COPY realtime.messages_2026_09_22 (topic, extension, payload, event, private, updated_at, inserted_at, id, binary_payload, skip_broadcast) FROM stdin;
\.


--
-- Data for Name: messages_2026_09_23; Type: TABLE DATA; Schema: realtime; Owner: -
--

COPY realtime.messages_2026_09_23 (topic, extension, payload, event, private, updated_at, inserted_at, id, binary_payload, skip_broadcast) FROM stdin;
\.


--
-- Data for Name: messages_2026_09_24; Type: TABLE DATA; Schema: realtime; Owner: -
--

COPY realtime.messages_2026_09_24 (topic, extension, payload, event, private, updated_at, inserted_at, id, binary_payload, skip_broadcast) FROM stdin;
\.


--
-- Data for Name: messages_2026_09_25; Type: TABLE DATA; Schema: realtime; Owner: -
--

COPY realtime.messages_2026_09_25 (topic, extension, payload, event, private, updated_at, inserted_at, id, binary_payload, skip_broadcast) FROM stdin;
\.


--
-- Data for Name: messages_2026_09_26; Type: TABLE DATA; Schema: realtime; Owner: -
--

COPY realtime.messages_2026_09_26 (topic, extension, payload, event, private, updated_at, inserted_at, id, binary_payload, skip_broadcast) FROM stdin;
\.


--
-- Data for Name: messages_2026_09_27; Type: TABLE DATA; Schema: realtime; Owner: -
--

COPY realtime.messages_2026_09_27 (topic, extension, payload, event, private, updated_at, inserted_at, id, binary_payload, skip_broadcast) FROM stdin;
\.


--
-- Data for Name: messages_2026_09_28; Type: TABLE DATA; Schema: realtime; Owner: -
--

COPY realtime.messages_2026_09_28 (topic, extension, payload, event, private, updated_at, inserted_at, id, binary_payload, skip_broadcast) FROM stdin;
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: realtime; Owner: -
--

COPY realtime.schema_migrations (version, inserted_at) FROM stdin;
20211116024918	2026-05-29 16:41:54
20211116045059	2026-05-29 16:41:55
20211116050929	2026-05-29 16:41:55
20211116051442	2026-05-29 16:41:55
20211116212300	2026-05-29 16:41:55
20211116213355	2026-05-29 16:41:55
20211116213934	2026-05-29 16:41:55
20211116214523	2026-05-29 16:41:55
20211122062447	2026-05-29 16:41:56
20211124070109	2026-05-29 16:41:56
20211202204204	2026-05-29 16:41:56
20211202204605	2026-05-29 16:41:56
20211210212804	2026-05-29 16:41:56
20211228014915	2026-05-29 16:41:56
20220107221237	2026-05-29 16:41:57
20220228202821	2026-05-29 16:41:57
20220312004840	2026-05-29 16:41:57
20220603231003	2026-05-29 16:41:57
20220603232444	2026-05-29 16:41:57
20220615214548	2026-05-29 16:41:57
20220712093339	2026-05-29 16:41:57
20220908172859	2026-05-29 16:41:58
20220916233421	2026-05-29 16:41:58
20230119133233	2026-05-29 16:41:58
20230128025114	2026-05-29 16:41:58
20230128025212	2026-05-29 16:41:58
20230227211149	2026-05-29 16:41:58
20230228184745	2026-05-29 16:41:58
20230308225145	2026-05-29 16:41:59
20230328144023	2026-05-29 16:41:59
20231018144023	2026-05-29 16:41:59
20231204144023	2026-05-29 16:41:59
20231204144024	2026-05-29 16:41:59
20231204144025	2026-05-29 16:41:59
20240108234812	2026-05-29 16:41:59
20240109165339	2026-05-29 16:42:00
20240227174441	2026-05-29 16:42:00
20240311171622	2026-05-29 16:42:00
20240321100241	2026-05-29 16:42:00
20240401105812	2026-05-29 16:42:01
20240418121054	2026-05-29 16:42:01
20240523004032	2026-05-29 16:42:01
20240618124746	2026-05-29 16:42:01
20240801235015	2026-05-29 16:42:01
20240805133720	2026-05-29 16:42:02
20240827160934	2026-05-29 16:42:02
20240919163303	2026-05-29 16:42:02
20240919163305	2026-05-29 16:42:02
20241019105805	2026-05-29 16:42:02
20241030150047	2026-05-29 16:42:03
20241108114728	2026-05-29 16:42:03
20241121104152	2026-05-29 16:42:03
20241130184212	2026-05-29 16:42:03
20241220035512	2026-05-29 16:42:03
20241220123912	2026-05-29 16:42:03
20241224161212	2026-05-29 16:42:03
20250107150512	2026-05-29 16:42:04
20250110162412	2026-05-29 16:42:04
20250123174212	2026-05-29 16:42:04
20250128220012	2026-05-29 16:42:04
20250506224012	2026-05-29 16:42:04
20250523164012	2026-05-29 16:42:04
20250714121412	2026-05-29 16:42:04
20250905041441	2026-05-29 16:42:04
20251103001201	2026-05-29 16:42:05
20251120212548	2026-05-29 16:42:05
20251120215549	2026-05-29 16:42:05
20260218120000	2026-05-29 16:42:05
20260326120000	2026-05-29 16:42:05
20260514120000	2026-06-15 04:08:03
20260527120000	2026-06-15 04:08:03
20260528120000	2026-06-15 04:08:03
20260603120000	2026-06-15 04:08:03
20260605120000	2026-06-16 00:18:38
20260606110000	2026-06-16 00:18:38
20260616120000	2026-07-10 18:09:19
20260624120000	2026-07-10 18:09:19
20260626120000	2026-07-10 18:09:20
20260706120000	2026-07-10 18:09:20
20260707120000	2026-07-20 08:37:03
20260709120000	2026-07-20 08:37:03
20260714120000	2026-09-04 07:00:16
20260827120000	2026-09-22 13:40:34
20260914120000	2026-09-22 13:40:34
20260916120000	2026-09-22 13:40:34
20260922120000	2026-09-24 04:57:37
\.


--
-- Data for Name: subscription; Type: TABLE DATA; Schema: realtime; Owner: -
--

COPY realtime.subscription (id, subscription_id, entity, filters, claims, created_at, action_filter, selected_columns) FROM stdin;
\.


--
-- Data for Name: buckets; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.buckets (id, name, owner, created_at, updated_at, public, avif_autodetection, file_size_limit, allowed_mime_types, owner_id, type, versioning_status, lifecycle_configuration, lifecycle_configuration_generation) FROM stdin;
products	products	\N	2026-07-12 15:44:22.800126+00	2026-07-12 15:44:22.800126+00	t	f	\N	\N	\N	STANDARD	DISABLED	\N	\N
\.


--
-- Data for Name: buckets_analytics; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.buckets_analytics (name, type, format, created_at, updated_at, id, deleted_at) FROM stdin;
\.


--
-- Data for Name: buckets_vectors; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.buckets_vectors (id, type, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: migrations; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.migrations (id, name, hash, executed_at) FROM stdin;
0	create-migrations-table	e18db593bcde2aca2a408c4d1100f6abba2195df	2026-05-29 16:41:59.990622
1	initialmigration	6ab16121fbaa08bbd11b712d05f358f9b555d777	2026-05-29 16:41:59.997335
2	storage-schema	f6a1fa2c93cbcd16d4e487b362e45fca157a8dbd	2026-05-29 16:42:00.002392
3	pathtoken-column	2cb1b0004b817b29d5b0a971af16bafeede4b70d	2026-05-29 16:42:00.019092
4	add-migrations-rls	427c5b63fe1c5937495d9c635c263ee7a5905058	2026-05-29 16:42:00.029662
5	add-size-functions	79e081a1455b63666c1294a440f8ad4b1e6a7f84	2026-05-29 16:42:00.033923
6	change-column-name-in-get-size	ded78e2f1b5d7e616117897e6443a925965b30d2	2026-05-29 16:42:00.039113
7	add-rls-to-buckets	e7e7f86adbc51049f341dfe8d30256c1abca17aa	2026-05-29 16:42:00.044718
8	add-public-to-buckets	fd670db39ed65f9d08b01db09d6202503ca2bab3	2026-05-29 16:42:00.048138
9	fix-search-function	af597a1b590c70519b464a4ab3be54490712796b	2026-05-29 16:42:00.051632
10	search-files-search-function	b595f05e92f7e91211af1bbfe9c6a13bb3391e16	2026-05-29 16:42:00.055155
11	add-trigger-to-auto-update-updated_at-column	7425bdb14366d1739fa8a18c83100636d74dcaa2	2026-05-29 16:42:00.058733
12	add-automatic-avif-detection-flag	8e92e1266eb29518b6a4c5313ab8f29dd0d08df9	2026-05-29 16:42:00.062165
13	add-bucket-custom-limits	cce962054138135cd9a8c4bcd531598684b25e7d	2026-05-29 16:42:00.065553
14	use-bytes-for-max-size	941c41b346f9802b411f06f30e972ad4744dad27	2026-05-29 16:42:00.068779
15	add-can-insert-object-function	934146bc38ead475f4ef4b555c524ee5d66799e5	2026-05-29 16:42:00.09174
16	add-version	76debf38d3fd07dcfc747ca49096457d95b1221b	2026-05-29 16:42:00.094778
17	drop-owner-foreign-key	f1cbb288f1b7a4c1eb8c38504b80ae2a0153d101	2026-05-29 16:42:00.097856
18	add_owner_id_column_deprecate_owner	e7a511b379110b08e2f214be852c35414749fe66	2026-05-29 16:42:00.100504
19	alter-default-value-objects-id	02e5e22a78626187e00d173dc45f58fa66a4f043	2026-05-29 16:42:00.10517
20	list-objects-with-delimiter	cd694ae708e51ba82bf012bba00caf4f3b6393b7	2026-05-29 16:42:00.107998
21	s3-multipart-uploads	8c804d4a566c40cd1e4cc5b3725a664a9303657f	2026-05-29 16:42:00.112694
22	s3-multipart-uploads-big-ints	9737dc258d2397953c9953d9b86920b8be0cdb73	2026-05-29 16:42:00.124732
23	optimize-search-function	9d7e604cddc4b56a5422dc68c9313f4a1b6f132c	2026-05-29 16:42:00.135701
24	operation-function	8312e37c2bf9e76bbe841aa5fda889206d2bf8aa	2026-05-29 16:42:00.13894
25	custom-metadata	d974c6057c3db1c1f847afa0e291e6165693b990	2026-05-29 16:42:00.141933
26	objects-prefixes	215cabcb7f78121892a5a2037a09fedf9a1ae322	2026-05-29 16:42:00.145249
27	search-v2	859ba38092ac96eb3964d83bf53ccc0b141663a6	2026-05-29 16:42:00.149937
28	object-bucket-name-sorting	c73a2b5b5d4041e39705814fd3a1b95502d38ce4	2026-05-29 16:42:00.152611
29	create-prefixes	ad2c1207f76703d11a9f9007f821620017a66c21	2026-05-29 16:42:00.155621
30	update-object-levels	2be814ff05c8252fdfdc7cfb4b7f5c7e17f0bed6	2026-05-29 16:42:00.158819
31	objects-level-index	b40367c14c3440ec75f19bbce2d71e914ddd3da0	2026-05-29 16:42:00.163697
32	backward-compatible-index-on-objects	e0c37182b0f7aee3efd823298fb3c76f1042c0f7	2026-05-29 16:42:00.167022
33	backward-compatible-index-on-prefixes	b480e99ed951e0900f033ec4eb34b5bdcb4e3d49	2026-05-29 16:42:00.169681
34	optimize-search-function-v1	ca80a3dc7bfef894df17108785ce29a7fc8ee456	2026-05-29 16:42:00.173169
35	add-insert-trigger-prefixes	458fe0ffd07ec53f5e3ce9df51bfdf4861929ccc	2026-05-29 16:42:00.176687
36	optimise-existing-functions	6ae5fca6af5c55abe95369cd4f93985d1814ca8f	2026-05-29 16:42:00.180073
37	add-bucket-name-length-trigger	3944135b4e3e8b22d6d4cbb568fe3b0b51df15c1	2026-05-29 16:42:00.182658
38	iceberg-catalog-flag-on-buckets	02716b81ceec9705aed84aa1501657095b32e5c5	2026-05-29 16:42:00.187679
39	add-search-v2-sort-support	6706c5f2928846abee18461279799ad12b279b78	2026-05-29 16:42:00.195631
40	fix-prefix-race-conditions-optimized	7ad69982ae2d372b21f48fc4829ae9752c518f6b	2026-05-29 16:42:00.198197
41	add-object-level-update-trigger	07fcf1a22165849b7a029deed059ffcde08d1ae0	2026-05-29 16:42:00.201113
42	rollback-prefix-triggers	771479077764adc09e2ea2043eb627503c034cd4	2026-05-29 16:42:00.204178
43	fix-object-level	84b35d6caca9d937478ad8a797491f38b8c2979f	2026-05-29 16:42:00.207419
44	vector-bucket-type	99c20c0ffd52bb1ff1f32fb992f3b351e3ef8fb3	2026-05-29 16:42:00.210172
45	vector-buckets	049e27196d77a7cb76497a85afae669d8b230953	2026-05-29 16:42:00.215924
46	buckets-objects-grants	fedeb96d60fefd8e02ab3ded9fbde05632f84aed	2026-05-29 16:42:00.228759
47	iceberg-table-metadata	649df56855c24d8b36dd4cc1aeb8251aa9ad42c2	2026-05-29 16:42:00.234682
48	iceberg-catalog-ids	e0e8b460c609b9999ccd0df9ad14294613eed939	2026-05-29 16:42:00.237748
49	buckets-objects-grants-postgres	072b1195d0d5a2f888af6b2302a1938dd94b8b3d	2026-05-29 16:42:00.263444
50	search-v2-optimised	6323ac4f850aa14e7387eb32102869578b5bd478	2026-05-29 16:42:00.267449
51	index-backward-compatible-search	2ee395d433f76e38bcd3856debaf6e0e5b674011	2026-05-29 16:42:00.934268
52	drop-not-used-indexes-and-functions	5cc44c8696749ac11dd0dc37f2a3802075f3a171	2026-05-29 16:42:00.935608
53	drop-index-lower-name	d0cb18777d9e2a98ebe0bc5cc7a42e57ebe41854	2026-05-29 16:42:00.944113
54	drop-index-object-level	6289e048b1472da17c31a7eba1ded625a6457e67	2026-05-29 16:42:00.945859
55	prevent-direct-deletes	262a4798d5e0f2e7c8970232e03ce8be695d5819	2026-05-29 16:42:00.947711
56	fix-optimized-search-function	b823ed1e418101032fa01374edc9a436e54e3ed4	2026-05-29 16:42:00.957508
57	s3-multipart-uploads-metadata	f127886e00d1b374fadbc7c6b31e09336aad5287	2026-05-29 16:42:00.961514
58	operation-ergonomics	00ca5d483b3fe0d522133d9002ccc5df98365120	2026-05-29 16:42:00.965393
59	drop-unused-functions	38456f13e39691c2bbb4b5151d0d1cdbabd4a8c4	2026-05-29 16:42:00.968835
60	optimize-existing-functions-again	db35e1c91a9201e59f4fef8d972c2f277d68b157	2026-05-29 16:42:00.973132
61	mark-filename-immutable	fe0096517ae9d60aaec1d110172ba9036dc66bb7	2026-08-16 12:14:48.748697
62	object-versioning-core	0b855f00ff3be0bfca91efee02a9858912491a9a	2026-08-21 15:29:08.856287
63	fix-search-name-relative-to-prefix	c7485e417624f795ce8bb2da21927f48e088904d	2026-08-25 10:40:58.509627
64	fix-search-by-timestamp-sqli	0af424ecd388a39bb1645184b222185a12149675	2026-08-25 10:40:58.536016
65	objects-key-version-index	da319c4b89ba800ce795d1b699f3a70675138058	2026-09-22 13:16:20.212905
66	objects-current-version-index	191466c93aa2c46a00e36505577c5fcab8d7cb4b	2026-09-22 13:16:20.230547
67	objects-null-version-index	15bfe8c35b66642b6c78ba60060fa8793bd2207a	2026-09-22 13:16:20.241683
68	bucket-lifecycle-configuration	3c08f6f889922f399519722a932b51007c11bebc	2026-09-22 13:16:20.243827
69	validate-bucket-lifecycle-constraints	4febacaaaa0e61e2b783bef081fe03a287e65eb3	2026-09-22 13:16:20.299072
70	list-objects-with-versions	5c17c3777616cd8d7b18b82835525fa3205af57b	2026-09-22 13:16:20.306336
71	objects-delete-marker-index	6d14858e66c66f8d6accf8a2630aefd1527fddba	2026-09-22 13:16:21.630487
72	drop-bucketid-objname-index	302beb09e1b469d7d4db19566f2389d280b64aa3	2026-09-22 13:16:21.665418
\.


--
-- Data for Name: objects; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.objects (id, bucket_id, name, owner, created_at, updated_at, last_accessed_at, metadata, version, owner_id, user_metadata, archived_at, is_delete_marker, is_versioned) FROM stdin;
766c469b-5361-4712-abf8-8aab8a959ff3	products	products/8638477e-f5a6-4c64-ae48-0743947ca67c/d1402a3c-d4f0-4d45-96f7-d7f946ebb56c.jpeg	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	2026-07-13 08:43:29.732622+00	2026-07-13 08:43:29.732622+00	2026-07-13 08:43:29.732622+00	{"eTag": "\\"502a7cb80863678298413a336aafcd2d\\"", "size": 94402, "mimetype": "image/jpeg", "cacheControl": "max-age=3600", "lastModified": "2026-07-13T08:43:30.000Z", "contentLength": 94402, "httpStatusCode": 200}	7c626c97-9202-486f-a424-1a0df693d09b	7d487b08-c6f1-4726-a23b-cbb9f7647cbd	{}	\N	f	f
\.


--
-- Data for Name: s3_multipart_uploads; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.s3_multipart_uploads (id, in_progress_size, upload_signature, bucket_id, key, version, owner_id, created_at, user_metadata, metadata) FROM stdin;
\.


--
-- Data for Name: s3_multipart_uploads_parts; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.s3_multipart_uploads_parts (id, upload_id, size, part_number, bucket_id, key, etag, owner_id, version, created_at) FROM stdin;
\.


--
-- Data for Name: vector_indexes; Type: TABLE DATA; Schema: storage; Owner: -
--

COPY storage.vector_indexes (id, name, bucket_id, data_type, dimension, distance_metric, metadata_configuration, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: schema_migrations; Type: TABLE DATA; Schema: supabase_migrations; Owner: -
--

COPY supabase_migrations.schema_migrations (version, statements, name) FROM stdin;
001	{"-- =====================================================================\n-- 001_initial_schema.sql — OFFICIAL BASELINE MIGRATION\n-- =====================================================================\n-- Source: read-only `supabase db dump --linked -s public` of live project\n--         qfcygrxrfszcdltangec (\\"Babis-place\\"), captured 2026-07-12.\n-- Provenance & verification: docs/database/Baseline_Migration_Verification.md\n-- Adoption record:           docs/audits/Phase1_7A_Baseline_Adoption_Report.md\n--\n-- This file is the AUTHORITATIVE representation of the current live schema and\n-- the foundation for all future (forward) migrations. It is a faithful pg_dump\n-- of live; only this comment header was added. Do NOT hand-edit the DDL below —\n-- schema evolution happens in NEW forward migrations per docs/database/Migration_Strategy.md.\n--\n-- Superseded/fictional migrations were moved to supabase/migrations/archive/\n-- (see docs/database/Migration_History.md). Live migration history is empty;\n-- adopting this on live requires `supabase migration repair` (a reconciliation\n-- step — NOT performed here).\n-- =====================================================================\n\nSET statement_timeout = 0","SET lock_timeout = 0","SET idle_in_transaction_session_timeout = 0","SET client_encoding = 'UTF8'","SET standard_conforming_strings = on","SELECT pg_catalog.set_config('search_path', '', false)","SET check_function_bodies = false","SET xmloption = content","SET client_min_messages = warning","SET row_security = off","CREATE SCHEMA IF NOT EXISTS \\"public\\"","ALTER SCHEMA \\"public\\" OWNER TO \\"pg_database_owner\\"","COMMENT ON SCHEMA \\"public\\" IS 'standard public schema'","CREATE TYPE \\"public\\".\\"order_status\\" AS ENUM (\n    'pending',\n    'paid',\n    'fulfilled',\n    'cancelled'\n)","ALTER TYPE \\"public\\".\\"order_status\\" OWNER TO \\"postgres\\"","SET default_tablespace = ''","SET default_table_access_method = \\"heap\\"","CREATE TABLE IF NOT EXISTS \\"public\\".\\"cart_items\\" (\n    \\"id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"() NOT NULL,\n    \\"user_id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"() NOT NULL,\n    \\"product_id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"(),\n    \\"quantity\\" smallint DEFAULT '1'::smallint,\n    \\"created_at\\" timestamp without time zone DEFAULT '2026-06-15 10:35:27.498106'::timestamp without time zone\n)","ALTER TABLE \\"public\\".\\"cart_items\\" OWNER TO \\"postgres\\"","CREATE TABLE IF NOT EXISTS \\"public\\".\\"categories\\" (\n    \\"id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"() NOT NULL,\n    \\"name\\" \\"text\\" NOT NULL,\n    \\"slug\\" \\"text\\",\n    \\"created_at\\" timestamp without time zone\n)","ALTER TABLE \\"public\\".\\"categories\\" OWNER TO \\"postgres\\"","CREATE TABLE IF NOT EXISTS \\"public\\".\\"order_items\\" (\n    \\"id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"() NOT NULL,\n    \\"order_id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"() NOT NULL,\n    \\"product_id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"(),\n    \\"quantity\\" smallint,\n    \\"price\\" numeric,\n    \\"name\\" \\"text\\" DEFAULT ''::\\"text\\"\n)","ALTER TABLE \\"public\\".\\"order_items\\" OWNER TO \\"postgres\\"","CREATE TABLE IF NOT EXISTS \\"public\\".\\"orders\\" (\n    \\"id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"() NOT NULL,\n    \\"user_id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"() NOT NULL,\n    \\"total\\" numeric,\n    \\"status\\" \\"text\\" DEFAULT 'pending'::\\"text\\",\n    \\"created_at\\" timestamp without time zone DEFAULT '2026-06-15 10:38:58.523008'::timestamp without time zone\n)","ALTER TABLE \\"public\\".\\"orders\\" OWNER TO \\"postgres\\"","CREATE TABLE IF NOT EXISTS \\"public\\".\\"products\\" (\n    \\"id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"() NOT NULL,\n    \\"name\\" \\"text\\" NOT NULL,\n    \\"slug\\" \\"text\\",\n    \\"price\\" numeric,\n    \\"category\\" \\"text\\",\n    \\"category_id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"(),\n    \\"featured\\" boolean DEFAULT false,\n    \\"created_at\\" timestamp without time zone DEFAULT '2026-06-15 10:32:57.103194'::timestamp without time zone,\n    \\"Description\\" \\"text\\"\n)","ALTER TABLE \\"public\\".\\"products\\" OWNER TO \\"postgres\\"","CREATE TABLE IF NOT EXISTS \\"public\\".\\"profiles\\" (\n    \\"id\\" \\"uuid\\" NOT NULL,\n    \\"email\\" \\"text\\",\n    \\"role\\" \\"text\\" DEFAULT 'customer'::\\"text\\",\n    \\"created_at\\" timestamp with time zone DEFAULT '2026-06-18 15:16:41.602395+00'::timestamp with time zone,\n    \\"phone\\" \\"text\\" DEFAULT '+254...'::\\"text\\"\n)","ALTER TABLE \\"public\\".\\"profiles\\" OWNER TO \\"postgres\\"","CREATE TABLE IF NOT EXISTS \\"public\\".\\"wishlists\\" (\n    \\"id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"() NOT NULL,\n    \\"user_id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"() NOT NULL,\n    \\"product_id\\" \\"uuid\\" DEFAULT \\"gen_random_uuid\\"(),\n    \\"created_at\\" timestamp without time zone\n)","ALTER TABLE \\"public\\".\\"wishlists\\" OWNER TO \\"postgres\\"","ALTER TABLE ONLY \\"public\\".\\"cart_items\\"\n    ADD CONSTRAINT \\"cart_items_pkey\\" PRIMARY KEY (\\"id\\")","ALTER TABLE ONLY \\"public\\".\\"categories\\"\n    ADD CONSTRAINT \\"categories_pkey\\" PRIMARY KEY (\\"id\\")","ALTER TABLE ONLY \\"public\\".\\"order_items\\"\n    ADD CONSTRAINT \\"order_items_pkey\\" PRIMARY KEY (\\"id\\")","ALTER TABLE ONLY \\"public\\".\\"orders\\"\n    ADD CONSTRAINT \\"orders_pkey\\" PRIMARY KEY (\\"id\\")","ALTER TABLE ONLY \\"public\\".\\"products\\"\n    ADD CONSTRAINT \\"products_pkey\\" PRIMARY KEY (\\"id\\", \\"name\\")","ALTER TABLE ONLY \\"public\\".\\"profiles\\"\n    ADD CONSTRAINT \\"profiles_pkey\\" PRIMARY KEY (\\"id\\")","ALTER TABLE ONLY \\"public\\".\\"wishlists\\"\n    ADD CONSTRAINT \\"wishlists_pkey\\" PRIMARY KEY (\\"id\\")","ALTER TABLE ONLY \\"public\\".\\"order_items\\"\n    ADD CONSTRAINT \\"order_items_order_id_fkey\\" FOREIGN KEY (\\"order_id\\") REFERENCES \\"public\\".\\"orders\\"(\\"id\\") ON DELETE CASCADE","ALTER TABLE ONLY \\"public\\".\\"profiles\\"\n    ADD CONSTRAINT \\"profiles_id_fkey\\" FOREIGN KEY (\\"id\\") REFERENCES \\"auth\\".\\"users\\"(\\"id\\") ON DELETE CASCADE","CREATE POLICY \\"Admins can update orders\\" ON \\"public\\".\\"orders\\" FOR UPDATE USING ((EXISTS ( SELECT 1\n   FROM \\"public\\".\\"profiles\\"\n  WHERE ((\\"profiles\\".\\"id\\" = \\"auth\\".\\"uid\\"()) AND (\\"profiles\\".\\"role\\" = 'admin'::\\"text\\")))))","CREATE POLICY \\"Admins can view all orders\\" ON \\"public\\".\\"orders\\" FOR SELECT USING ((EXISTS ( SELECT 1\n   FROM \\"public\\".\\"profiles\\"\n  WHERE ((\\"profiles\\".\\"id\\" = \\"auth\\".\\"uid\\"()) AND (\\"profiles\\".\\"role\\" = 'admin'::\\"text\\")))))","CREATE POLICY \\"Allow public read access\\" ON \\"public\\".\\"products\\" FOR SELECT USING (true)","CREATE POLICY \\"Block direct insert order items\\" ON \\"public\\".\\"order_items\\" FOR INSERT WITH CHECK (false)","CREATE POLICY \\"Users can insert own orders\\" ON \\"public\\".\\"orders\\" FOR INSERT WITH CHECK ((\\"auth\\".\\"uid\\"() = \\"user_id\\"))","CREATE POLICY \\"Users can insert their own profile\\" ON \\"public\\".\\"profiles\\" FOR INSERT WITH CHECK ((\\"auth\\".\\"uid\\"() = \\"id\\"))","CREATE POLICY \\"Users can update their own profile\\" ON \\"public\\".\\"profiles\\" FOR UPDATE USING ((\\"auth\\".\\"uid\\"() = \\"id\\"))","CREATE POLICY \\"Users can view own order items\\" ON \\"public\\".\\"order_items\\" FOR SELECT USING ((EXISTS ( SELECT 1\n   FROM \\"public\\".\\"orders\\"\n  WHERE ((\\"orders\\".\\"id\\" = \\"order_items\\".\\"order_id\\") AND (\\"orders\\".\\"user_id\\" = \\"auth\\".\\"uid\\"())))))","CREATE POLICY \\"Users can view own orders\\" ON \\"public\\".\\"orders\\" FOR SELECT USING ((\\"auth\\".\\"uid\\"() = \\"user_id\\"))","CREATE POLICY \\"Users can view their own profile\\" ON \\"public\\".\\"profiles\\" FOR SELECT USING ((\\"auth\\".\\"uid\\"() = \\"id\\"))","ALTER TABLE \\"public\\".\\"cart_items\\" ENABLE ROW LEVEL SECURITY","ALTER TABLE \\"public\\".\\"categories\\" ENABLE ROW LEVEL SECURITY","ALTER TABLE \\"public\\".\\"order_items\\" ENABLE ROW LEVEL SECURITY","ALTER TABLE \\"public\\".\\"orders\\" ENABLE ROW LEVEL SECURITY","ALTER TABLE \\"public\\".\\"products\\" ENABLE ROW LEVEL SECURITY","ALTER TABLE \\"public\\".\\"profiles\\" ENABLE ROW LEVEL SECURITY","ALTER TABLE \\"public\\".\\"wishlists\\" ENABLE ROW LEVEL SECURITY","GRANT USAGE ON SCHEMA \\"public\\" TO \\"postgres\\"","GRANT USAGE ON SCHEMA \\"public\\" TO \\"anon\\"","GRANT USAGE ON SCHEMA \\"public\\" TO \\"authenticated\\"","GRANT USAGE ON SCHEMA \\"public\\" TO \\"service_role\\"","GRANT ALL ON TABLE \\"public\\".\\"cart_items\\" TO \\"anon\\"","GRANT ALL ON TABLE \\"public\\".\\"cart_items\\" TO \\"authenticated\\"","GRANT ALL ON TABLE \\"public\\".\\"cart_items\\" TO \\"service_role\\"","GRANT ALL ON TABLE \\"public\\".\\"categories\\" TO \\"anon\\"","GRANT ALL ON TABLE \\"public\\".\\"categories\\" TO \\"authenticated\\"","GRANT ALL ON TABLE \\"public\\".\\"categories\\" TO \\"service_role\\"","GRANT ALL ON TABLE \\"public\\".\\"order_items\\" TO \\"anon\\"","GRANT ALL ON TABLE \\"public\\".\\"order_items\\" TO \\"authenticated\\"","GRANT ALL ON TABLE \\"public\\".\\"order_items\\" TO \\"service_role\\"","GRANT ALL ON TABLE \\"public\\".\\"orders\\" TO \\"anon\\"","GRANT ALL ON TABLE \\"public\\".\\"orders\\" TO \\"authenticated\\"","GRANT ALL ON TABLE \\"public\\".\\"orders\\" TO \\"service_role\\"","GRANT ALL ON TABLE \\"public\\".\\"products\\" TO \\"anon\\"","GRANT ALL ON TABLE \\"public\\".\\"products\\" TO \\"authenticated\\"","GRANT ALL ON TABLE \\"public\\".\\"products\\" TO \\"service_role\\"","GRANT ALL ON TABLE \\"public\\".\\"profiles\\" TO \\"anon\\"","GRANT ALL ON TABLE \\"public\\".\\"profiles\\" TO \\"authenticated\\"","GRANT ALL ON TABLE \\"public\\".\\"profiles\\" TO \\"service_role\\"","GRANT ALL ON TABLE \\"public\\".\\"wishlists\\" TO \\"anon\\"","GRANT ALL ON TABLE \\"public\\".\\"wishlists\\" TO \\"authenticated\\"","GRANT ALL ON TABLE \\"public\\".\\"wishlists\\" TO \\"service_role\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON SEQUENCES TO \\"postgres\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON SEQUENCES TO \\"anon\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON SEQUENCES TO \\"authenticated\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON SEQUENCES TO \\"service_role\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON FUNCTIONS TO \\"postgres\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON FUNCTIONS TO \\"anon\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON FUNCTIONS TO \\"authenticated\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON FUNCTIONS TO \\"service_role\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON TABLES TO \\"postgres\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON TABLES TO \\"anon\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON TABLES TO \\"authenticated\\"","ALTER DEFAULT PRIVILEGES FOR ROLE \\"postgres\\" IN SCHEMA \\"public\\" GRANT ALL ON TABLES TO \\"service_role\\""}	initial_schema
002	{"-- =============================================================================\n-- 002_additive_columns.sql — Additive schema columns  (Strategy: M1)\n-- Babees Place — Phase 1.7B Workstream 1 forward migration\n-- =============================================================================\n-- PURPOSE:\n--   Add the columns the application already expects but that are missing on the\n--   live schema, WITHOUT touching existing data. Unblocks the majority of the\n--   frontend/service reconciliation (products stock/pricing/images, order\n--   payment status, profile full_name, order-item snapshot fields).\n--\n-- DEPENDENCIES:\n--   * 001_initial_schema.sql (baseline) only.\n--\n-- RISK: Low. Purely additive (ADD COLUMN IF NOT EXISTS). New NOT NULL columns\n--   all carry defaults, so existing rows are backfilled automatically.\n--\n-- ROLLBACK:\n--   Drop only the columns introduced here, e.g.:\n--     ALTER TABLE public.products    DROP COLUMN IF EXISTS stock, ... ;\n--     ALTER TABLE public.orders      DROP COLUMN IF EXISTS payment_status, ... ;\n--     ALTER TABLE public.profiles    DROP COLUMN IF EXISTS full_name, updated_at;\n--     ALTER TABLE public.order_items DROP COLUMN IF EXISTS image_url, created_at;\n--   No data migration to reverse (defaults only).\n--\n-- EXPECTED SCHEMA CHANGES:\n--   profiles    += full_name, updated_at\n--   orders      += payment_status, note, updated_at\n--   products    += stock, discount_price, image_url, images, is_active\n--   order_items += image_url, created_at\n--   (Phase-2 order columns delivery_type/pickup_location/delivery_address/\n--    mpesa_receipt_number are intentionally deferred — see authoring report.)\n--\n-- IDEMPOTENCY: ADD COLUMN IF NOT EXISTS throughout; safe to re-run.\n-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.\n-- =============================================================================\n\nBEGIN","-- profiles -------------------------------------------------------------------\nALTER TABLE public.profiles\n  ADD COLUMN IF NOT EXISTS full_name  text,\n  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()","-- orders ---------------------------------------------------------------------\nALTER TABLE public.orders\n  ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'pending',\n  ADD COLUMN IF NOT EXISTS note           text,\n  ADD COLUMN IF NOT EXISTS updated_at     timestamptz NOT NULL DEFAULT now()","-- products -------------------------------------------------------------------\n-- is_active is included per Final_Canonical_Schema §4.3 (D-PROD-11, additive &\n-- non-blocking); see authoring report for the note that no frontend read exists\n-- yet — the column is introduced ahead of app support and is harmless.\nALTER TABLE public.products\n  ADD COLUMN IF NOT EXISTS stock          integer      NOT NULL DEFAULT 0,\n  ADD COLUMN IF NOT EXISTS discount_price numeric(12,2),\n  ADD COLUMN IF NOT EXISTS image_url      text,\n  ADD COLUMN IF NOT EXISTS images         jsonb        NOT NULL DEFAULT '[]'::jsonb,\n  ADD COLUMN IF NOT EXISTS is_active      boolean      NOT NULL DEFAULT true","-- order_items ----------------------------------------------------------------\nALTER TABLE public.order_items\n  ADD COLUMN IF NOT EXISTS image_url  text,\n  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now()",COMMIT}	additive_columns
003	{"-- =============================================================================\n-- 003_functions_and_triggers.sql — Server logic  (Strategy: M4)\n-- Babees Place — Phase 1.7B Workstream 1 forward migration\n-- =============================================================================\n-- PURPOSE:\n--   Recreate the server-authoritative logic against the CANONICAL/live schema:\n--     * is_admin()          — central admin check used by RLS (avoids recursion)\n--     * handle_new_user()   — auto-create a profile row on signup (role customer)\n--     * set_updated_at()    — maintain updated_at on write\n--     * place_order()       — atomic, server-priced checkout with stock locking\n--   Definitions are DERIVED from the archived repo 001 + verified live columns,\n--   adapted to live names (cart_items, orders.total, products.discount_price).\n--   Nothing is fabricated.\n--\n-- DEPENDENCIES:\n--   * 002_additive_columns.sql — place_order/handle_new_user/set_updated_at\n--     require the columns added there (profiles.full_name/updated_at,\n--     orders.payment_status/updated_at, products.stock/discount_price/images/\n--     image_url, order_items.image_url).\n--\n-- RISK: Medium. Checkout depends on place_order(); validate on staging (signup\n--   -> profile row; browse -> cart -> checkout). Functions are pinned to\n--   search_path=public and SECURITY DEFINER where elevation is required.\n--\n-- ROLLBACK:\n--   DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;\n--   DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;\n--   DROP TRIGGER IF EXISTS set_products_updated_at ON public.products;\n--   DROP TRIGGER IF EXISTS set_orders_updated_at   ON public.orders;\n--   DROP FUNCTION IF EXISTS public.place_order(uuid);\n--   DROP FUNCTION IF EXISTS public.set_updated_at();\n--   DROP FUNCTION IF EXISTS public.handle_new_user();\n--   DROP FUNCTION IF EXISTS public.is_admin();\n--\n-- EXPECTED SCHEMA CHANGES:\n--   + functions: is_admin, handle_new_user, set_updated_at, place_order\n--   + triggers : on_auth_user_created (auth.users),\n--                set_updated_at on profiles/products/orders\n--\n-- IDEMPOTENCY: CREATE OR REPLACE FUNCTION; DROP TRIGGER IF EXISTS before CREATE.\n-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.\n-- =============================================================================\n\nBEGIN","-- ---------------------------------------------------------------------------\n-- is_admin(): central admin predicate. SECURITY DEFINER so RLS on profiles\n-- does not recurse; STABLE (single value per statement).\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.is_admin()\nRETURNS boolean\nLANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$\n  SELECT EXISTS (\n    SELECT 1 FROM public.profiles\n    WHERE id = auth.uid() AND role = 'admin'\n  );\n$$","-- ---------------------------------------------------------------------------\n-- handle_new_user(): auto-provision a profile on auth signup.\n-- Canonical role vocabulary is 'customer' (D-CUST-1), matching the live default.\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.handle_new_user()\nRETURNS trigger\nLANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$\nBEGIN\n  INSERT INTO public.profiles (id, email, full_name, phone, role)\n  VALUES (\n    NEW.id,\n    NEW.email,\n    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),\n    COALESCE(NEW.raw_user_meta_data->>'phone', ''),\n    'customer'\n  )\n  ON CONFLICT (id) DO NOTHING;\n  RETURN NEW;\nEND;\n$$","DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users","CREATE TRIGGER on_auth_user_created\n  AFTER INSERT ON auth.users\n  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user()","-- ---------------------------------------------------------------------------\n-- set_updated_at(): generic updated_at maintainer.\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.set_updated_at()\nRETURNS trigger\nLANGUAGE plpgsql AS $$\nBEGIN\n  NEW.updated_at = now();\n  RETURN NEW;\nEND;\n$$","DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles","CREATE TRIGGER set_profiles_updated_at\n  BEFORE UPDATE ON public.profiles\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","DROP TRIGGER IF EXISTS set_products_updated_at ON public.products","CREATE TRIGGER set_products_updated_at\n  BEFORE UPDATE ON public.products\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","DROP TRIGGER IF EXISTS set_orders_updated_at ON public.orders","CREATE TRIGGER set_orders_updated_at\n  BEFORE UPDATE ON public.orders\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","-- ---------------------------------------------------------------------------\n-- place_order(): the ONLY path that writes orders/order_items.\n--   * caller must be the cart owner (or an admin)\n--   * locks product rows (FOR UPDATE) to prevent oversell TOCTOU races\n--   * computes total server-side from live prices (never trust the client)\n--   * snapshots name/price/image into order_items\n--   * decrements stock and clears the cart atomically\n-- Adapted from archived repo 001/002 to live columns: cart_items (not cart),\n-- orders.total (not total_amount), products.discount_price (not \\"discountPrice\\").\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.place_order(p_user_id uuid DEFAULT auth.uid())\nRETURNS uuid\nLANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$\nDECLARE\n  v_order_id uuid;\n  v_total    numeric(12,2) := 0;\n  r          RECORD;\nBEGIN\n  IF p_user_id IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n  IF auth.uid() IS DISTINCT FROM p_user_id AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  -- Lock the product rows referenced by this cart for the transaction.\n  PERFORM 1\n  FROM public.products p\n  JOIN public.cart_items c ON c.product_id = p.id\n  WHERE c.user_id = p_user_id\n  FOR UPDATE OF p;\n\n  -- Validate stock.\n  FOR r IN\n    SELECT c.product_id, c.quantity, p.stock, p.name\n    FROM public.cart_items c\n    JOIN public.products p ON p.id = c.product_id\n    WHERE c.user_id = p_user_id\n  LOOP\n    IF r.stock < r.quantity THEN\n      RAISE EXCEPTION 'Insufficient stock for %', r.name;\n    END IF;\n  END LOOP;\n\n  -- Server-computed total (discount price preferred).\n  SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)\n  INTO v_total\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  IF v_total = 0 THEN\n    RAISE EXCEPTION 'Cart is empty';\n  END IF;\n\n  INSERT INTO public.orders (user_id, status, total, payment_status)\n  VALUES (p_user_id, 'pending', v_total, 'pending')\n  RETURNING id INTO v_order_id;\n\n  INSERT INTO public.order_items (order_id, product_id, name, price, quantity, image_url)\n  SELECT\n    v_order_id,\n    c.product_id,\n    p.name,\n    COALESCE(p.discount_price, p.price),\n    c.quantity,\n    COALESCE(\n      p.image_url,\n      CASE WHEN jsonb_typeof(p.images) = 'array'\n           THEN p.images->0->>'url'\n           ELSE NULL END\n    )\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  UPDATE public.products p\n  SET stock = p.stock - c.quantity\n  FROM public.cart_items c\n  WHERE c.user_id = p_user_id AND c.product_id = p.id;\n\n  DELETE FROM public.cart_items WHERE user_id = p_user_id;\n\n  RETURN v_order_id;\nEND;\n$$","-- Restrict execution to authenticated users only. The baseline default\n-- privileges (001) grant EXECUTE to anon on newly-created functions, so revoke\n-- anon explicitly in addition to PUBLIC; keep authenticated (service_role retains\n-- its default-privilege grant for server-side use).\nREVOKE ALL ON FUNCTION public.place_order(uuid) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.place_order(uuid) TO authenticated",COMMIT}	functions_and_triggers
004	{"-- =============================================================================\n-- 004_rls_and_security.sql — RLS policies + role-escalation fix  (Strategy: M2 + M3)\n-- Babees Place — Phase 1.7B Workstream 1 forward migration\n-- =============================================================================\n-- PURPOSE:\n--   (M3, CRITICAL) Close C-1: users can currently UPDATE their own profile row\n--   and self-escalate role because the live \\"Users can update their own profile\\"\n--   policy has USING only and NO WITH CHECK. Replace it with a WITH CHECK that\n--   forbids changing role, and add a separate admin-only role-change policy.\n--   (M2) Make the deny-all live tables (cart_items, wishlists, categories) usable\n--   and secure, add admin write on products, and remove the direct INSERT on\n--   orders so all order creation flows only through place_order() (D-RLS-4).\n--\n-- DEPENDENCIES:\n--   * 003_functions_and_triggers.sql — policies reference public.is_admin().\n--\n-- RISK: Low–Medium. Behavioral: blocks profile role self-edit and direct order\n--   inserts. Verify normal flows (cart/wishlist read+write, order read) on staging.\n--\n-- ROLLBACK:\n--   Drop the policies created here and, if needed, recreate the prior live\n--   policies (profiles USING-only update, orders owner-insert). See per-block notes.\n--\n-- EXPECTED SCHEMA CHANGES (no data change):\n--   profiles   : replace update-own (adds WITH CHECK role-unchanged); add admin update;\n--                broaden select to own-or-admin.\n--   cart_items : add owner ALL policy.\n--   wishlists  : add owner ALL policy.\n--   categories : add public SELECT + admin write.\n--   products   : keep public SELECT; add admin write.\n--   orders     : remove direct owner INSERT (creation via place_order only).\n--   order_items: keep INSERT blocked; broaden SELECT to owner-OR-admin (§7).\n--\n-- IDEMPOTENCY: DROP POLICY IF EXISTS before each CREATE; ENABLE RLS is a no-op if on.\n-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.\n-- =============================================================================\n\nBEGIN","-- Ensure RLS is enabled (baseline already enables these; no-op if already on).\nALTER TABLE public.profiles    ENABLE ROW LEVEL SECURITY","ALTER TABLE public.categories  ENABLE ROW LEVEL SECURITY","ALTER TABLE public.products    ENABLE ROW LEVEL SECURITY","ALTER TABLE public.cart_items  ENABLE ROW LEVEL SECURITY","ALTER TABLE public.wishlists   ENABLE ROW LEVEL SECURITY","ALTER TABLE public.orders      ENABLE ROW LEVEL SECURITY","ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY","-- ---------------------------------------------------------------------------\n-- PROFILES (M3 CRITICAL)\n-- Replace the live-named policies with canonical, hardened equivalents.\n-- ---------------------------------------------------------------------------\nDROP POLICY IF EXISTS \\"Users can view their own profile\\" ON public.profiles","DROP POLICY IF EXISTS profiles_select_own_or_admin       ON public.profiles","CREATE POLICY profiles_select_own_or_admin ON public.profiles\n  FOR SELECT USING (auth.uid() = id OR public.is_admin())","-- Owner may update their row but MUST NOT change role (compare to stored role).\nDROP POLICY IF EXISTS \\"Users can update their own profile\\" ON public.profiles","DROP POLICY IF EXISTS profiles_update_own                  ON public.profiles","CREATE POLICY profiles_update_own ON public.profiles\n  FOR UPDATE\n  USING (auth.uid() = id)\n  WITH CHECK (\n    auth.uid() = id\n    AND role = (SELECT p.role FROM public.profiles p WHERE p.id = auth.uid())\n  )","-- Admins may change any profile (incl. role).\nDROP POLICY IF EXISTS profiles_update_admin ON public.profiles","CREATE POLICY profiles_update_admin ON public.profiles\n  FOR UPDATE\n  USING (public.is_admin())\n  WITH CHECK (public.is_admin())","-- Keep the existing insert-own policy semantics (recreate canonically).\nDROP POLICY IF EXISTS \\"Users can insert their own profile\\" ON public.profiles","DROP POLICY IF EXISTS profiles_insert_own                  ON public.profiles","CREATE POLICY profiles_insert_own ON public.profiles\n  FOR INSERT WITH CHECK (auth.uid() = id)","-- ---------------------------------------------------------------------------\n-- CART_ITEMS (M2) — owner-scoped full access.\n-- ---------------------------------------------------------------------------\nDROP POLICY IF EXISTS cart_items_all_own ON public.cart_items","CREATE POLICY cart_items_all_own ON public.cart_items\n  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id)","-- ---------------------------------------------------------------------------\n-- WISHLISTS (M2) — owner-scoped full access.\n-- ---------------------------------------------------------------------------\nDROP POLICY IF EXISTS wishlists_all_own ON public.wishlists","CREATE POLICY wishlists_all_own ON public.wishlists\n  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id)","-- ---------------------------------------------------------------------------\n-- CATEGORIES (M2) — public read, admin write.\n-- ---------------------------------------------------------------------------\nDROP POLICY IF EXISTS categories_select_public ON public.categories","CREATE POLICY categories_select_public ON public.categories\n  FOR SELECT USING (true)","DROP POLICY IF EXISTS categories_modify_admin ON public.categories","CREATE POLICY categories_modify_admin ON public.categories\n  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin())","-- ---------------------------------------------------------------------------\n-- PRODUCTS (M2/D-RLS-3) — keep public read (live \\"Allow public read access\\"),\n-- add admin write. Public SELECT + admin ALL are OR-combined, so anonymous\n-- read still works while writes require admin.\n-- ---------------------------------------------------------------------------\nDROP POLICY IF EXISTS products_write_admin ON public.products","CREATE POLICY products_write_admin ON public.products\n  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin())","-- ---------------------------------------------------------------------------\n-- ORDERS (D-RLS-4) — remove direct client INSERT; creation only via place_order().\n-- SELECT (own / admin) and admin UPDATE policies from the baseline are retained.\n-- Rollback: recreate  CREATE POLICY \\"Users can insert own orders\\" ON public.orders\n--           FOR INSERT WITH CHECK (auth.uid() = user_id);\n-- ---------------------------------------------------------------------------\nDROP POLICY IF EXISTS \\"Users can insert own orders\\" ON public.orders","-- ---------------------------------------------------------------------------\n-- ORDER_ITEMS — keep the baseline INSERT block (WITH CHECK false); writes happen\n-- only via place_order() (SECURITY DEFINER). Broaden SELECT from owner-only to\n-- owner-OR-admin so admin order views can read line items (Final_Canonical_Schema\n-- §7). This is additive for admins and does not widen access for regular users.\n-- Rollback: restore the owner-only policy\n--   CREATE POLICY \\"Users can view own order items\\" ON public.order_items\n--     FOR SELECT USING (EXISTS (SELECT 1 FROM public.orders o\n--       WHERE o.id = order_items.order_id AND o.user_id = auth.uid()));\n-- ---------------------------------------------------------------------------\nDROP POLICY IF EXISTS \\"Users can view own order items\\"      ON public.order_items","DROP POLICY IF EXISTS order_items_select_owner_or_admin     ON public.order_items","CREATE POLICY order_items_select_owner_or_admin ON public.order_items\n  FOR SELECT USING (\n    EXISTS (\n      SELECT 1 FROM public.orders o\n      WHERE o.id = order_items.order_id\n        AND (o.user_id = auth.uid() OR public.is_admin())\n    )\n  )",COMMIT}	rls_and_security
005	{"-- =============================================================================\n-- 005_integrity_constraints.sql — Defaults, user FKs, quantity CHECKs  (Strategy: M5a)\n-- Babees Place — Phase 1.7B Workstream 1 forward migration\n-- =============================================================================\n-- PURPOSE:\n--   Restore data integrity for the parts that DO NOT depend on the gated\n--   structural changes (M7 PK) or the gated data normalization (M6 dedupe):\n--     * remove the erroneous live defaults (gen_random_uuid() on FK columns,\n--       the literal phone default) so future inserts cannot fabricate bad keys;\n--     * add foreign keys from user_id columns to auth.users (NOT VALID — enforced\n--       for new/updated rows immediately, existing rows checked later);\n--     * add CHECK (quantity > 0) to cart_items and order_items.\n--   Product-referencing FKs, the (user_id, product_id) UNIQUEs, and the\n--   category FK live in 009_product_integrity.sql because they depend on the\n--   products PK change (008) and the dedupe (007).\n--\n-- DEPENDENCIES:\n--   * 002_additive_columns.sql (no direct column dependency, but ordered after it).\n--\n-- RISK: Medium. FKs are added NOT VALID to avoid failing on any pre-existing\n--   orphan rows; VALIDATE is left as a documented manual step (run after the\n--   orphan check in Phase1_5_Readiness_Report.md §Manual Steps). Dropping a\n--   default never touches stored data.\n--\n-- ROLLBACK:\n--   ALTER TABLE ... DROP CONSTRAINT IF EXISTS <name>;   -- for each FK/CHECK\n--   (Re-adding the old bad defaults is intentionally NOT provided.)\n--\n-- EXPECTED SCHEMA CHANGES (no data change):\n--   - drop DEFAULT on: cart_items.user_id/product_id, wishlists.user_id/product_id,\n--     orders.user_id, order_items.order_id/product_id, products.category_id,\n--     profiles.phone\n--   ~ set created_at DEFAULT now() on cart_items/orders/products/profiles/\n--     categories/wishlists (replaces frozen literal defaults)\n--   + FK (NOT VALID): orders.user_id, cart_items.user_id, wishlists.user_id -> auth.users\n--   + CHECK (quantity > 0): cart_items, order_items\n--\n-- IDEMPOTENCY: DROP DEFAULT is a no-op if absent; DROP CONSTRAINT IF EXISTS before ADD.\n-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.\n-- =============================================================================\n\nBEGIN","-- ---------------------------------------------------------------------------\n-- Remove erroneous live defaults (D-KEY-5). FK/identity columns must never\n-- auto-generate a random value; phone must not default to a literal.\n-- ---------------------------------------------------------------------------\nALTER TABLE public.cart_items  ALTER COLUMN user_id    DROP DEFAULT","ALTER TABLE public.cart_items  ALTER COLUMN product_id DROP DEFAULT","ALTER TABLE public.wishlists   ALTER COLUMN user_id    DROP DEFAULT","ALTER TABLE public.wishlists   ALTER COLUMN product_id DROP DEFAULT","ALTER TABLE public.orders      ALTER COLUMN user_id    DROP DEFAULT","ALTER TABLE public.order_items ALTER COLUMN order_id   DROP DEFAULT","ALTER TABLE public.order_items ALTER COLUMN product_id DROP DEFAULT","ALTER TABLE public.products    ALTER COLUMN category_id DROP DEFAULT","ALTER TABLE public.profiles    ALTER COLUMN phone      DROP DEFAULT","-- ---------------------------------------------------------------------------\n-- Fix hard-coded timestamp defaults (D-KEY-5 / Schema_Comparison_Matrix §5).\n-- The baseline froze created_at to literal 2026 values, so new rows would all\n-- receive the same past timestamp; categories/wishlists had no default at all.\n-- Set them to now() per Final_Canonical_Schema §3. Existing rows are NOT touched\n-- (defaults only affect future inserts) — data is preserved. Column TYPE is left\n-- as-is (timestamptz standardization is an optional follow-up per the matrix).\n-- ---------------------------------------------------------------------------\nALTER TABLE public.cart_items ALTER COLUMN created_at SET DEFAULT now()","ALTER TABLE public.orders     ALTER COLUMN created_at SET DEFAULT now()","ALTER TABLE public.products   ALTER COLUMN created_at SET DEFAULT now()","ALTER TABLE public.profiles   ALTER COLUMN created_at SET DEFAULT now()","ALTER TABLE public.categories ALTER COLUMN created_at SET DEFAULT now()","ALTER TABLE public.wishlists  ALTER COLUMN created_at SET DEFAULT now()","-- ---------------------------------------------------------------------------\n-- User foreign keys -> auth.users (D-KEY-2). Added NOT VALID so the migration\n-- cannot fail on legacy orphan rows; new/updated rows are enforced immediately.\n--\n-- MANUAL (post-check, after confirming zero orphans on staging/prod):\n--   ALTER TABLE public.orders     VALIDATE CONSTRAINT orders_user_id_fkey;\n--   ALTER TABLE public.cart_items VALIDATE CONSTRAINT cart_items_user_id_fkey;\n--   ALTER TABLE public.wishlists  VALIDATE CONSTRAINT wishlists_user_id_fkey;\n-- ---------------------------------------------------------------------------\nALTER TABLE public.orders     DROP CONSTRAINT IF EXISTS orders_user_id_fkey","ALTER TABLE public.orders     ADD  CONSTRAINT orders_user_id_fkey\n  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID","ALTER TABLE public.cart_items DROP CONSTRAINT IF EXISTS cart_items_user_id_fkey","ALTER TABLE public.cart_items ADD  CONSTRAINT cart_items_user_id_fkey\n  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID","ALTER TABLE public.wishlists  DROP CONSTRAINT IF EXISTS wishlists_user_id_fkey","ALTER TABLE public.wishlists  ADD  CONSTRAINT wishlists_user_id_fkey\n  FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID","-- ---------------------------------------------------------------------------\n-- Quantity CHECKs (D-KEY-4). quantity > 0 is expected to already hold, so we\n-- add NOT VALID then VALIDATE within this migration.\n-- ---------------------------------------------------------------------------\nALTER TABLE public.cart_items  DROP CONSTRAINT IF EXISTS cart_items_quantity_check","ALTER TABLE public.cart_items  ADD  CONSTRAINT cart_items_quantity_check\n  CHECK (quantity > 0) NOT VALID","ALTER TABLE public.cart_items  VALIDATE CONSTRAINT cart_items_quantity_check","ALTER TABLE public.order_items DROP CONSTRAINT IF EXISTS order_items_quantity_check","ALTER TABLE public.order_items ADD  CONSTRAINT order_items_quantity_check\n  CHECK (quantity > 0) NOT VALID","ALTER TABLE public.order_items VALIDATE CONSTRAINT order_items_quantity_check",COMMIT}	integrity_constraints
006	{"-- =============================================================================\n-- 006_storage_policies.sql — Product image storage security  (Strategy: M8)\n-- Babees Place — Phase 1.7B Workstream 1 forward migration\n-- =============================================================================\n-- PURPOSE:\n--   Secure the product image bucket. Live has no user-defined storage policies.\n--   Ensure the `products` bucket exists (public) and add storage.objects policies:\n--   public read, admin-only write/update/delete (via is_admin()).\n--\n-- DEPENDENCIES:\n--   * 003_functions_and_triggers.sql — policies reference public.is_admin().\n--   * MANUAL: confirm in the dashboard whether a `products` bucket already exists\n--     and its intended visibility (Reconciliation Decision Log — unresolved Q2).\n--     The INSERT below is idempotent and will not clobber an existing bucket.\n--\n-- RISK: Medium. Misconfigured policies can break admin uploads or public image\n--   reads; verify upload + public URL fetch on staging.\n--\n-- ROLLBACK:\n--   DROP POLICY IF EXISTS \\"products_public_read\\"   ON storage.objects;\n--   DROP POLICY IF EXISTS \\"products_admin_insert\\"  ON storage.objects;\n--   DROP POLICY IF EXISTS \\"products_admin_update\\"  ON storage.objects;\n--   DROP POLICY IF EXISTS \\"products_admin_delete\\"  ON storage.objects;\n--   (Leave the bucket in place; removing a bucket with objects is destructive.)\n--\n-- EXPECTED SCHEMA CHANGES:\n--   + storage.buckets row 'products' (if missing)\n--   + 4 policies on storage.objects scoped to bucket_id = 'products'\n--\n-- IDEMPOTENCY: ON CONFLICT DO NOTHING for the bucket; DROP POLICY IF EXISTS before CREATE.\n-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.\n-- =============================================================================\n\nBEGIN","-- Ensure the bucket exists (public read bucket for product imagery).\nINSERT INTO storage.buckets (id, name, public)\nVALUES ('products', 'products', true)\nON CONFLICT (id) DO NOTHING","-- Public read of product images.\nDROP POLICY IF EXISTS \\"products_public_read\\" ON storage.objects","CREATE POLICY \\"products_public_read\\" ON storage.objects\n  FOR SELECT USING (bucket_id = 'products')","-- Admin-only writes.\nDROP POLICY IF EXISTS \\"products_admin_insert\\" ON storage.objects","CREATE POLICY \\"products_admin_insert\\" ON storage.objects\n  FOR INSERT WITH CHECK (bucket_id = 'products' AND public.is_admin())","DROP POLICY IF EXISTS \\"products_admin_update\\" ON storage.objects","CREATE POLICY \\"products_admin_update\\" ON storage.objects\n  FOR UPDATE USING (bucket_id = 'products' AND public.is_admin())\n             WITH CHECK (bucket_id = 'products' AND public.is_admin())","DROP POLICY IF EXISTS \\"products_admin_delete\\" ON storage.objects","CREATE POLICY \\"products_admin_delete\\" ON storage.objects\n  FOR DELETE USING (bucket_id = 'products' AND public.is_admin())",COMMIT}	storage_policies
007	{"-- =============================================================================\n-- 007_data_normalization.sql — Data cleanup (APPROVAL-GATED)  (Strategy: M6)\n-- Babees Place — Phase 1.7B Workstream 1 forward migration\n-- =============================================================================\n-- 🛑 GATED: requires a fresh backup + explicit approval + a maintenance window.\n--    This migration MUTATES existing production rows. Unlike additive steps it\n--    is NOT reversible with DROP — rollback is restore-from-backup.\n--\n-- PURPOSE:\n--   Normalize live data so the canonical constraints can be enforced:\n--     * backfill profiles.full_name from auth.users metadata;\n--     * normalize profiles.role to ('customer','admin') and enforce a CHECK;\n--     * clean/repair products.category_id (drop garbage random UUIDs from the old\n--       bad default, then backfill from the products.category text) so the FK in\n--       009 can validate;\n--     * dedupe cart_items / wishlists on (user_id, product_id) so the UNIQUE in\n--       009 can be created;\n--     * add orders.status / orders.payment_status CHECKs.\n--\n-- DEPENDENCIES:\n--   * 002_additive_columns.sql (full_name column), 005 (defaults already dropped).\n--\n-- RISK: Medium–High. Data mutation. Take a backup first. Run the read-only\n--   verification queries in Phase1_5_Readiness_Report.md §Manual Steps beforehand.\n--\n-- ROLLBACK: restore from the pre-migration backup (no in-place reversal).\n--\n-- EXPECTED SCHEMA/DATA CHANGES:\n--   ~ profiles.full_name backfilled; profiles.role normalized\n--   ~ products.category_id cleaned + backfilled from products.category\n--   ~ duplicate cart_items/wishlists rows removed (latest kept)\n--   + CHECK profiles.role, orders.status, orders.payment_status\n--\n-- IDEMPOTENCY: updates are guarded by WHERE clauses and safe to re-run; DROP\n--   CONSTRAINT IF EXISTS before ADD.\n-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.\n-- =============================================================================\n\nBEGIN","-- ---------------------------------------------------------------------------\n-- Backfill profiles.full_name from auth metadata where missing.\n-- ---------------------------------------------------------------------------\nUPDATE public.profiles p\nSET full_name = COALESCE(NULLIF(u.raw_user_meta_data->>'full_name', ''), p.full_name)\nFROM auth.users u\nWHERE u.id = p.id\n  AND (p.full_name IS NULL OR p.full_name = '')","-- ---------------------------------------------------------------------------\n-- Normalize profiles.role to the canonical vocabulary, then enforce CHECK.\n-- Any legacy value (e.g. 'user') that is not 'admin' collapses to 'customer'.\n-- ---------------------------------------------------------------------------\nUPDATE public.profiles\nSET role = 'customer'\nWHERE role IS NULL OR role NOT IN ('customer', 'admin')","ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check","ALTER TABLE public.profiles ADD  CONSTRAINT profiles_role_check\n  CHECK (role IN ('customer', 'admin')) NOT VALID","ALTER TABLE public.profiles VALIDATE CONSTRAINT profiles_role_check","-- ---------------------------------------------------------------------------\n-- Repair products.category_id: the old bad default (gen_random_uuid()) may have\n-- left values that reference no category. Null those out, then backfill from the\n-- denormalized products.category text by case-insensitive name match. This makes\n-- the FK in 009 validatable.\n-- ---------------------------------------------------------------------------\nUPDATE public.products\nSET category_id = NULL\nWHERE category_id IS NOT NULL\n  AND category_id NOT IN (SELECT id FROM public.categories)","UPDATE public.products p\nSET category_id = c.id\nFROM public.categories c\nWHERE p.category_id IS NULL\n  AND p.category IS NOT NULL\n  AND lower(p.category) = lower(c.name)","-- ---------------------------------------------------------------------------\n-- Dedupe cart_items / wishlists on (user_id, product_id) — keep the most recent\n-- row so the UNIQUE constraint in 009 can be added.\n-- ---------------------------------------------------------------------------\nDELETE FROM public.cart_items\nWHERE ctid NOT IN (\n  SELECT DISTINCT ON (user_id, product_id) ctid\n  FROM public.cart_items\n  ORDER BY user_id, product_id, created_at DESC NULLS LAST, ctid\n)","DELETE FROM public.wishlists\nWHERE ctid NOT IN (\n  SELECT DISTINCT ON (user_id, product_id) ctid\n  FROM public.wishlists\n  ORDER BY user_id, product_id, created_at DESC NULLS LAST, ctid\n)","-- ---------------------------------------------------------------------------\n-- orders.payment_status CHECK. All rows were defaulted to 'pending' in 002, so\n-- VALIDATE is safe here.\n-- ---------------------------------------------------------------------------\nALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_payment_status_check","ALTER TABLE public.orders ADD  CONSTRAINT orders_payment_status_check\n  CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')) NOT VALID","ALTER TABLE public.orders VALIDATE CONSTRAINT orders_payment_status_check","-- ---------------------------------------------------------------------------\n-- orders.status CHECK. Map the one known legacy enum value; add NOT VALID.\n-- VALIDATE is left MANUAL because the full set of historical status values on\n-- live is an unresolved assumption (see authoring report). Confirm the live\n-- distinct values, map any strays, then:\n--   ALTER TABLE public.orders VALIDATE CONSTRAINT orders_status_check;\n-- ---------------------------------------------------------------------------\nUPDATE public.orders SET status = 'delivered'  WHERE status = 'fulfilled'","-- (No automatic mapping for 'paid' -> keep as data decision; see report.)\nALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check","ALTER TABLE public.orders ADD  CONSTRAINT orders_status_check\n  CHECK (status IN ('pending', 'processing', 'shipped', 'delivered', 'cancelled')) NOT VALID",COMMIT}	data_normalization
008	{"-- =============================================================================\n-- 008_structural_reconciliation.sql — Products PK + column rename (APPROVAL-GATED)  (Strategy: M7)\n-- Babees Place — Phase 1.7B Workstream 1 forward migration\n-- =============================================================================\n-- 🛑 GATED: requires a fresh backup + explicit approval + a maintenance window.\n--    Structural/destructive-class change on `products`. Rollback is\n--    restore-from-backup.\n--\n-- PURPOSE:\n--   * Change products PK from composite (id, name) to (id) so single-column FKs\n--     (009) and single-row .eq('id') guarantees work. PRECONDITION: id is unique.\n--   * Rename products.\\"Description\\" -> description (canonical snake_case).\n--\n-- DEPENDENCIES:\n--   * 007_data_normalization.sql (ordered after gated data cleanup).\n--   * No FK references products yet (product FKs are added in 009), so the PK can\n--     be swapped safely here.\n--\n-- RISK: High. Briefly locks products. The id-uniqueness guard below aborts the\n--   migration with a clear message if duplicates exist (verify beforehand:\n--   SELECT id, count(*) FROM public.products GROUP BY id HAVING count(*) > 1;).\n--\n-- ROLLBACK: restore from the pre-migration backup. (Reversing a PK change +\n--   rename in place is error-prone and intentionally not scripted.)\n--\n-- EXPECTED SCHEMA CHANGES:\n--   ~ products PK (id, name) -> (id)\n--   ~ products.\\"Description\\" renamed to description\n--   - drop unused enum type public.order_status (D-ENUM-1)\n--\n-- IDEMPOTENCY: guarded by catalog checks; safe to re-run (no-op once applied).\n-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.\n-- =============================================================================\n\nBEGIN","-- ---------------------------------------------------------------------------\n-- Guard: abort if products.id is not unique (composite PK could have masked dups).\n-- ---------------------------------------------------------------------------\nDO $$\nDECLARE\n  v_dups bigint;\nBEGIN\n  SELECT count(*) INTO v_dups\n  FROM (SELECT id FROM public.products GROUP BY id HAVING count(*) > 1) d;\n  IF v_dups > 0 THEN\n    RAISE EXCEPTION\n      'Cannot set products PK to (id): % duplicate id value(s) found. Resolve duplicates first.',\n      v_dups;\n  END IF;\nEND $$","-- ---------------------------------------------------------------------------\n-- Swap the primary key to (id). No FK currently references products_pkey.\n-- ---------------------------------------------------------------------------\nDO $$\nBEGIN\n  IF EXISTS (\n    SELECT 1 FROM pg_constraint\n    WHERE conrelid = 'public.products'::regclass\n      AND contype  = 'p'\n      AND array_length(conkey, 1) > 1      -- current PK is composite\n  ) THEN\n    ALTER TABLE public.products DROP CONSTRAINT products_pkey;\n    ALTER TABLE public.products ADD  CONSTRAINT products_pkey PRIMARY KEY (id);\n  ELSIF NOT EXISTS (\n    SELECT 1 FROM pg_constraint\n    WHERE conrelid = 'public.products'::regclass AND contype = 'p'\n  ) THEN\n    ALTER TABLE public.products ADD CONSTRAINT products_pkey PRIMARY KEY (id);\n  END IF;\nEND $$","-- ---------------------------------------------------------------------------\n-- Rename \\"Description\\" -> description (data-preserving RENAME, guarded).\n-- ---------------------------------------------------------------------------\nDO $$\nBEGIN\n  IF EXISTS (\n    SELECT 1 FROM information_schema.columns\n    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'Description'\n  ) AND NOT EXISTS (\n    SELECT 1 FROM information_schema.columns\n    WHERE table_schema = 'public' AND table_name = 'products' AND column_name = 'description'\n  ) THEN\n    ALTER TABLE public.products RENAME COLUMN \\"Description\\" TO description;\n  END IF;\nEND $$","-- ---------------------------------------------------------------------------\n-- D-ENUM-1: drop the unused public.order_status enum. The baseline created it\n-- but orders.status is text (+ CHECK in 007); no column references the type.\n-- Guarded so it only drops when genuinely unreferenced.\n-- Rollback: CREATE TYPE public.order_status AS ENUM ('pending','paid','fulfilled','cancelled');\n-- ---------------------------------------------------------------------------\nDO $$\nBEGIN\n  IF EXISTS (\n    SELECT 1 FROM pg_type t\n    JOIN pg_namespace n ON n.oid = t.typnamespace\n    WHERE t.typname = 'order_status' AND n.nspname = 'public'\n  ) AND NOT EXISTS (\n    SELECT 1\n    FROM pg_attribute a\n    JOIN pg_type t     ON a.atttypid = t.oid\n    JOIN pg_namespace n ON n.oid = t.typnamespace\n    WHERE t.typname = 'order_status' AND n.nspname = 'public'\n      AND a.attnum > 0 AND NOT a.attisdropped\n  ) THEN\n    DROP TYPE public.order_status;\n  END IF;\nEND $$",COMMIT}	structural_reconciliation
009	{"-- =============================================================================\n-- 009_product_integrity.sql — Product FKs + UNIQUE + category FK  (Strategy: M5b)\n-- Babees Place — Phase 1.7B Workstream 1 forward migration\n-- =============================================================================\n-- PURPOSE:\n--   The integrity constraints that depend on the gated steps:\n--     * product-referencing FKs (need products single-column PK from 008);\n--     * UNIQUE (user_id, product_id) on cart_items/wishlists (need dedupe from 007);\n--     * products.category_id -> categories(id) FK (needs category_id repair in 007).\n--\n-- DEPENDENCIES:\n--   * 008_structural_reconciliation.sql (products PK on (id)).\n--   * 007_data_normalization.sql (dedupe + category_id repair).\n--\n-- RISK: Medium–High. Product FKs are added NOT VALID to avoid failing on orphan\n--   product_id values; VALIDATE is a documented manual step. The UNIQUEs will\n--   fail if duplicates remain — 007 must have run.\n--\n-- ROLLBACK:\n--   ALTER TABLE ... DROP CONSTRAINT IF EXISTS <name>;  -- for each FK/UNIQUE\n--\n-- EXPECTED SCHEMA CHANGES (no data change):\n--   + FK (NOT VALID): cart_items.product_id, wishlists.product_id -> products(id) CASCADE\n--   + FK (NOT VALID): order_items.product_id -> products(id) ON DELETE SET NULL\n--   + FK (validated): products.category_id -> categories(id) ON DELETE SET NULL\n--   + UNIQUE: cart_items(user_id, product_id), wishlists(user_id, product_id)\n--\n-- IDEMPOTENCY: DROP CONSTRAINT IF EXISTS before each ADD.\n-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.\n-- =============================================================================\n\nBEGIN","-- ---------------------------------------------------------------------------\n-- Product-referencing FKs (NOT VALID). MANUAL VALIDATE after orphan check:\n--   ALTER TABLE public.cart_items  VALIDATE CONSTRAINT cart_items_product_id_fkey;\n--   ALTER TABLE public.wishlists   VALIDATE CONSTRAINT wishlists_product_id_fkey;\n--   ALTER TABLE public.order_items VALIDATE CONSTRAINT order_items_product_id_fkey;\n-- ---------------------------------------------------------------------------\nALTER TABLE public.cart_items  DROP CONSTRAINT IF EXISTS cart_items_product_id_fkey","ALTER TABLE public.cart_items  ADD  CONSTRAINT cart_items_product_id_fkey\n  FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE NOT VALID","ALTER TABLE public.wishlists   DROP CONSTRAINT IF EXISTS wishlists_product_id_fkey","ALTER TABLE public.wishlists   ADD  CONSTRAINT wishlists_product_id_fkey\n  FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE NOT VALID","-- order_items keeps its product reference but survives product deletion (snapshot).\nALTER TABLE public.order_items DROP CONSTRAINT IF EXISTS order_items_product_id_fkey","ALTER TABLE public.order_items ADD  CONSTRAINT order_items_product_id_fkey\n  FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL NOT VALID","-- ---------------------------------------------------------------------------\n-- category FK. 007 guarantees category_id is NULL or references a real category,\n-- so this can be validated immediately.\n-- ---------------------------------------------------------------------------\nALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_category_id_fkey","ALTER TABLE public.products ADD  CONSTRAINT products_category_id_fkey\n  FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE SET NULL NOT VALID","ALTER TABLE public.products VALIDATE CONSTRAINT products_category_id_fkey","-- ---------------------------------------------------------------------------\n-- Upsert-enabling UNIQUE constraints (dedupe performed in 007).\n-- ---------------------------------------------------------------------------\nALTER TABLE public.cart_items DROP CONSTRAINT IF EXISTS cart_items_user_product_key","ALTER TABLE public.cart_items ADD  CONSTRAINT cart_items_user_product_key\n  UNIQUE (user_id, product_id)","ALTER TABLE public.wishlists  DROP CONSTRAINT IF EXISTS wishlists_user_product_key","ALTER TABLE public.wishlists  ADD  CONSTRAINT wishlists_user_product_key\n  UNIQUE (user_id, product_id)",COMMIT}	product_integrity
010	{"-- =============================================================================\n-- 010_performance_optimizations.sql — Indexes + full-text search\n-- Babees Place — Phase 1.7B Workstream 1 forward migration\n-- =============================================================================\n-- PURPOSE:\n--   Add indexes for the common access paths (FK columns, filters, sorts) and a\n--   GIN full-text index for product search. Completes Final_Canonical_Schema §5.\n--\n-- DEPENDENCIES:\n--   * 002_additive_columns.sql (products.is_active),\n--   * 008_structural_reconciliation.sql (products.description — used by the FTS index).\n--\n-- RISK: Low. Index creation only. Plain CREATE INDEX briefly locks writes; for\n--   LARGE production tables prefer CONCURRENTLY (see the manual block at the end,\n--   which MUST be run OUTSIDE a transaction). At current MVP scale plain creation\n--   is acceptable.\n--\n-- ROLLBACK: DROP INDEX IF EXISTS <name>;  (for each index below)\n--\n-- EXPECTED SCHEMA CHANGES (no data change): indexes only.\n--\n-- IDEMPOTENCY: CREATE INDEX IF NOT EXISTS throughout; safe to re-run.\n-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.\n-- =============================================================================\n\nBEGIN","-- orders ---------------------------------------------------------------------\nCREATE INDEX IF NOT EXISTS idx_orders_user_id     ON public.orders (user_id)","CREATE INDEX IF NOT EXISTS idx_orders_created_at  ON public.orders (created_at DESC)","CREATE INDEX IF NOT EXISTS idx_orders_status      ON public.orders (status)","-- order_items ----------------------------------------------------------------\nCREATE INDEX IF NOT EXISTS idx_order_items_order_id   ON public.order_items (order_id)","CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON public.order_items (product_id)","-- cart_items / wishlists (composite UNIQUE already covers user_id) ------------\nCREATE INDEX IF NOT EXISTS idx_cart_items_product_id ON public.cart_items (product_id)","CREATE INDEX IF NOT EXISTS idx_wishlists_product_id  ON public.wishlists (product_id)","-- products -------------------------------------------------------------------\nCREATE INDEX IF NOT EXISTS idx_products_category_id ON public.products (category_id)","CREATE INDEX IF NOT EXISTS idx_products_is_active   ON public.products (is_active)","-- slug lookup (productService.getProduct slug fallback). Canonical recommends a\n-- UNIQUE index; created as NON-unique here because slug uniqueness on live is\n-- unverified. After confirming no duplicate slugs, replace with:\n--   CREATE UNIQUE INDEX CONCURRENTLY idx_products_slug ON public.products (slug) WHERE slug IS NOT NULL;\nCREATE INDEX IF NOT EXISTS idx_products_slug ON public.products (slug)","-- Full-text search over name + description (storefront search box).\nCREATE INDEX IF NOT EXISTS idx_products_search ON public.products\n  USING gin (to_tsvector('simple', coalesce(name, '') || ' ' || coalesce(description, '')))",COMMIT,"-- =============================================================================\n-- LARGE-TABLE VARIANT (manual). CONCURRENTLY cannot run inside a transaction;\n-- run these statements individually instead of the transactional block above if\n-- the tables are large enough that a brief write lock is unacceptable:\n--\n--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_user_id ON public.orders (user_id);\n--   ... (repeat for each index) ...\n--   CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_search ON public.products\n--     USING gin (to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(description,'')));\n-- ============================================================================="}	performance_optimizations
011	{"-- =============================================================================\n-- 011_inventory_hardening.sql — Inventory constraints + checkout hardening\n-- Babees Place — Phase 2 Workstream 1\n-- =============================================================================\n-- PURPOSE:\n--   * Enforce non-negative stock at the database level\n--   * Reject inactive products in place_order()\n--   * Add cancel_order() to restore stock atomically on cancellation\n--\n-- DEPENDENCIES:\n--   * 002_additive_columns.sql (stock, is_active)\n--   * 003_functions_and_triggers.sql (place_order baseline)\n--   * 007_data_normalization.sql (orders.status CHECK vocabulary)\n--\n-- RISK: Low. Additive constraint + function replacements. cancel_order is new.\n-- =============================================================================\n\nBEGIN","-- ---------------------------------------------------------------------------\n-- Non-negative stock (products.stock >= 0)\n-- ---------------------------------------------------------------------------\nALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_stock_nonneg_check","ALTER TABLE public.products ADD CONSTRAINT products_stock_nonneg_check\n  CHECK (stock >= 0) NOT VALID","ALTER TABLE public.products VALIDATE CONSTRAINT products_stock_nonneg_check","-- ---------------------------------------------------------------------------\n-- place_order(): reject inactive products before stock deduction\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.place_order(p_user_id uuid DEFAULT auth.uid())\nRETURNS uuid\nLANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$\nDECLARE\n  v_order_id uuid;\n  v_total    numeric(12,2) := 0;\n  r          RECORD;\nBEGIN\n  IF p_user_id IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n  IF auth.uid() IS DISTINCT FROM p_user_id AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  PERFORM 1\n  FROM public.products p\n  JOIN public.cart_items c ON c.product_id = p.id\n  WHERE c.user_id = p_user_id\n  FOR UPDATE OF p;\n\n  FOR r IN\n    SELECT c.product_id, c.quantity, p.stock, p.name, p.is_active\n    FROM public.cart_items c\n    JOIN public.products p ON p.id = c.product_id\n    WHERE c.user_id = p_user_id\n  LOOP\n    IF NOT COALESCE(r.is_active, true) THEN\n      RAISE EXCEPTION 'Product % is no longer available', r.name;\n    END IF;\n    IF r.stock < r.quantity THEN\n      RAISE EXCEPTION 'Insufficient stock for %', r.name;\n    END IF;\n  END LOOP;\n\n  SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)\n  INTO v_total\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  IF v_total = 0 THEN\n    RAISE EXCEPTION 'Cart is empty';\n  END IF;\n\n  INSERT INTO public.orders (user_id, status, total, payment_status)\n  VALUES (p_user_id, 'pending', v_total, 'pending')\n  RETURNING id INTO v_order_id;\n\n  INSERT INTO public.order_items (order_id, product_id, name, price, quantity, image_url)\n  SELECT\n    v_order_id,\n    c.product_id,\n    p.name,\n    COALESCE(p.discount_price, p.price),\n    c.quantity,\n    COALESCE(\n      p.image_url,\n      CASE WHEN jsonb_typeof(p.images) = 'array'\n           THEN p.images->0->>'url'\n           ELSE NULL END\n    )\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  UPDATE public.products p\n  SET stock = p.stock - c.quantity\n  FROM public.cart_items c\n  WHERE c.user_id = p_user_id AND c.product_id = p.id;\n\n  DELETE FROM public.cart_items WHERE user_id = p_user_id;\n\n  RETURN v_order_id;\nEND;\n$$","REVOKE ALL ON FUNCTION public.place_order(uuid) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.place_order(uuid) TO authenticated","-- ---------------------------------------------------------------------------\n-- cancel_order(): atomic cancel + stock restore (idempotent)\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid)\nRETURNS void\nLANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$\nDECLARE\n  v_order public.orders%ROWTYPE;\nBEGIN\n  IF p_order_id IS NULL THEN\n    RAISE EXCEPTION 'Order id is required';\n  END IF;\n  IF auth.uid() IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n\n  SELECT * INTO v_order\n  FROM public.orders\n  WHERE id = p_order_id\n  FOR UPDATE;\n\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Order not found';\n  END IF;\n\n  IF auth.uid() IS DISTINCT FROM v_order.user_id AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  -- Idempotent: already cancelled — no double restore\n  IF v_order.status = 'cancelled' THEN\n    RETURN;\n  END IF;\n\n  IF v_order.status = 'delivered' THEN\n    RAISE EXCEPTION 'Delivered orders cannot be cancelled';\n  END IF;\n\n  PERFORM 1\n  FROM public.products p\n  JOIN public.order_items oi ON oi.product_id = p.id\n  WHERE oi.order_id = p_order_id\n    AND oi.product_id IS NOT NULL\n  FOR UPDATE OF p;\n\n  UPDATE public.products p\n  SET stock = p.stock + oi.quantity\n  FROM public.order_items oi\n  WHERE oi.order_id = p_order_id\n    AND oi.product_id = p.id\n    AND oi.product_id IS NOT NULL;\n\n  UPDATE public.orders\n  SET status = 'cancelled', updated_at = now()\n  WHERE id = p_order_id;\nEND;\n$$","REVOKE ALL ON FUNCTION public.cancel_order(uuid) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.cancel_order(uuid) TO authenticated",COMMIT}	inventory_hardening
012	{"-- =============================================================================\n-- 012_product_management.sql — Product management hardening\n-- Babees Place — Phase 2 Workstream 2\n-- =============================================================================\n-- PURPOSE:\n--   * Backfill product/category slugs and enforce uniqueness\n--   * Add price validation CHECK constraints\n--   * Ensure products.updated_at exists (migration-chain reconciliation)\n--\n-- DEPENDENCIES: 001–011 applied\n-- =============================================================================\n\nBEGIN","-- ---------------------------------------------------------------------------\n-- Migration-chain reconciliation: products.updated_at (trigger exists in 003)\n-- ---------------------------------------------------------------------------\nALTER TABLE public.products\n  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()","-- ---------------------------------------------------------------------------\n-- Backfill product slugs from name where missing\n-- ---------------------------------------------------------------------------\nUPDATE public.products\nSET slug = lower(\n  regexp_replace(\n    regexp_replace(trim(name), '[^a-zA-Z0-9]+', '-', 'g'),\n    '(^-+|-+$)', '', 'g'\n  )\n)\nWHERE slug IS NULL OR trim(slug) = ''","-- Resolve duplicate product slugs by appending short id suffix\nWITH ranked AS (\n  SELECT id, slug,\n         row_number() OVER (PARTITION BY slug ORDER BY created_at NULLS LAST, id) AS rn\n  FROM public.products\n  WHERE slug IS NOT NULL AND trim(slug) <> ''\n)\nUPDATE public.products p\nSET slug = p.slug || '-' || left(replace(p.id::text, '-', ''), 8)\nFROM ranked r\nWHERE p.id = r.id AND r.rn > 1","-- ---------------------------------------------------------------------------\n-- Backfill category slugs from name where missing\n-- ---------------------------------------------------------------------------\nUPDATE public.categories\nSET slug = lower(\n  regexp_replace(\n    regexp_replace(trim(name), '[^a-zA-Z0-9]+', '-', 'g'),\n    '(^-+|-+$)', '', 'g'\n  )\n)\nWHERE slug IS NULL OR trim(slug) = ''","WITH ranked AS (\n  SELECT id, slug,\n         row_number() OVER (PARTITION BY slug ORDER BY created_at NULLS LAST, id) AS rn\n  FROM public.categories\n  WHERE slug IS NOT NULL AND trim(slug) <> ''\n)\nUPDATE public.categories c\nSET slug = c.slug || '-' || left(replace(c.id::text, '-', ''), 8)\nFROM ranked r\nWHERE c.id = r.id AND r.rn > 1","-- ---------------------------------------------------------------------------\n-- UNIQUE slugs (partial index allows legacy nulls during transition)\n-- ---------------------------------------------------------------------------\nDROP INDEX IF EXISTS idx_products_slug","CREATE UNIQUE INDEX IF NOT EXISTS idx_products_slug_unique\n  ON public.products (slug) WHERE slug IS NOT NULL AND trim(slug) <> ''","CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_slug_unique\n  ON public.categories (slug) WHERE slug IS NOT NULL AND trim(slug) <> ''","-- ---------------------------------------------------------------------------\n-- Price validation\n-- ---------------------------------------------------------------------------\nALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_price_nonneg_check","ALTER TABLE public.products ADD CONSTRAINT products_price_nonneg_check\n  CHECK (price IS NULL OR price >= 0) NOT VALID","ALTER TABLE public.products VALIDATE CONSTRAINT products_price_nonneg_check","ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_discount_lte_price_check","ALTER TABLE public.products ADD CONSTRAINT products_discount_lte_price_check\n  CHECK (\n    discount_price IS NULL\n    OR price IS NULL\n    OR discount_price <= price\n  ) NOT VALID","ALTER TABLE public.products VALIDATE CONSTRAINT products_discount_lte_price_check",COMMIT}	product_management
013	{"-- =============================================================================\n-- 013_order_fulfillment.sql — Order fulfillment, status machine, pickup locations\n-- Babees Place — Phase 2 Workstream 3\n-- =============================================================================\n-- PURPOSE:\n--   * pickup_locations table + RLS\n--   * Order fulfillment columns (delivery_type, address, fee, etc.)\n--   * Extended order status vocabulary + validated CHECK\n--   * order_events table (notification architecture hook)\n--   * place_order() extended with fulfillment params\n--   * cancel_order() hardened (customer vs admin rules)\n--   * update_order_status() RPC with transition matrix\n--   * update_order_payment_status() RPC (admin COD/manual)\n--\n-- DEPENDENCIES: 001–012 applied\n-- =============================================================================\n\nBEGIN","-- ---------------------------------------------------------------------------\n-- Constants (flat delivery fee in KES)\n-- ---------------------------------------------------------------------------\n-- Delivery fee applied when delivery_type = 'delivery' (enforced in place_order).\n\n-- ---------------------------------------------------------------------------\n-- pickup_locations\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.pickup_locations (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  name text NOT NULL,\n  building text NOT NULL DEFAULT '',\n  description text,\n  operating_hours jsonb NOT NULL DEFAULT '{}'::jsonb,\n  is_active boolean NOT NULL DEFAULT true,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now()\n)","ALTER TABLE public.pickup_locations ENABLE ROW LEVEL SECURITY","DROP POLICY IF EXISTS pickup_locations_select_active ON public.pickup_locations","CREATE POLICY pickup_locations_select_active ON public.pickup_locations\n  FOR SELECT USING (is_active = true OR public.is_admin())","DROP POLICY IF EXISTS pickup_locations_modify_admin ON public.pickup_locations","CREATE POLICY pickup_locations_modify_admin ON public.pickup_locations\n  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin())","CREATE INDEX IF NOT EXISTS idx_pickup_locations_is_active\n  ON public.pickup_locations (is_active) WHERE is_active = true","-- ---------------------------------------------------------------------------\n-- orders: fulfillment columns\n-- ---------------------------------------------------------------------------\nALTER TABLE public.orders\n  ADD COLUMN IF NOT EXISTS delivery_type text,\n  ADD COLUMN IF NOT EXISTS pickup_location_id uuid REFERENCES public.pickup_locations(id) ON DELETE SET NULL,\n  ADD COLUMN IF NOT EXISTS delivery_address jsonb,\n  ADD COLUMN IF NOT EXISTS delivery_fee numeric(12,2) NOT NULL DEFAULT 0,\n  ADD COLUMN IF NOT EXISTS customer_note text","ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_delivery_type_check","ALTER TABLE public.orders ADD CONSTRAINT orders_delivery_type_check\n  CHECK (delivery_type IS NULL OR delivery_type IN ('pickup', 'delivery'))","CREATE INDEX IF NOT EXISTS idx_orders_pickup_location_id\n  ON public.orders (pickup_location_id) WHERE pickup_location_id IS NOT NULL","-- ---------------------------------------------------------------------------\n-- Extended order status vocabulary\n-- ---------------------------------------------------------------------------\nALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check","ALTER TABLE public.orders ADD CONSTRAINT orders_status_check\n  CHECK (status IN (\n    'pending', 'confirmed', 'processing', 'ready_for_pickup',\n    'shipped', 'delivered', 'cancelled'\n  )) NOT VALID","ALTER TABLE public.orders VALIDATE CONSTRAINT orders_status_check","-- ---------------------------------------------------------------------------\n-- order_events (notification architecture — no email/SMS in WS3)\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.order_events (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,\n  event_type text NOT NULL,\n  payload jsonb NOT NULL DEFAULT '{}'::jsonb,\n  created_at timestamptz NOT NULL DEFAULT now()\n)","CREATE INDEX IF NOT EXISTS idx_order_events_order_id\n  ON public.order_events (order_id, created_at DESC)","ALTER TABLE public.order_events ENABLE ROW LEVEL SECURITY","DROP POLICY IF EXISTS order_events_select_owner_or_admin ON public.order_events","CREATE POLICY order_events_select_owner_or_admin ON public.order_events\n  FOR SELECT USING (\n    EXISTS (\n      SELECT 1 FROM public.orders o\n      WHERE o.id = order_events.order_id\n        AND (o.user_id = auth.uid() OR public.is_admin())\n    )\n  )","-- ---------------------------------------------------------------------------\n-- log_order_event() — internal helper for RPCs\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.log_order_event(\n  p_order_id uuid,\n  p_event_type text,\n  p_payload jsonb DEFAULT '{}'::jsonb\n)\nRETURNS void\nLANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$\nBEGIN\n  INSERT INTO public.order_events (order_id, event_type, payload)\n  VALUES (p_order_id, p_event_type, COALESCE(p_payload, '{}'::jsonb));\nEND;\n$$","REVOKE ALL ON FUNCTION public.log_order_event(uuid, text, jsonb) FROM PUBLIC, anon, authenticated","-- ---------------------------------------------------------------------------\n-- place_order(): fulfillment params + delivery fee in total\n-- ---------------------------------------------------------------------------\nDROP FUNCTION IF EXISTS public.place_order(uuid)","CREATE OR REPLACE FUNCTION public.place_order(\n  p_user_id uuid DEFAULT auth.uid(),\n  p_delivery_type text DEFAULT NULL,\n  p_pickup_location_id uuid DEFAULT NULL,\n  p_delivery_address jsonb DEFAULT NULL,\n  p_customer_note text DEFAULT NULL\n)\nRETURNS uuid\nLANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$\nDECLARE\n  v_order_id uuid;\n  v_subtotal numeric(12,2) := 0;\n  v_delivery_fee numeric(12,2) := 0;\n  v_total numeric(12,2) := 0;\n  r RECORD;\nBEGIN\n  IF p_user_id IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n  IF auth.uid() IS DISTINCT FROM p_user_id AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  IF p_delivery_type IS NULL OR p_delivery_type NOT IN ('pickup', 'delivery') THEN\n    RAISE EXCEPTION 'Delivery type is required (pickup or delivery)';\n  END IF;\n\n  IF p_delivery_type = 'pickup' THEN\n    IF p_pickup_location_id IS NULL THEN\n      RAISE EXCEPTION 'Pickup location is required';\n    END IF;\n    IF NOT EXISTS (\n      SELECT 1 FROM public.pickup_locations\n      WHERE id = p_pickup_location_id AND is_active = true\n    ) THEN\n      RAISE EXCEPTION 'Invalid or inactive pickup location';\n    END IF;\n  END IF;\n\n  IF p_delivery_type = 'delivery' THEN\n    IF p_delivery_address IS NULL\n       OR NULLIF(trim(p_delivery_address->>'line1'), '') IS NULL\n       OR NULLIF(trim(p_delivery_address->>'city'), '') IS NULL\n       OR NULLIF(trim(p_delivery_address->>'phone'), '') IS NULL THEN\n      RAISE EXCEPTION 'Delivery address (line1, city, phone) is required';\n    END IF;\n    v_delivery_fee := 200;\n  END IF;\n\n  PERFORM 1\n  FROM public.products p\n  JOIN public.cart_items c ON c.product_id = p.id\n  WHERE c.user_id = p_user_id\n  FOR UPDATE OF p;\n\n  FOR r IN\n    SELECT c.product_id, c.quantity, p.stock, p.name, p.is_active\n    FROM public.cart_items c\n    JOIN public.products p ON p.id = c.product_id\n    WHERE c.user_id = p_user_id\n  LOOP\n    IF NOT COALESCE(r.is_active, true) THEN\n      RAISE EXCEPTION 'Product % is no longer available', r.name;\n    END IF;\n    IF r.stock < r.quantity THEN\n      RAISE EXCEPTION 'Insufficient stock for %', r.name;\n    END IF;\n  END LOOP;\n\n  SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)\n  INTO v_subtotal\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  IF v_subtotal = 0 THEN\n    RAISE EXCEPTION 'Cart is empty';\n  END IF;\n\n  v_total := v_subtotal + v_delivery_fee;\n\n  INSERT INTO public.orders (\n    user_id, status, total, payment_status,\n    delivery_type, pickup_location_id, delivery_address,\n    delivery_fee, customer_note\n  )\n  VALUES (\n    p_user_id, 'pending', v_total, 'pending',\n    p_delivery_type, p_pickup_location_id, p_delivery_address,\n    v_delivery_fee, NULLIF(trim(p_customer_note), '')\n  )\n  RETURNING id INTO v_order_id;\n\n  INSERT INTO public.order_items (order_id, product_id, name, price, quantity, image_url)\n  SELECT\n    v_order_id,\n    c.product_id,\n    p.name,\n    COALESCE(p.discount_price, p.price),\n    c.quantity,\n    COALESCE(\n      p.image_url,\n      CASE WHEN jsonb_typeof(p.images) = 'array'\n           THEN p.images->0->>'url'\n           ELSE NULL END\n    )\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  UPDATE public.products p\n  SET stock = p.stock - c.quantity\n  FROM public.cart_items c\n  WHERE c.user_id = p_user_id AND c.product_id = p.id;\n\n  DELETE FROM public.cart_items WHERE user_id = p_user_id;\n\n  PERFORM public.log_order_event(v_order_id, 'order_placed', jsonb_build_object(\n    'delivery_type', p_delivery_type,\n    'delivery_fee', v_delivery_fee,\n    'subtotal', v_subtotal,\n    'total', v_total\n  ));\n\n  RETURN v_order_id;\nEND;\n$$","REVOKE ALL ON FUNCTION public.place_order(uuid, text, uuid, jsonb, text) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.place_order(uuid, text, uuid, jsonb, text) TO authenticated","-- ---------------------------------------------------------------------------\n-- cancel_order(): customer vs admin cancellation rules + payment refund flag\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid)\nRETURNS void\nLANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$\nDECLARE\n  v_order public.orders%ROWTYPE;\n  v_is_admin boolean;\nBEGIN\n  IF p_order_id IS NULL THEN\n    RAISE EXCEPTION 'Order id is required';\n  END IF;\n  IF auth.uid() IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n\n  v_is_admin := public.is_admin();\n\n  SELECT * INTO v_order\n  FROM public.orders\n  WHERE id = p_order_id\n  FOR UPDATE;\n\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Order not found';\n  END IF;\n\n  IF auth.uid() IS DISTINCT FROM v_order.user_id AND NOT v_is_admin THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  IF v_order.status = 'cancelled' THEN\n    RETURN;\n  END IF;\n\n  IF v_order.status = 'delivered' THEN\n    RAISE EXCEPTION 'Delivered orders cannot be cancelled';\n  END IF;\n\n  IF NOT v_is_admin AND v_order.status NOT IN ('pending', 'confirmed') THEN\n    RAISE EXCEPTION 'This order cannot be cancelled at its current status';\n  END IF;\n\n  PERFORM 1\n  FROM public.products p\n  JOIN public.order_items oi ON oi.product_id = p.id\n  WHERE oi.order_id = p_order_id\n    AND oi.product_id IS NOT NULL\n  FOR UPDATE OF p;\n\n  UPDATE public.products p\n  SET stock = p.stock + oi.quantity\n  FROM public.order_items oi\n  WHERE oi.order_id = p_order_id\n    AND oi.product_id = p.id\n    AND oi.product_id IS NOT NULL;\n\n  UPDATE public.orders\n  SET\n    status = 'cancelled',\n    payment_status = CASE\n      WHEN payment_status = 'paid' THEN 'refunded'\n      ELSE payment_status\n    END,\n    updated_at = now()\n  WHERE id = p_order_id;\n\n  PERFORM public.log_order_event(p_order_id, 'order_cancelled', jsonb_build_object(\n    'previous_status', v_order.status,\n    'cancelled_by', CASE WHEN v_is_admin THEN 'admin' ELSE 'customer' END\n  ));\nEND;\n$$","REVOKE ALL ON FUNCTION public.cancel_order(uuid) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.cancel_order(uuid) TO authenticated","-- ---------------------------------------------------------------------------\n-- update_order_status(): admin-only transition matrix\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.update_order_status(\n  p_order_id uuid,\n  p_status text,\n  p_note text DEFAULT NULL\n)\nRETURNS void\nLANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$\nDECLARE\n  v_order public.orders%ROWTYPE;\n  v_allowed boolean := false;\nBEGIN\n  IF p_order_id IS NULL THEN\n    RAISE EXCEPTION 'Order id is required';\n  END IF;\n  IF auth.uid() IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n  IF NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  IF p_status = 'cancelled' THEN\n    RAISE EXCEPTION 'Use cancel_order() to cancel orders';\n  END IF;\n\n  IF p_status NOT IN (\n    'pending', 'confirmed', 'processing', 'ready_for_pickup',\n    'shipped', 'delivered', 'cancelled'\n  ) THEN\n    RAISE EXCEPTION 'Invalid status: %', p_status;\n  END IF;\n\n  SELECT * INTO v_order\n  FROM public.orders\n  WHERE id = p_order_id\n  FOR UPDATE;\n\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Order not found';\n  END IF;\n\n  IF v_order.status = 'cancelled' OR v_order.status = 'delivered' THEN\n    RAISE EXCEPTION 'Cannot update a % order', v_order.status;\n  END IF;\n\n  IF v_order.status = p_status THEN\n    IF p_note IS NOT NULL THEN\n      UPDATE public.orders SET note = NULLIF(trim(p_note), ''), updated_at = now()\n      WHERE id = p_order_id;\n    END IF;\n    RETURN;\n  END IF;\n\n  -- Transition matrix (delivery_type aware)\n  v_allowed := CASE\n    WHEN v_order.status = 'pending' AND p_status = 'confirmed' THEN true\n    WHEN v_order.status = 'confirmed' AND p_status = 'processing'\n         AND v_order.delivery_type = 'delivery' THEN true\n    WHEN v_order.status = 'confirmed' AND p_status = 'ready_for_pickup'\n         AND v_order.delivery_type = 'pickup' THEN true\n    WHEN v_order.status = 'processing' AND p_status = 'shipped' THEN true\n    WHEN v_order.status = 'ready_for_pickup' AND p_status = 'delivered' THEN true\n    WHEN v_order.status = 'shipped' AND p_status = 'delivered' THEN true\n    ELSE false\n  END;\n\n  IF NOT v_allowed THEN\n    RAISE EXCEPTION 'Transition from % to % is not allowed', v_order.status, p_status;\n  END IF;\n\n  UPDATE public.orders\n  SET\n    status = p_status,\n    note = COALESCE(NULLIF(trim(p_note), ''), note),\n    updated_at = now()\n  WHERE id = p_order_id;\n\n  PERFORM public.log_order_event(p_order_id, 'status_changed', jsonb_build_object(\n    'from', v_order.status,\n    'to', p_status,\n    'note', p_note\n  ));\nEND;\n$$","REVOKE ALL ON FUNCTION public.update_order_status(uuid, text, text) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.update_order_status(uuid, text, text) TO authenticated","-- ---------------------------------------------------------------------------\n-- update_order_payment_status(): admin manual COD / refund marking\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.update_order_payment_status(\n  p_order_id uuid,\n  p_payment_status text,\n  p_note text DEFAULT NULL\n)\nRETURNS void\nLANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$\nDECLARE\n  v_order public.orders%ROWTYPE;\nBEGIN\n  IF p_order_id IS NULL THEN\n    RAISE EXCEPTION 'Order id is required';\n  END IF;\n  IF auth.uid() IS NULL OR NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  IF p_payment_status NOT IN ('pending', 'paid', 'failed', 'refunded') THEN\n    RAISE EXCEPTION 'Invalid payment status: %', p_payment_status;\n  END IF;\n\n  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id FOR UPDATE;\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Order not found';\n  END IF;\n\n  UPDATE public.orders\n  SET\n    payment_status = p_payment_status,\n    note = COALESCE(NULLIF(trim(p_note), ''), note),\n    updated_at = now()\n  WHERE id = p_order_id;\n\n  PERFORM public.log_order_event(p_order_id, 'payment_status_changed', jsonb_build_object(\n    'from', v_order.payment_status,\n    'to', p_payment_status\n  ));\nEND;\n$$","REVOKE ALL ON FUNCTION public.update_order_payment_status(uuid, text, text) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.update_order_payment_status(uuid, text, text) TO authenticated","-- ---------------------------------------------------------------------------\n-- Seed default pickup location when none exist (enables checkout on fresh deploy)\n-- ---------------------------------------------------------------------------\nINSERT INTO public.pickup_locations (name, building, description, operating_hours)\nSELECT\n  'Babees Place Main',\n  'Primary Boutique',\n  'Default pickup hub',\n  '{\\"weekdays\\":{\\"open\\":\\"08:00\\",\\"close\\":\\"18:00\\"},\\"weekends\\":{\\"open\\":\\"09:00\\",\\"close\\":\\"15:00\\"}}'::jsonb\nWHERE NOT EXISTS (SELECT 1 FROM public.pickup_locations)",COMMIT}	order_fulfillment
014	{"-- =============================================================================\n-- 014_customer_profile.sql — Saved addresses & account preferences\n-- Babees Place — Phase 2 Workstream 5 Milestone 5.1\n-- =============================================================================\n-- PURPOSE:\n--   * customer_addresses — multi-address book per customer\n--   * customer_preferences — fulfillment & notification prefs (storage only)\n--   * RLS: customers access own rows only\n--   * Single default address enforced via trigger\n--\n-- DEPENDENCIES: 001–013 applied\n-- =============================================================================\n\nBEGIN","-- ---------------------------------------------------------------------------\n-- customer_addresses\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.customer_addresses (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,\n  label text NOT NULL,\n  recipient_name text NOT NULL,\n  phone text NOT NULL,\n  county text NOT NULL,\n  town text NOT NULL,\n  street_address text NOT NULL,\n  additional_directions text,\n  is_default boolean NOT NULL DEFAULT false,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT customer_addresses_label_check\n    CHECK (label IN ('home', 'work', 'other'))\n)","CREATE INDEX IF NOT EXISTS idx_customer_addresses_user_id\n  ON public.customer_addresses (user_id)","CREATE INDEX IF NOT EXISTS idx_customer_addresses_user_default\n  ON public.customer_addresses (user_id, is_default)\n  WHERE is_default = true","ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY","DROP POLICY IF EXISTS customer_addresses_select_own ON public.customer_addresses","CREATE POLICY customer_addresses_select_own ON public.customer_addresses\n  FOR SELECT USING (user_id = auth.uid())","DROP POLICY IF EXISTS customer_addresses_insert_own ON public.customer_addresses","CREATE POLICY customer_addresses_insert_own ON public.customer_addresses\n  FOR INSERT WITH CHECK (user_id = auth.uid())","DROP POLICY IF EXISTS customer_addresses_update_own ON public.customer_addresses","CREATE POLICY customer_addresses_update_own ON public.customer_addresses\n  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid())","DROP POLICY IF EXISTS customer_addresses_delete_own ON public.customer_addresses","CREATE POLICY customer_addresses_delete_own ON public.customer_addresses\n  FOR DELETE USING (user_id = auth.uid())","-- ---------------------------------------------------------------------------\n-- customer_preferences (one row per customer)\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.customer_preferences (\n  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,\n  preferred_fulfillment text,\n  preferred_pickup_location_id uuid REFERENCES public.pickup_locations(id) ON DELETE SET NULL,\n  marketing_emails boolean NOT NULL DEFAULT false,\n  sms_notifications boolean NOT NULL DEFAULT false,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT customer_preferences_fulfillment_check\n    CHECK (preferred_fulfillment IS NULL OR preferred_fulfillment IN ('pickup', 'delivery'))\n)","ALTER TABLE public.customer_preferences ENABLE ROW LEVEL SECURITY","DROP POLICY IF EXISTS customer_preferences_select_own ON public.customer_preferences","CREATE POLICY customer_preferences_select_own ON public.customer_preferences\n  FOR SELECT USING (user_id = auth.uid())","DROP POLICY IF EXISTS customer_preferences_insert_own ON public.customer_preferences","CREATE POLICY customer_preferences_insert_own ON public.customer_preferences\n  FOR INSERT WITH CHECK (user_id = auth.uid())","DROP POLICY IF EXISTS customer_preferences_update_own ON public.customer_preferences","CREATE POLICY customer_preferences_update_own ON public.customer_preferences\n  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid())","DROP POLICY IF EXISTS customer_preferences_delete_own ON public.customer_preferences","CREATE POLICY customer_preferences_delete_own ON public.customer_preferences\n  FOR DELETE USING (user_id = auth.uid())","-- ---------------------------------------------------------------------------\n-- updated_at triggers (set_updated_at from 003)\n-- ---------------------------------------------------------------------------\nDROP TRIGGER IF EXISTS customer_addresses_set_updated_at ON public.customer_addresses","CREATE TRIGGER customer_addresses_set_updated_at\n  BEFORE UPDATE ON public.customer_addresses\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","DROP TRIGGER IF EXISTS customer_preferences_set_updated_at ON public.customer_preferences","CREATE TRIGGER customer_preferences_set_updated_at\n  BEFORE UPDATE ON public.customer_preferences\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","-- ---------------------------------------------------------------------------\n-- Ensure at most one default address per user\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.enforce_single_default_address()\nRETURNS trigger\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public AS $$\nBEGIN\n  IF NEW.is_default THEN\n    UPDATE public.customer_addresses\n    SET is_default = false\n    WHERE user_id = NEW.user_id\n      AND id IS DISTINCT FROM NEW.id\n      AND is_default = true;\n  END IF;\n  RETURN NEW;\nEND;\n$$","DROP TRIGGER IF EXISTS customer_addresses_single_default ON public.customer_addresses","CREATE TRIGGER customer_addresses_single_default\n  AFTER INSERT OR UPDATE OF is_default ON public.customer_addresses\n  FOR EACH ROW\n  WHEN (NEW.is_default = true)\n  EXECUTE FUNCTION public.enforce_single_default_address()",COMMIT}	customer_profile
015	{"-- 015_recommendations.sql\n-- Phase 2 WS5 Milestone 5.3 — storefront recommendation helpers\n--\n-- Best-seller aggregates require reading across customers' order_items.\n-- RLS on order_items is owner-or-admin, so a SECURITY DEFINER RPC exposes\n-- only anonymized product_id + units_sold for active, in-stock products.\n-- No new tables. Idempotent.\n\nCREATE OR REPLACE FUNCTION public.get_bestseller_product_ids(p_limit integer DEFAULT 12)\nRETURNS TABLE (product_id uuid, units_sold bigint)\nLANGUAGE sql\nSTABLE\nSECURITY DEFINER\nSET search_path = public\nAS $$\n  SELECT\n    oi.product_id,\n    SUM(oi.quantity)::bigint AS units_sold\n  FROM public.order_items oi\n  INNER JOIN public.orders o ON o.id = oi.order_id\n  INNER JOIN public.products p ON p.id = oi.product_id\n  WHERE oi.product_id IS NOT NULL\n    AND o.status IS DISTINCT FROM 'cancelled'\n    AND p.is_active IS TRUE\n  GROUP BY oi.product_id\n  ORDER BY units_sold DESC, oi.product_id\n  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 12), 50));\n$$","COMMENT ON FUNCTION public.get_bestseller_product_ids(integer) IS\n  'WS5 M5.3 — anonymized bestseller ids for storefront recommendations (SECURITY DEFINER).'","REVOKE ALL ON FUNCTION public.get_bestseller_product_ids(integer) FROM PUBLIC","GRANT EXECUTE ON FUNCTION public.get_bestseller_product_ids(integer) TO anon, authenticated"}	recommendations
016	{"-- 016_payments.sql\n-- Workstream 6 — Payments foundation\n--\n-- Adds payments + payment_events, order payment_method / mpesa_receipt_number,\n-- extends place_order with optional payment method (default cod), and\n-- SECURITY DEFINER helpers for initiating / finalizing payments.\n-- Idempotent where practical. Preserves COD as default.\n\n-- ---------------------------------------------------------------------------\n-- 1. Orders: payment method + M-Pesa receipt mirror\n-- ---------------------------------------------------------------------------\nALTER TABLE public.orders\n  ADD COLUMN IF NOT EXISTS payment_method text NOT NULL DEFAULT 'cod'","ALTER TABLE public.orders\n  ADD COLUMN IF NOT EXISTS mpesa_receipt_number text","DO $$\nBEGIN\n  IF NOT EXISTS (\n    SELECT 1 FROM pg_constraint WHERE conname = 'orders_payment_method_check'\n  ) THEN\n    ALTER TABLE public.orders\n      ADD CONSTRAINT orders_payment_method_check\n      CHECK (payment_method IN ('cod', 'mpesa', 'card', 'paypal', 'bank_transfer'));\n  END IF;\nEND $$","CREATE INDEX IF NOT EXISTS idx_orders_payment_method ON public.orders (payment_method)","CREATE INDEX IF NOT EXISTS idx_orders_payment_status ON public.orders (payment_status)","COMMENT ON COLUMN public.orders.payment_method IS\n  'WS6 — checkout payment channel (cod default).'","COMMENT ON COLUMN public.orders.mpesa_receipt_number IS\n  'WS6 — mirrored from payments.receipt_number when M-Pesa succeeds.'","-- ---------------------------------------------------------------------------\n-- 2. payments\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.payments (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,\n  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,\n  provider text NOT NULL DEFAULT 'mpesa',\n  method text NOT NULL DEFAULT 'mpesa',\n  status text NOT NULL DEFAULT 'pending',\n  amount numeric(12,2) NOT NULL,\n  currency text NOT NULL DEFAULT 'KES',\n  phone_number text,\n  transaction_reference text,\n  checkout_request_id text,\n  merchant_request_id text,\n  receipt_number text,\n  failure_reason text,\n  raw_request jsonb NOT NULL DEFAULT '{}'::jsonb,\n  raw_response jsonb NOT NULL DEFAULT '{}'::jsonb,\n  raw_callback jsonb NOT NULL DEFAULT '{}'::jsonb,\n  expires_at timestamptz,\n  paid_at timestamptz,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT payments_provider_check\n    CHECK (provider IN ('mpesa', 'mock_mpesa', 'card', 'paypal', 'bank', 'cod')),\n  CONSTRAINT payments_method_check\n    CHECK (method IN ('cod', 'mpesa', 'card', 'paypal', 'bank_transfer')),\n  CONSTRAINT payments_status_check\n    CHECK (status IN (\n      'pending', 'initiated', 'processing', 'paid',\n      'failed', 'cancelled', 'expired', 'refunded'\n    )),\n  CONSTRAINT payments_amount_positive CHECK (amount > 0)\n)","CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_checkout_request_id_unique\n  ON public.payments (checkout_request_id)\n  WHERE checkout_request_id IS NOT NULL","CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_merchant_request_id_unique\n  ON public.payments (merchant_request_id)\n  WHERE merchant_request_id IS NOT NULL","CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_receipt_number_unique\n  ON public.payments (receipt_number)\n  WHERE receipt_number IS NOT NULL","CREATE INDEX IF NOT EXISTS idx_payments_order_id ON public.payments (order_id)","CREATE INDEX IF NOT EXISTS idx_payments_user_id ON public.payments (user_id)","CREATE INDEX IF NOT EXISTS idx_payments_status ON public.payments (status)","CREATE INDEX IF NOT EXISTS idx_payments_created_at ON public.payments (created_at DESC)","DROP TRIGGER IF EXISTS payments_set_updated_at ON public.payments","CREATE TRIGGER payments_set_updated_at\n  BEFORE UPDATE ON public.payments\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","-- ---------------------------------------------------------------------------\n-- 3. payment_events (audit / callback log)\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.payment_events (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  payment_id uuid NOT NULL REFERENCES public.payments(id) ON DELETE CASCADE,\n  event_type text NOT NULL,\n  payload jsonb NOT NULL DEFAULT '{}'::jsonb,\n  created_at timestamptz NOT NULL DEFAULT now()\n)","CREATE INDEX IF NOT EXISTS idx_payment_events_payment_id_created\n  ON public.payment_events (payment_id, created_at ASC)","-- ---------------------------------------------------------------------------\n-- 4. RLS\n-- ---------------------------------------------------------------------------\nALTER TABLE public.payments ENABLE ROW LEVEL SECURITY","ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY","DROP POLICY IF EXISTS payments_select_own_or_admin ON public.payments","CREATE POLICY payments_select_own_or_admin ON public.payments\n  FOR SELECT TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS payments_insert_own ON public.payments","CREATE POLICY payments_insert_own ON public.payments\n  FOR INSERT TO authenticated\n  WITH CHECK (user_id = auth.uid())","DROP POLICY IF EXISTS payments_update_own_or_admin ON public.payments","CREATE POLICY payments_update_own_or_admin ON public.payments\n  FOR UPDATE TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())\n  WITH CHECK (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS payment_events_select_own_or_admin ON public.payment_events","CREATE POLICY payment_events_select_own_or_admin ON public.payment_events\n  FOR SELECT TO authenticated\n  USING (\n    EXISTS (\n      SELECT 1 FROM public.payments p\n      WHERE p.id = payment_id\n        AND (p.user_id = auth.uid() OR public.is_admin())\n    )\n  )","DROP POLICY IF EXISTS payment_events_insert_own_or_admin ON public.payment_events","CREATE POLICY payment_events_insert_own_or_admin ON public.payment_events\n  FOR INSERT TO authenticated\n  WITH CHECK (\n    EXISTS (\n      SELECT 1 FROM public.payments p\n      WHERE p.id = payment_id\n        AND (p.user_id = auth.uid() OR public.is_admin())\n    )\n  )","GRANT SELECT, INSERT, UPDATE ON public.payments TO authenticated","GRANT SELECT, INSERT ON public.payment_events TO authenticated","-- ---------------------------------------------------------------------------\n-- 5. Extend place_order with payment_method (default cod)\n-- ---------------------------------------------------------------------------\nDROP FUNCTION IF EXISTS public.place_order(uuid, text, uuid, jsonb, text)","CREATE OR REPLACE FUNCTION public.place_order(\n  p_user_id uuid DEFAULT auth.uid(),\n  p_delivery_type text DEFAULT NULL,\n  p_pickup_location_id uuid DEFAULT NULL,\n  p_delivery_address jsonb DEFAULT NULL,\n  p_customer_note text DEFAULT NULL,\n  p_payment_method text DEFAULT 'cod'\n)\nRETURNS uuid\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_order_id uuid;\n  v_subtotal numeric(12,2) := 0;\n  v_delivery_fee numeric(12,2) := 0;\n  v_total numeric(12,2) := 0;\n  v_payment_method text := COALESCE(NULLIF(trim(p_payment_method), ''), 'cod');\n  r RECORD;\nBEGIN\n  IF p_user_id IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n  IF auth.uid() IS DISTINCT FROM p_user_id AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  IF v_payment_method NOT IN ('cod', 'mpesa', 'card', 'paypal', 'bank_transfer') THEN\n    RAISE EXCEPTION 'Invalid payment method: %', v_payment_method;\n  END IF;\n\n  IF p_delivery_type IS NULL OR p_delivery_type NOT IN ('pickup', 'delivery') THEN\n    RAISE EXCEPTION 'Delivery type is required (pickup or delivery)';\n  END IF;\n\n  IF p_delivery_type = 'pickup' THEN\n    IF p_pickup_location_id IS NULL THEN\n      RAISE EXCEPTION 'Pickup location is required';\n    END IF;\n    IF NOT EXISTS (\n      SELECT 1 FROM public.pickup_locations\n      WHERE id = p_pickup_location_id AND is_active = true\n    ) THEN\n      RAISE EXCEPTION 'Invalid or inactive pickup location';\n    END IF;\n  END IF;\n\n  IF p_delivery_type = 'delivery' THEN\n    IF p_delivery_address IS NULL\n       OR NULLIF(trim(p_delivery_address->>'line1'), '') IS NULL\n       OR NULLIF(trim(p_delivery_address->>'city'), '') IS NULL\n       OR NULLIF(trim(p_delivery_address->>'phone'), '') IS NULL THEN\n      RAISE EXCEPTION 'Delivery address (line1, city, phone) is required';\n    END IF;\n    v_delivery_fee := 200;\n  END IF;\n\n  PERFORM 1\n  FROM public.products p\n  JOIN public.cart_items c ON c.product_id = p.id\n  WHERE c.user_id = p_user_id\n  FOR UPDATE OF p;\n\n  FOR r IN\n    SELECT c.product_id, c.quantity, p.stock, p.name, p.is_active\n    FROM public.cart_items c\n    JOIN public.products p ON p.id = c.product_id\n    WHERE c.user_id = p_user_id\n  LOOP\n    IF NOT COALESCE(r.is_active, true) THEN\n      RAISE EXCEPTION 'Product % is no longer available', r.name;\n    END IF;\n    IF r.stock < r.quantity THEN\n      RAISE EXCEPTION 'Insufficient stock for %', r.name;\n    END IF;\n  END LOOP;\n\n  SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)\n  INTO v_subtotal\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  IF v_subtotal = 0 THEN\n    RAISE EXCEPTION 'Cart is empty';\n  END IF;\n\n  v_total := v_subtotal + v_delivery_fee;\n\n  INSERT INTO public.orders (\n    user_id, status, total, payment_status, payment_method,\n    delivery_type, pickup_location_id, delivery_address,\n    delivery_fee, customer_note\n  )\n  VALUES (\n    p_user_id, 'pending', v_total, 'pending', v_payment_method,\n    p_delivery_type, p_pickup_location_id, p_delivery_address,\n    v_delivery_fee, NULLIF(trim(p_customer_note), '')\n  )\n  RETURNING id INTO v_order_id;\n\n  INSERT INTO public.order_items (order_id, product_id, name, price, quantity, image_url)\n  SELECT\n    v_order_id,\n    c.product_id,\n    p.name,\n    COALESCE(p.discount_price, p.price),\n    c.quantity,\n    COALESCE(\n      p.image_url,\n      CASE WHEN jsonb_typeof(p.images) = 'array'\n           THEN p.images->0->>'url'\n           ELSE NULL END\n    )\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  UPDATE public.products p\n  SET stock = p.stock - c.quantity\n  FROM public.cart_items c\n  WHERE c.user_id = p_user_id AND c.product_id = p.id;\n\n  DELETE FROM public.cart_items WHERE user_id = p_user_id;\n\n  PERFORM public.log_order_event(v_order_id, 'order_placed', jsonb_build_object(\n    'delivery_type', p_delivery_type,\n    'delivery_fee', v_delivery_fee,\n    'subtotal', v_subtotal,\n    'total', v_total,\n    'payment_method', v_payment_method\n  ));\n\n  RETURN v_order_id;\nEND;\n$$","REVOKE ALL ON FUNCTION public.place_order(uuid, text, uuid, jsonb, text, text) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.place_order(uuid, text, uuid, jsonb, text, text) TO authenticated","-- ---------------------------------------------------------------------------\n-- 6. create_payment_for_order — owner initiates a payment attempt\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.create_payment_for_order(\n  p_order_id uuid,\n  p_method text DEFAULT 'mpesa',\n  p_provider text DEFAULT 'mock_mpesa',\n  p_phone_number text DEFAULT NULL,\n  p_amount numeric DEFAULT NULL\n)\nRETURNS public.payments\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_order public.orders%ROWTYPE;\n  v_payment public.payments%ROWTYPE;\n  v_amount numeric(12,2);\nBEGIN\n  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Order not found';\n  END IF;\n  IF v_order.user_id IS DISTINCT FROM auth.uid() AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n  IF v_order.status = 'cancelled' THEN\n    RAISE EXCEPTION 'Cannot pay a cancelled order';\n  END IF;\n  IF v_order.payment_status = 'paid' THEN\n    RAISE EXCEPTION 'Order is already paid';\n  END IF;\n\n  v_amount := COALESCE(p_amount, v_order.total);\n  IF v_amount IS NULL OR v_amount <= 0 THEN\n    RAISE EXCEPTION 'Invalid payment amount';\n  END IF;\n\n  INSERT INTO public.payments (\n    order_id, user_id, provider, method, status, amount, currency, phone_number, expires_at\n  )\n  VALUES (\n    p_order_id,\n    v_order.user_id,\n    COALESCE(NULLIF(trim(p_provider), ''), 'mock_mpesa'),\n    COALESCE(NULLIF(trim(p_method), ''), 'mpesa'),\n    'pending',\n    v_amount,\n    'KES',\n    NULLIF(trim(p_phone_number), ''),\n    now() + interval '5 minutes'\n  )\n  RETURNING * INTO v_payment;\n\n  INSERT INTO public.payment_events (payment_id, event_type, payload)\n  VALUES (\n    v_payment.id,\n    'payment_created',\n    jsonb_build_object('method', v_payment.method, 'provider', v_payment.provider, 'amount', v_amount)\n  );\n\n  UPDATE public.orders\n  SET payment_method = v_payment.method,\n      payment_status = 'pending',\n      updated_at = now()\n  WHERE id = p_order_id;\n\n  RETURN v_payment;\nEND;\n$$","REVOKE ALL ON FUNCTION public.create_payment_for_order(uuid, text, text, text, numeric) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.create_payment_for_order(uuid, text, text, text, numeric) TO authenticated","-- ---------------------------------------------------------------------------\n-- 7. mark_payment_initiated — store STK ids after provider call\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.mark_payment_initiated(\n  p_payment_id uuid,\n  p_checkout_request_id text,\n  p_merchant_request_id text DEFAULT NULL,\n  p_raw_response jsonb DEFAULT '{}'::jsonb\n)\nRETURNS public.payments\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_payment public.payments%ROWTYPE;\nBEGIN\n  SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Payment not found';\n  END IF;\n  IF v_payment.user_id IS DISTINCT FROM auth.uid() AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  UPDATE public.payments\n  SET status = 'initiated',\n      checkout_request_id = NULLIF(trim(p_checkout_request_id), ''),\n      merchant_request_id = NULLIF(trim(p_merchant_request_id), ''),\n      raw_response = COALESCE(p_raw_response, '{}'::jsonb),\n      updated_at = now()\n  WHERE id = p_payment_id\n  RETURNING * INTO v_payment;\n\n  INSERT INTO public.payment_events (payment_id, event_type, payload)\n  VALUES (\n    p_payment_id,\n    'stk_initiated',\n    jsonb_build_object(\n      'checkout_request_id', p_checkout_request_id,\n      'merchant_request_id', p_merchant_request_id\n    )\n  );\n\n  RETURN v_payment;\nEND;\n$$","REVOKE ALL ON FUNCTION public.mark_payment_initiated(uuid, text, text, jsonb) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.mark_payment_initiated(uuid, text, text, jsonb) TO authenticated","-- ---------------------------------------------------------------------------\n-- 8. finalize_payment — idempotent callback / poll result applicator\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.finalize_payment(\n  p_payment_id uuid,\n  p_status text,\n  p_receipt_number text DEFAULT NULL,\n  p_transaction_reference text DEFAULT NULL,\n  p_failure_reason text DEFAULT NULL,\n  p_raw_callback jsonb DEFAULT '{}'::jsonb\n)\nRETURNS public.payments\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_payment public.payments%ROWTYPE;\n  v_order public.orders%ROWTYPE;\n  v_status text := lower(trim(p_status));\nBEGIN\n  IF v_status NOT IN ('paid', 'failed', 'cancelled', 'expired', 'processing') THEN\n    RAISE EXCEPTION 'Invalid finalize status: %', p_status;\n  END IF;\n\n  SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Payment not found';\n  END IF;\n\n  -- Idempotent success: already paid with same receipt\n  IF v_payment.status = 'paid' AND v_status = 'paid' THEN\n    INSERT INTO public.payment_events (payment_id, event_type, payload)\n    VALUES (\n      p_payment_id,\n      'duplicate_callback_ignored',\n      COALESCE(p_raw_callback, '{}'::jsonb)\n    );\n    RETURN v_payment;\n  END IF;\n\n  -- Do not regress a paid payment\n  IF v_payment.status = 'paid' AND v_status <> 'paid' THEN\n    INSERT INTO public.payment_events (payment_id, event_type, payload)\n    VALUES (\n      p_payment_id,\n      'stale_callback_ignored',\n      jsonb_build_object('attempted_status', v_status)\n    );\n    RETURN v_payment;\n  END IF;\n\n  UPDATE public.payments\n  SET status = v_status,\n      receipt_number = COALESCE(NULLIF(trim(p_receipt_number), ''), receipt_number),\n      transaction_reference = COALESCE(NULLIF(trim(p_transaction_reference), ''), transaction_reference),\n      failure_reason = CASE\n        WHEN v_status IN ('failed', 'cancelled', 'expired')\n          THEN COALESCE(NULLIF(trim(p_failure_reason), ''), failure_reason)\n        ELSE NULL\n      END,\n      raw_callback = COALESCE(p_raw_callback, '{}'::jsonb),\n      paid_at = CASE WHEN v_status = 'paid' THEN now() ELSE paid_at END,\n      updated_at = now()\n  WHERE id = p_payment_id\n  RETURNING * INTO v_payment;\n\n  INSERT INTO public.payment_events (payment_id, event_type, payload)\n  VALUES (\n    p_payment_id,\n    'payment_' || v_status,\n    COALESCE(p_raw_callback, '{}'::jsonb)\n  );\n\n  SELECT * INTO v_order FROM public.orders WHERE id = v_payment.order_id FOR UPDATE;\n\n  IF v_status = 'paid' THEN\n    UPDATE public.orders\n    SET payment_status = 'paid',\n        mpesa_receipt_number = COALESCE(v_payment.receipt_number, mpesa_receipt_number),\n        payment_method = COALESCE(v_payment.method, payment_method),\n        updated_at = now()\n    WHERE id = v_payment.order_id;\n\n    PERFORM public.log_order_event(v_payment.order_id, 'payment_status_changed', jsonb_build_object(\n      'from', v_order.payment_status,\n      'to', 'paid',\n      'payment_id', p_payment_id,\n      'receipt_number', v_payment.receipt_number\n    ));\n  ELSIF v_status IN ('failed', 'cancelled', 'expired') THEN\n    -- Keep order payment_status failed only if not already paid\n    IF v_order.payment_status IS DISTINCT FROM 'paid' THEN\n      UPDATE public.orders\n      SET payment_status = 'failed',\n          updated_at = now()\n      WHERE id = v_payment.order_id;\n\n      PERFORM public.log_order_event(v_payment.order_id, 'payment_status_changed', jsonb_build_object(\n        'from', v_order.payment_status,\n        'to', 'failed',\n        'payment_id', p_payment_id,\n        'reason', v_payment.failure_reason\n      ));\n    END IF;\n  END IF;\n\n  RETURN v_payment;\nEND;\n$$","REVOKE ALL ON FUNCTION public.finalize_payment(uuid, text, text, text, text, jsonb) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.finalize_payment(uuid, text, text, text, text, jsonb) TO authenticated"}	payments
017	{"-- 017_notifications.sql\n-- Workstream 7 — Notifications & customer communications foundation\n--\n-- In-app inbox, delivery ledger, templates, preferences, event audit.\n-- Mock email/SMS providers are used in the app; live Resend / Africa's Talking\n-- / Twilio swap via provider factory (no secrets in this migration).\n-- Idempotent where practical.\n\n-- ---------------------------------------------------------------------------\n-- 1. Extend customer_preferences (backwards-compatible flags)\n-- ---------------------------------------------------------------------------\nALTER TABLE public.customer_preferences\n  ADD COLUMN IF NOT EXISTS email_notifications boolean NOT NULL DEFAULT true","ALTER TABLE public.customer_preferences\n  ADD COLUMN IF NOT EXISTS order_updates boolean NOT NULL DEFAULT true","ALTER TABLE public.customer_preferences\n  ADD COLUMN IF NOT EXISTS payment_updates boolean NOT NULL DEFAULT true","COMMENT ON COLUMN public.customer_preferences.email_notifications IS\n  'WS7 — allow transactional email (orders/payments/account).'","COMMENT ON COLUMN public.customer_preferences.order_updates IS\n  'WS7 — order lifecycle notifications.'","COMMENT ON COLUMN public.customer_preferences.payment_updates IS\n  'WS7 — payment lifecycle notifications.'","-- ---------------------------------------------------------------------------\n-- 2. notification_templates\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.notification_templates (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  code text NOT NULL,\n  channel text NOT NULL DEFAULT 'in_app',\n  subject text,\n  body text NOT NULL,\n  description text,\n  is_active boolean NOT NULL DEFAULT true,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT notification_templates_channel_check\n    CHECK (channel IN ('in_app', 'email', 'sms', 'push')),\n  CONSTRAINT notification_templates_code_channel_unique UNIQUE (code, channel)\n)","CREATE INDEX IF NOT EXISTS idx_notification_templates_code\n  ON public.notification_templates (code)","DROP TRIGGER IF EXISTS notification_templates_set_updated_at ON public.notification_templates","CREATE TRIGGER notification_templates_set_updated_at\n  BEFORE UPDATE ON public.notification_templates\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","-- ---------------------------------------------------------------------------\n-- 3. notification_preferences (per-user channel/category toggles)\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.notification_preferences (\n  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,\n  email_enabled boolean NOT NULL DEFAULT true,\n  sms_enabled boolean NOT NULL DEFAULT false,\n  in_app_enabled boolean NOT NULL DEFAULT true,\n  push_enabled boolean NOT NULL DEFAULT false,\n  marketing_emails boolean NOT NULL DEFAULT false,\n  order_updates boolean NOT NULL DEFAULT true,\n  payment_updates boolean NOT NULL DEFAULT true,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now()\n)","DROP TRIGGER IF EXISTS notification_preferences_set_updated_at ON public.notification_preferences","CREATE TRIGGER notification_preferences_set_updated_at\n  BEFORE UPDATE ON public.notification_preferences\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","-- ---------------------------------------------------------------------------\n-- 4. notifications (in-app inbox)\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.notifications (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,\n  event_type text NOT NULL,\n  channel text NOT NULL DEFAULT 'in_app',\n  title text NOT NULL,\n  body text NOT NULL,\n  link text,\n  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,\n  status text NOT NULL DEFAULT 'unread',\n  audience text NOT NULL DEFAULT 'customer',\n  read_at timestamptz,\n  archived_at timestamptz,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT notifications_channel_check\n    CHECK (channel IN ('in_app', 'email', 'sms', 'push')),\n  CONSTRAINT notifications_status_check\n    CHECK (status IN ('unread', 'read', 'archived')),\n  CONSTRAINT notifications_audience_check\n    CHECK (audience IN ('customer', 'admin', 'system'))\n)","CREATE INDEX IF NOT EXISTS idx_notifications_user_created\n  ON public.notifications (user_id, created_at DESC)","CREATE INDEX IF NOT EXISTS idx_notifications_user_status\n  ON public.notifications (user_id, status)","CREATE INDEX IF NOT EXISTS idx_notifications_event_type\n  ON public.notifications (event_type)","CREATE INDEX IF NOT EXISTS idx_notifications_audience_created\n  ON public.notifications (audience, created_at DESC)\n  WHERE audience = 'admin'","DROP TRIGGER IF EXISTS notifications_set_updated_at ON public.notifications","CREATE TRIGGER notifications_set_updated_at\n  BEFORE UPDATE ON public.notifications\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","-- ---------------------------------------------------------------------------\n-- 5. notification_deliveries (per-channel send attempts)\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.notification_deliveries (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  notification_id uuid REFERENCES public.notifications(id) ON DELETE SET NULL,\n  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,\n  event_type text NOT NULL,\n  channel text NOT NULL,\n  provider text NOT NULL DEFAULT 'mock',\n  status text NOT NULL DEFAULT 'pending',\n  retry_count integer NOT NULL DEFAULT 0,\n  max_retries integer NOT NULL DEFAULT 3,\n  external_id text,\n  error_message text,\n  payload jsonb NOT NULL DEFAULT '{}'::jsonb,\n  response jsonb NOT NULL DEFAULT '{}'::jsonb,\n  scheduled_at timestamptz,\n  sent_at timestamptz,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT notification_deliveries_channel_check\n    CHECK (channel IN ('in_app', 'email', 'sms', 'push')),\n  CONSTRAINT notification_deliveries_status_check\n    CHECK (status IN (\n      'pending', 'queued', 'sending', 'sent', 'delivered',\n      'failed', 'skipped', 'cancelled'\n    )),\n  CONSTRAINT notification_deliveries_retry_nonneg CHECK (retry_count >= 0)\n)","CREATE INDEX IF NOT EXISTS idx_notification_deliveries_user_created\n  ON public.notification_deliveries (user_id, created_at DESC)","CREATE INDEX IF NOT EXISTS idx_notification_deliveries_status\n  ON public.notification_deliveries (status)","CREATE INDEX IF NOT EXISTS idx_notification_deliveries_notification_id\n  ON public.notification_deliveries (notification_id)","DROP TRIGGER IF EXISTS notification_deliveries_set_updated_at ON public.notification_deliveries","CREATE TRIGGER notification_deliveries_set_updated_at\n  BEFORE UPDATE ON public.notification_deliveries\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","-- ---------------------------------------------------------------------------\n-- 6. notification_events (emit / dispatch audit)\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.notification_events (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  event_type text NOT NULL,\n  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,\n  payload jsonb NOT NULL DEFAULT '{}'::jsonb,\n  result jsonb NOT NULL DEFAULT '{}'::jsonb,\n  created_at timestamptz NOT NULL DEFAULT now()\n)","CREATE INDEX IF NOT EXISTS idx_notification_events_type_created\n  ON public.notification_events (event_type, created_at DESC)","CREATE INDEX IF NOT EXISTS idx_notification_events_user_created\n  ON public.notification_events (user_id, created_at DESC)","-- ---------------------------------------------------------------------------\n-- 7. RLS\n-- ---------------------------------------------------------------------------\nALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY","ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY","ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY","ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY","ALTER TABLE public.notification_events ENABLE ROW LEVEL SECURITY","-- Templates: authenticated read active; admin write\nDROP POLICY IF EXISTS notification_templates_select_authenticated ON public.notification_templates","CREATE POLICY notification_templates_select_authenticated ON public.notification_templates\n  FOR SELECT TO authenticated\n  USING (is_active = true OR public.is_admin())","DROP POLICY IF EXISTS notification_templates_admin_all ON public.notification_templates","CREATE POLICY notification_templates_admin_all ON public.notification_templates\n  FOR ALL TO authenticated\n  USING (public.is_admin())\n  WITH CHECK (public.is_admin())","-- Preferences: owner only\nDROP POLICY IF EXISTS notification_preferences_select_own ON public.notification_preferences","CREATE POLICY notification_preferences_select_own ON public.notification_preferences\n  FOR SELECT TO authenticated\n  USING (user_id = auth.uid())","DROP POLICY IF EXISTS notification_preferences_insert_own ON public.notification_preferences","CREATE POLICY notification_preferences_insert_own ON public.notification_preferences\n  FOR INSERT TO authenticated\n  WITH CHECK (user_id = auth.uid())","DROP POLICY IF EXISTS notification_preferences_update_own ON public.notification_preferences","CREATE POLICY notification_preferences_update_own ON public.notification_preferences\n  FOR UPDATE TO authenticated\n  USING (user_id = auth.uid())\n  WITH CHECK (user_id = auth.uid())","-- Inbox: owner or admin\nDROP POLICY IF EXISTS notifications_select_own_or_admin ON public.notifications","CREATE POLICY notifications_select_own_or_admin ON public.notifications\n  FOR SELECT TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS notifications_insert_own_or_admin ON public.notifications","CREATE POLICY notifications_insert_own_or_admin ON public.notifications\n  FOR INSERT TO authenticated\n  WITH CHECK (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS notifications_update_own_or_admin ON public.notifications","CREATE POLICY notifications_update_own_or_admin ON public.notifications\n  FOR UPDATE TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())\n  WITH CHECK (user_id = auth.uid() OR public.is_admin())","-- Deliveries: owner or admin\nDROP POLICY IF EXISTS notification_deliveries_select_own_or_admin ON public.notification_deliveries","CREATE POLICY notification_deliveries_select_own_or_admin ON public.notification_deliveries\n  FOR SELECT TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS notification_deliveries_insert_own_or_admin ON public.notification_deliveries","CREATE POLICY notification_deliveries_insert_own_or_admin ON public.notification_deliveries\n  FOR INSERT TO authenticated\n  WITH CHECK (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS notification_deliveries_update_own_or_admin ON public.notification_deliveries","CREATE POLICY notification_deliveries_update_own_or_admin ON public.notification_deliveries\n  FOR UPDATE TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())\n  WITH CHECK (user_id = auth.uid() OR public.is_admin())","-- Events: own or admin read; insert own or admin\nDROP POLICY IF EXISTS notification_events_select_own_or_admin ON public.notification_events","CREATE POLICY notification_events_select_own_or_admin ON public.notification_events\n  FOR SELECT TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin() OR user_id IS NULL)","DROP POLICY IF EXISTS notification_events_insert_authenticated ON public.notification_events","CREATE POLICY notification_events_insert_authenticated ON public.notification_events\n  FOR INSERT TO authenticated\n  WITH CHECK (user_id = auth.uid() OR public.is_admin() OR user_id IS NULL)","-- ---------------------------------------------------------------------------\n-- 8. Helpers — preferences bootstrap + admin fan-out + mark read\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.ensure_notification_preferences(p_user_id uuid DEFAULT auth.uid())\nRETURNS public.notification_preferences\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_row public.notification_preferences;\n  v_cp public.customer_preferences;\nBEGIN\n  IF p_user_id IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n  IF p_user_id <> auth.uid() AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Forbidden';\n  END IF;\n\n  SELECT * INTO v_row FROM public.notification_preferences WHERE user_id = p_user_id;\n  IF FOUND THEN\n    RETURN v_row;\n  END IF;\n\n  SELECT * INTO v_cp FROM public.customer_preferences WHERE user_id = p_user_id;\n\n  INSERT INTO public.notification_preferences (\n    user_id, email_enabled, sms_enabled, in_app_enabled, push_enabled,\n    marketing_emails, order_updates, payment_updates\n  ) VALUES (\n    p_user_id,\n    COALESCE(v_cp.email_notifications, true),\n    COALESCE(v_cp.sms_notifications, false),\n    true,\n    false,\n    COALESCE(v_cp.marketing_emails, false),\n    COALESCE(v_cp.order_updates, true),\n    COALESCE(v_cp.payment_updates, true)\n  )\n  RETURNING * INTO v_row;\n\n  RETURN v_row;\nEND;\n$$","REVOKE ALL ON FUNCTION public.ensure_notification_preferences(uuid) FROM PUBLIC","GRANT EXECUTE ON FUNCTION public.ensure_notification_preferences(uuid) TO authenticated","CREATE OR REPLACE FUNCTION public.notify_admin_users(\n  p_event_type text,\n  p_title text,\n  p_body text,\n  p_link text DEFAULT NULL,\n  p_metadata jsonb DEFAULT '{}'::jsonb\n)\nRETURNS integer\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_count integer := 0;\n  v_admin record;\nBEGIN\n  FOR v_admin IN\n    SELECT id FROM public.profiles WHERE role = 'admin'\n  LOOP\n    INSERT INTO public.notifications (\n      user_id, event_type, channel, title, body, link, metadata, audience, status\n    ) VALUES (\n      v_admin.id, p_event_type, 'in_app', p_title, p_body, p_link,\n      COALESCE(p_metadata, '{}'::jsonb), 'admin', 'unread'\n    );\n    v_count := v_count + 1;\n  END LOOP;\n  RETURN v_count;\nEND;\n$$","REVOKE ALL ON FUNCTION public.notify_admin_users(text, text, text, text, jsonb) FROM PUBLIC","GRANT EXECUTE ON FUNCTION public.notify_admin_users(text, text, text, text, jsonb) TO authenticated","CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)\nRETURNS public.notifications\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_row public.notifications;\nBEGIN\n  UPDATE public.notifications\n  SET status = 'read',\n      read_at = COALESCE(read_at, now()),\n      updated_at = now()\n  WHERE id = p_notification_id\n    AND (user_id = auth.uid() OR public.is_admin())\n    AND status <> 'archived'\n  RETURNING * INTO v_row;\n\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Notification not found';\n  END IF;\n  RETURN v_row;\nEND;\n$$","REVOKE ALL ON FUNCTION public.mark_notification_read(uuid) FROM PUBLIC","GRANT EXECUTE ON FUNCTION public.mark_notification_read(uuid) TO authenticated","CREATE OR REPLACE FUNCTION public.mark_all_notifications_read(p_audience text DEFAULT NULL)\nRETURNS integer\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_count integer;\nBEGIN\n  UPDATE public.notifications\n  SET status = 'read',\n      read_at = COALESCE(read_at, now()),\n      updated_at = now()\n  WHERE user_id = auth.uid()\n    AND status = 'unread'\n    AND (p_audience IS NULL OR audience = p_audience);\n\n  GET DIAGNOSTICS v_count = ROW_COUNT;\n  RETURN v_count;\nEND;\n$$","REVOKE ALL ON FUNCTION public.mark_all_notifications_read(text) FROM PUBLIC","GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read(text) TO authenticated","CREATE OR REPLACE FUNCTION public.archive_notification(p_notification_id uuid)\nRETURNS public.notifications\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_row public.notifications;\nBEGIN\n  UPDATE public.notifications\n  SET status = 'archived',\n      archived_at = now(),\n      read_at = COALESCE(read_at, now()),\n      updated_at = now()\n  WHERE id = p_notification_id\n    AND (user_id = auth.uid() OR public.is_admin())\n  RETURNING * INTO v_row;\n\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Notification not found';\n  END IF;\n  RETURN v_row;\nEND;\n$$","REVOKE ALL ON FUNCTION public.archive_notification(uuid) FROM PUBLIC","GRANT EXECUTE ON FUNCTION public.archive_notification(uuid) TO authenticated","-- ---------------------------------------------------------------------------\n-- 9. Seed templates ({{variable}} placeholders)\n-- ---------------------------------------------------------------------------\nINSERT INTO public.notification_templates (code, channel, subject, body, description)\nVALUES\n  ('account_registration', 'in_app', NULL,\n   'Welcome to Babees Place, {{name}}! Your account is ready.',\n   'Account registration confirmation'),\n  ('welcome', 'email', 'Welcome to Babees Place',\n   'Hi {{name}},\\\\n\\\\nWelcome to Babees Place. Start exploring our collection today.',\n   'Welcome email'),\n  ('password_reset', 'email', 'Reset your Babees Place password',\n   'Hi {{name}},\\\\n\\\\nUse this link to reset your password: {{reset_link}}\\\\n\\\\nIf you did not request this, ignore this email.',\n   'Password reset'),\n  ('email_verification', 'email', 'Verify your Babees Place email',\n   'Hi {{name}},\\\\n\\\\nPlease verify your email: {{verify_link}}',\n   'Email verification'),\n  ('order_created', 'in_app', NULL,\n   'Order {{order_number}} was placed successfully. Total: {{amount}} {{currency}}.',\n   'Customer order created'),\n  ('order_confirmed', 'in_app', NULL,\n   'Order {{order_number}} has been confirmed and is being prepared.',\n   'Order confirmed'),\n  ('order_cancelled', 'in_app', NULL,\n   'Order {{order_number}} has been cancelled.',\n   'Order cancelled'),\n  ('order_ready_for_pickup', 'in_app', NULL,\n   'Order {{order_number}} is ready for pickup at {{location}}.',\n   'Ready for pickup'),\n  ('out_for_delivery', 'in_app', NULL,\n   'Order {{order_number}} is out for delivery.',\n   'Out for delivery'),\n  ('delivered', 'in_app', NULL,\n   'Order {{order_number}} has been delivered. Enjoy!',\n   'Delivered'),\n  ('payment_initiated', 'in_app', NULL,\n   'Payment of {{amount}} {{currency}} initiated for order {{order_number}}. Check your phone for M-Pesa.',\n   'Payment initiated'),\n  ('payment_successful', 'in_app', NULL,\n   'Payment received for order {{order_number}}. Receipt: {{receipt_number}}.',\n   'Payment successful'),\n  ('payment_failed', 'in_app', NULL,\n   'Payment for order {{order_number}} failed. You can retry from your order page.',\n   'Payment failed'),\n  ('payment_retry', 'in_app', NULL,\n   'A new payment attempt was started for order {{order_number}}.',\n   'Payment retry'),\n  ('admin_new_order', 'in_app', NULL,\n   'New order {{order_number}} — {{amount}} {{currency}} ({{payment_method}}).',\n   'Admin new order'),\n  ('admin_low_inventory', 'in_app', NULL,\n   'Low stock: {{product_name}} has {{stock}} units left.',\n   'Admin low inventory'),\n  ('admin_payment_received', 'in_app', NULL,\n   'Payment received for order {{order_number}}. Receipt: {{receipt_number}}.',\n   'Admin payment received'),\n  ('order_created', 'email', 'Order confirmation — {{order_number}}',\n   'Hi {{name}},\\\\n\\\\nThanks for your order {{order_number}}. Total: {{amount}} {{currency}}.',\n   'Order confirmation email'),\n  ('payment_successful', 'email', 'Payment received — {{order_number}}',\n   'Hi {{name}},\\\\n\\\\nWe received your payment for {{order_number}}. Receipt: {{receipt_number}}.',\n   'Payment success email'),\n  ('payment_failed', 'email', 'Payment failed — {{order_number}}',\n   'Hi {{name}},\\\\n\\\\nPayment for {{order_number}} did not complete. Please retry from your orders.',\n   'Payment failed email'),\n  ('order_ready_for_pickup', 'sms', NULL,\n   'Babees Place: Order {{order_number}} is ready for pickup.',\n   'Pickup SMS'),\n  ('payment_successful', 'sms', NULL,\n   'Babees Place: Payment confirmed for {{order_number}}. Receipt {{receipt_number}}.',\n   'Payment SMS')\nON CONFLICT (code, channel) DO NOTHING"}	notifications
018	{"-- 018_promotions_loyalty.sql\n-- Workstream 8 — Promotions, loyalty, coupons, referrals, gift cards\n--\n-- Extends place_order with optional reward params (defaults preserve COD path).\n-- Idempotent where practical.\n\n-- ---------------------------------------------------------------------------\n-- 1. Order reward columns (backwards compatible)\n-- ---------------------------------------------------------------------------\nALTER TABLE public.orders\n  ADD COLUMN IF NOT EXISTS discount_amount numeric(12,2) NOT NULL DEFAULT 0","ALTER TABLE public.orders\n  ADD COLUMN IF NOT EXISTS coupon_code text","ALTER TABLE public.orders\n  ADD COLUMN IF NOT EXISTS loyalty_points_redeemed integer NOT NULL DEFAULT 0","ALTER TABLE public.orders\n  ADD COLUMN IF NOT EXISTS gift_card_amount numeric(12,2) NOT NULL DEFAULT 0","ALTER TABLE public.orders\n  ADD COLUMN IF NOT EXISTS free_delivery boolean NOT NULL DEFAULT false","ALTER TABLE public.orders\n  ADD COLUMN IF NOT EXISTS promotions_applied jsonb NOT NULL DEFAULT '[]'::jsonb","ALTER TABLE public.orders\n  ADD COLUMN IF NOT EXISTS referral_code text","COMMENT ON COLUMN public.orders.discount_amount IS 'WS8 — merchandise discount (excl. gift card).'","COMMENT ON COLUMN public.orders.promotions_applied IS 'WS8 — snapshot of applied promo/coupon ids.'","-- ---------------------------------------------------------------------------\n-- 2. promotions\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.promotions (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  code text,\n  name text NOT NULL,\n  description text,\n  promo_type text NOT NULL,\n  status text NOT NULL DEFAULT 'active',\n  priority integer NOT NULL DEFAULT 100,\n  stackable boolean NOT NULL DEFAULT false,\n  percent_off numeric(5,2),\n  amount_off numeric(12,2),\n  buy_quantity integer,\n  get_quantity integer,\n  category_id uuid REFERENCES public.categories(id) ON DELETE SET NULL,\n  product_id uuid,\n  min_order_amount numeric(12,2) NOT NULL DEFAULT 0,\n  max_discount_amount numeric(12,2),\n  usage_limit integer,\n  usage_count integer NOT NULL DEFAULT 0,\n  per_user_limit integer,\n  starts_at timestamptz,\n  ends_at timestamptz,\n  eligibility jsonb NOT NULL DEFAULT '{}'::jsonb,\n  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT promotions_type_check CHECK (promo_type IN (\n    'percentage', 'fixed', 'free_delivery', 'buy_x_get_y',\n    'category', 'product', 'storewide'\n  )),\n  CONSTRAINT promotions_status_check CHECK (status IN ('draft', 'active', 'paused', 'expired'))\n)","CREATE UNIQUE INDEX IF NOT EXISTS idx_promotions_code_unique\n  ON public.promotions (lower(code)) WHERE code IS NOT NULL","CREATE INDEX IF NOT EXISTS idx_promotions_status_priority\n  ON public.promotions (status, priority DESC)","CREATE INDEX IF NOT EXISTS idx_promotions_dates\n  ON public.promotions (starts_at, ends_at)","DROP TRIGGER IF EXISTS promotions_set_updated_at ON public.promotions","CREATE TRIGGER promotions_set_updated_at\n  BEFORE UPDATE ON public.promotions\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","-- ---------------------------------------------------------------------------\n-- 3. promotion_rules (extra targeting / conditions)\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.promotion_rules (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  promotion_id uuid NOT NULL REFERENCES public.promotions(id) ON DELETE CASCADE,\n  rule_type text NOT NULL,\n  rule_value jsonb NOT NULL DEFAULT '{}'::jsonb,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT promotion_rules_type_check CHECK (rule_type IN (\n    'min_quantity', 'max_uses_per_day', 'customer_segment', 'first_order_only', 'exclude_sale_items'\n  ))\n)","CREATE INDEX IF NOT EXISTS idx_promotion_rules_promotion_id\n  ON public.promotion_rules (promotion_id)","-- ---------------------------------------------------------------------------\n-- 4. coupons\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.coupons (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  code text NOT NULL,\n  name text NOT NULL,\n  description text,\n  discount_type text NOT NULL,\n  percent_off numeric(5,2),\n  amount_off numeric(12,2),\n  free_delivery boolean NOT NULL DEFAULT false,\n  min_order_amount numeric(12,2) NOT NULL DEFAULT 0,\n  max_discount_amount numeric(12,2),\n  usage_limit integer,\n  usage_count integer NOT NULL DEFAULT 0,\n  per_user_limit integer DEFAULT 1,\n  is_one_time boolean NOT NULL DEFAULT false,\n  is_active boolean NOT NULL DEFAULT true,\n  starts_at timestamptz,\n  ends_at timestamptz,\n  promotion_id uuid REFERENCES public.promotions(id) ON DELETE SET NULL,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT coupons_discount_type_check CHECK (discount_type IN (\n    'percentage', 'fixed', 'free_delivery'\n  )),\n  CONSTRAINT coupons_code_unique UNIQUE (code)\n)","CREATE INDEX IF NOT EXISTS idx_coupons_active ON public.coupons (is_active, starts_at, ends_at)","DROP TRIGGER IF EXISTS coupons_set_updated_at ON public.coupons","CREATE TRIGGER coupons_set_updated_at\n  BEFORE UPDATE ON public.coupons\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","CREATE TABLE IF NOT EXISTS public.coupon_redemptions (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  coupon_id uuid NOT NULL REFERENCES public.coupons(id) ON DELETE CASCADE,\n  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,\n  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,\n  discount_amount numeric(12,2) NOT NULL DEFAULT 0,\n  created_at timestamptz NOT NULL DEFAULT now()\n)","CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_coupon_user\n  ON public.coupon_redemptions (coupon_id, user_id)","CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_order\n  ON public.coupon_redemptions (order_id)","-- ---------------------------------------------------------------------------\n-- 5. loyalty\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.loyalty_accounts (\n  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,\n  points_balance integer NOT NULL DEFAULT 0,\n  lifetime_earned integer NOT NULL DEFAULT 0,\n  lifetime_redeemed integer NOT NULL DEFAULT 0,\n  referral_code text NOT NULL,\n  tier text NOT NULL DEFAULT 'member',\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT loyalty_accounts_balance_nonneg CHECK (points_balance >= 0),\n  CONSTRAINT loyalty_accounts_referral_code_unique UNIQUE (referral_code)\n)","DROP TRIGGER IF EXISTS loyalty_accounts_set_updated_at ON public.loyalty_accounts","CREATE TRIGGER loyalty_accounts_set_updated_at\n  BEFORE UPDATE ON public.loyalty_accounts\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","CREATE TABLE IF NOT EXISTS public.loyalty_transactions (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,\n  tx_type text NOT NULL,\n  points integer NOT NULL,\n  balance_after integer NOT NULL,\n  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,\n  description text,\n  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT loyalty_transactions_type_check CHECK (tx_type IN (\n    'earn_purchase', 'earn_promotion', 'earn_referral', 'earn_bonus',\n    'redeem_discount', 'redeem_delivery', 'redeem_product', 'adjust', 'expire'\n  ))\n)","CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_user_created\n  ON public.loyalty_transactions (user_id, created_at DESC)","CREATE TABLE IF NOT EXISTS public.loyalty_rules (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  code text NOT NULL UNIQUE,\n  name text NOT NULL,\n  is_active boolean NOT NULL DEFAULT true,\n  earn_points_per_currency numeric(12,4) NOT NULL DEFAULT 0.01,\n  redeem_points_per_currency numeric(12,4) NOT NULL DEFAULT 10,\n  free_delivery_points integer NOT NULL DEFAULT 500,\n  min_redeem_points integer NOT NULL DEFAULT 100,\n  max_redeem_percent numeric(5,2) NOT NULL DEFAULT 50,\n  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now()\n)","DROP TRIGGER IF EXISTS loyalty_rules_set_updated_at ON public.loyalty_rules","CREATE TRIGGER loyalty_rules_set_updated_at\n  BEFORE UPDATE ON public.loyalty_rules\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","-- ---------------------------------------------------------------------------\n-- 6. gift cards\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.gift_cards (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  code text NOT NULL UNIQUE,\n  initial_balance numeric(12,2) NOT NULL,\n  balance numeric(12,2) NOT NULL,\n  currency text NOT NULL DEFAULT 'KES',\n  status text NOT NULL DEFAULT 'active',\n  purchased_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,\n  recipient_email text,\n  expires_at timestamptz,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT gift_cards_balance_nonneg CHECK (balance >= 0),\n  CONSTRAINT gift_cards_status_check CHECK (status IN ('active', 'depleted', 'expired', 'disabled'))\n)","CREATE INDEX IF NOT EXISTS idx_gift_cards_status ON public.gift_cards (status)","DROP TRIGGER IF EXISTS gift_cards_set_updated_at ON public.gift_cards","CREATE TRIGGER gift_cards_set_updated_at\n  BEFORE UPDATE ON public.gift_cards\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","CREATE TABLE IF NOT EXISTS public.gift_card_transactions (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  gift_card_id uuid NOT NULL REFERENCES public.gift_cards(id) ON DELETE CASCADE,\n  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,\n  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,\n  tx_type text NOT NULL,\n  amount numeric(12,2) NOT NULL,\n  balance_after numeric(12,2) NOT NULL,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT gift_card_transactions_type_check CHECK (tx_type IN (\n    'issue', 'redeem', 'refund', 'adjust', 'expire'\n  ))\n)","CREATE INDEX IF NOT EXISTS idx_gift_card_transactions_card\n  ON public.gift_card_transactions (gift_card_id, created_at DESC)","-- ---------------------------------------------------------------------------\n-- 7. referrals\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.referrals (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  referrer_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,\n  referred_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,\n  referral_code text NOT NULL,\n  status text NOT NULL DEFAULT 'pending',\n  reward_points integer NOT NULL DEFAULT 0,\n  referred_reward_points integer NOT NULL DEFAULT 0,\n  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,\n  rewarded_at timestamptz,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  updated_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT referrals_status_check CHECK (status IN (\n    'pending', 'signed_up', 'qualified', 'rewarded', 'cancelled'\n  ))\n)","CREATE UNIQUE INDEX IF NOT EXISTS idx_referrals_referred_user\n  ON public.referrals (referred_user_id) WHERE referred_user_id IS NOT NULL","CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON public.referrals (referrer_user_id)","CREATE INDEX IF NOT EXISTS idx_referrals_code ON public.referrals (referral_code)","DROP TRIGGER IF EXISTS referrals_set_updated_at ON public.referrals","CREATE TRIGGER referrals_set_updated_at\n  BEFORE UPDATE ON public.referrals\n  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()","-- ---------------------------------------------------------------------------\n-- 8. reward_events (audit)\n-- ---------------------------------------------------------------------------\nCREATE TABLE IF NOT EXISTS public.reward_events (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,\n  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,\n  event_type text NOT NULL,\n  payload jsonb NOT NULL DEFAULT '{}'::jsonb,\n  created_at timestamptz NOT NULL DEFAULT now()\n)","CREATE INDEX IF NOT EXISTS idx_reward_events_user_created\n  ON public.reward_events (user_id, created_at DESC)","-- ---------------------------------------------------------------------------\n-- 9. RLS\n-- ---------------------------------------------------------------------------\nALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY","ALTER TABLE public.promotion_rules ENABLE ROW LEVEL SECURITY","ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY","ALTER TABLE public.coupon_redemptions ENABLE ROW LEVEL SECURITY","ALTER TABLE public.loyalty_accounts ENABLE ROW LEVEL SECURITY","ALTER TABLE public.loyalty_transactions ENABLE ROW LEVEL SECURITY","ALTER TABLE public.loyalty_rules ENABLE ROW LEVEL SECURITY","ALTER TABLE public.gift_cards ENABLE ROW LEVEL SECURITY","ALTER TABLE public.gift_card_transactions ENABLE ROW LEVEL SECURITY","ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY","ALTER TABLE public.reward_events ENABLE ROW LEVEL SECURITY","-- Promotions: public read active; admin write\nDROP POLICY IF EXISTS promotions_select_active_or_admin ON public.promotions","CREATE POLICY promotions_select_active_or_admin ON public.promotions\n  FOR SELECT TO authenticated\n  USING (status = 'active' OR public.is_admin())","DROP POLICY IF EXISTS promotions_admin_all ON public.promotions","CREATE POLICY promotions_admin_all ON public.promotions\n  FOR ALL TO authenticated\n  USING (public.is_admin()) WITH CHECK (public.is_admin())","DROP POLICY IF EXISTS promotion_rules_select ON public.promotion_rules","CREATE POLICY promotion_rules_select ON public.promotion_rules\n  FOR SELECT TO authenticated USING (true)","DROP POLICY IF EXISTS promotion_rules_admin_all ON public.promotion_rules","CREATE POLICY promotion_rules_admin_all ON public.promotion_rules\n  FOR ALL TO authenticated\n  USING (public.is_admin()) WITH CHECK (public.is_admin())","DROP POLICY IF EXISTS coupons_select_active_or_admin ON public.coupons","CREATE POLICY coupons_select_active_or_admin ON public.coupons\n  FOR SELECT TO authenticated\n  USING (is_active = true OR public.is_admin())","DROP POLICY IF EXISTS coupons_admin_all ON public.coupons","CREATE POLICY coupons_admin_all ON public.coupons\n  FOR ALL TO authenticated\n  USING (public.is_admin()) WITH CHECK (public.is_admin())","DROP POLICY IF EXISTS coupon_redemptions_select_own_or_admin ON public.coupon_redemptions","CREATE POLICY coupon_redemptions_select_own_or_admin ON public.coupon_redemptions\n  FOR SELECT TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS coupon_redemptions_insert_own ON public.coupon_redemptions","CREATE POLICY coupon_redemptions_insert_own ON public.coupon_redemptions\n  FOR INSERT TO authenticated\n  WITH CHECK (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS loyalty_accounts_select_own_or_admin ON public.loyalty_accounts","CREATE POLICY loyalty_accounts_select_own_or_admin ON public.loyalty_accounts\n  FOR SELECT TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS loyalty_accounts_update_own_or_admin ON public.loyalty_accounts","CREATE POLICY loyalty_accounts_update_own_or_admin ON public.loyalty_accounts\n  FOR UPDATE TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())\n  WITH CHECK (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS loyalty_accounts_insert_own ON public.loyalty_accounts","CREATE POLICY loyalty_accounts_insert_own ON public.loyalty_accounts\n  FOR INSERT TO authenticated\n  WITH CHECK (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS loyalty_transactions_select_own_or_admin ON public.loyalty_transactions","CREATE POLICY loyalty_transactions_select_own_or_admin ON public.loyalty_transactions\n  FOR SELECT TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS loyalty_rules_select ON public.loyalty_rules","CREATE POLICY loyalty_rules_select ON public.loyalty_rules\n  FOR SELECT TO authenticated USING (is_active = true OR public.is_admin())","DROP POLICY IF EXISTS loyalty_rules_admin_all ON public.loyalty_rules","CREATE POLICY loyalty_rules_admin_all ON public.loyalty_rules\n  FOR ALL TO authenticated\n  USING (public.is_admin()) WITH CHECK (public.is_admin())","-- Gift cards: lookup by code via RPC; owners/admins see own purchases\nDROP POLICY IF EXISTS gift_cards_select_own_or_admin ON public.gift_cards","CREATE POLICY gift_cards_select_own_or_admin ON public.gift_cards\n  FOR SELECT TO authenticated\n  USING (purchased_by = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS gift_cards_admin_all ON public.gift_cards","CREATE POLICY gift_cards_admin_all ON public.gift_cards\n  FOR ALL TO authenticated\n  USING (public.is_admin()) WITH CHECK (public.is_admin())","DROP POLICY IF EXISTS gift_card_transactions_select_own_or_admin ON public.gift_card_transactions","CREATE POLICY gift_card_transactions_select_own_or_admin ON public.gift_card_transactions\n  FOR SELECT TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS referrals_select_own_or_admin ON public.referrals","CREATE POLICY referrals_select_own_or_admin ON public.referrals\n  FOR SELECT TO authenticated\n  USING (\n    referrer_user_id = auth.uid()\n    OR referred_user_id = auth.uid()\n    OR public.is_admin()\n  )","DROP POLICY IF EXISTS referrals_insert_own ON public.referrals","CREATE POLICY referrals_insert_own ON public.referrals\n  FOR INSERT TO authenticated\n  WITH CHECK (referrer_user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS reward_events_select_own_or_admin ON public.reward_events","CREATE POLICY reward_events_select_own_or_admin ON public.reward_events\n  FOR SELECT TO authenticated\n  USING (user_id = auth.uid() OR public.is_admin())","DROP POLICY IF EXISTS reward_events_insert_authenticated ON public.reward_events","CREATE POLICY reward_events_insert_authenticated ON public.reward_events\n  FOR INSERT TO authenticated\n  WITH CHECK (user_id = auth.uid() OR public.is_admin() OR user_id IS NULL)","-- ---------------------------------------------------------------------------\n-- 10. Helpers\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.generate_referral_code()\nRETURNS text\nLANGUAGE plpgsql\nAS $$\nDECLARE\n  v_code text;\nBEGIN\n  LOOP\n    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));\n    EXIT WHEN NOT EXISTS (\n      SELECT 1 FROM public.loyalty_accounts WHERE referral_code = v_code\n    );\n  END LOOP;\n  RETURN v_code;\nEND;\n$$","CREATE OR REPLACE FUNCTION public.ensure_loyalty_account(p_user_id uuid DEFAULT auth.uid())\nRETURNS public.loyalty_accounts\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_row public.loyalty_accounts;\nBEGIN\n  IF p_user_id IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n  IF p_user_id <> auth.uid() AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Forbidden';\n  END IF;\n\n  SELECT * INTO v_row FROM public.loyalty_accounts WHERE user_id = p_user_id;\n  IF FOUND THEN\n    RETURN v_row;\n  END IF;\n\n  INSERT INTO public.loyalty_accounts (user_id, referral_code)\n  VALUES (p_user_id, public.generate_referral_code())\n  RETURNING * INTO v_row;\n\n  RETURN v_row;\nEND;\n$$","REVOKE ALL ON FUNCTION public.ensure_loyalty_account(uuid) FROM PUBLIC","GRANT EXECUTE ON FUNCTION public.ensure_loyalty_account(uuid) TO authenticated","CREATE OR REPLACE FUNCTION public.lookup_gift_card(p_code text)\nRETURNS TABLE (\n  id uuid,\n  code text,\n  balance numeric,\n  status text,\n  expires_at timestamptz,\n  currency text\n)\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nBEGIN\n  RETURN QUERY\n  SELECT g.id, g.code, g.balance, g.status, g.expires_at, g.currency\n  FROM public.gift_cards g\n  WHERE upper(g.code) = upper(trim(p_code))\n  LIMIT 1;\nEND;\n$$","REVOKE ALL ON FUNCTION public.lookup_gift_card(text) FROM PUBLIC","GRANT EXECUTE ON FUNCTION public.lookup_gift_card(text) TO authenticated","-- ---------------------------------------------------------------------------\n-- 11. Extended place_order (optional rewards; defaults = prior behavior)\n-- Drop prior overloads so only the extended signature remains.\n-- ---------------------------------------------------------------------------\nDROP FUNCTION IF EXISTS public.place_order(uuid, text, uuid, jsonb, text)","DROP FUNCTION IF EXISTS public.place_order(uuid, text, uuid, jsonb, text, text)","CREATE OR REPLACE FUNCTION public.place_order(\n  p_user_id uuid DEFAULT auth.uid(),\n  p_delivery_type text DEFAULT NULL,\n  p_pickup_location_id uuid DEFAULT NULL,\n  p_delivery_address jsonb DEFAULT NULL,\n  p_customer_note text DEFAULT NULL,\n  p_payment_method text DEFAULT 'cod',\n  p_coupon_code text DEFAULT NULL,\n  p_loyalty_points integer DEFAULT 0,\n  p_gift_card_code text DEFAULT NULL,\n  p_gift_card_amount numeric DEFAULT 0,\n  p_discount_amount numeric DEFAULT 0,\n  p_free_delivery boolean DEFAULT false,\n  p_promotions_applied jsonb DEFAULT '[]'::jsonb,\n  p_referral_code text DEFAULT NULL\n)\nRETURNS uuid\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_order_id uuid;\n  v_subtotal numeric(12,2) := 0;\n  v_delivery_fee numeric(12,2) := 0;\n  v_total numeric(12,2) := 0;\n  v_discount numeric(12,2) := GREATEST(COALESCE(p_discount_amount, 0), 0);\n  v_gift numeric(12,2) := GREATEST(COALESCE(p_gift_card_amount, 0), 0);\n  v_points integer := GREATEST(COALESCE(p_loyalty_points, 0), 0);\n  v_free_delivery boolean := COALESCE(p_free_delivery, false);\n  v_payment_method text := COALESCE(NULLIF(trim(p_payment_method), ''), 'cod');\n  v_coupon public.coupons;\n  v_coupon_code text := NULLIF(upper(trim(p_coupon_code)), '');\n  v_gift_card public.gift_cards;\n  v_loyalty public.loyalty_accounts;\n  v_rule public.loyalty_rules;\n  v_points_value numeric(12,2) := 0;\n  v_user_redemptions integer := 0;\n  r RECORD;\nBEGIN\n  IF p_user_id IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n  IF auth.uid() IS DISTINCT FROM p_user_id AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  IF v_payment_method NOT IN ('cod', 'mpesa', 'card', 'paypal', 'bank_transfer') THEN\n    RAISE EXCEPTION 'Invalid payment method: %', v_payment_method;\n  END IF;\n\n  IF p_delivery_type IS NULL OR p_delivery_type NOT IN ('pickup', 'delivery') THEN\n    RAISE EXCEPTION 'Delivery type is required (pickup or delivery)';\n  END IF;\n\n  IF p_delivery_type = 'pickup' THEN\n    IF p_pickup_location_id IS NULL THEN\n      RAISE EXCEPTION 'Pickup location is required';\n    END IF;\n    IF NOT EXISTS (\n      SELECT 1 FROM public.pickup_locations\n      WHERE id = p_pickup_location_id AND is_active = true\n    ) THEN\n      RAISE EXCEPTION 'Invalid or inactive pickup location';\n    END IF;\n  END IF;\n\n  IF p_delivery_type = 'delivery' THEN\n    IF p_delivery_address IS NULL\n       OR NULLIF(trim(p_delivery_address->>'line1'), '') IS NULL\n       OR NULLIF(trim(p_delivery_address->>'city'), '') IS NULL\n       OR NULLIF(trim(p_delivery_address->>'phone'), '') IS NULL THEN\n      RAISE EXCEPTION 'Delivery address (line1, city, phone) is required';\n    END IF;\n    IF NOT v_free_delivery THEN\n      v_delivery_fee := 200;\n    END IF;\n  END IF;\n\n  PERFORM 1\n  FROM public.products p\n  JOIN public.cart_items c ON c.product_id = p.id\n  WHERE c.user_id = p_user_id\n  FOR UPDATE OF p;\n\n  FOR r IN\n    SELECT c.product_id, c.quantity, p.stock, p.name, p.is_active\n    FROM public.cart_items c\n    JOIN public.products p ON p.id = c.product_id\n    WHERE c.user_id = p_user_id\n  LOOP\n    IF NOT COALESCE(r.is_active, true) THEN\n      RAISE EXCEPTION 'Product % is no longer available', r.name;\n    END IF;\n    IF r.stock < r.quantity THEN\n      RAISE EXCEPTION 'Insufficient stock for %', r.name;\n    END IF;\n  END LOOP;\n\n  SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)\n  INTO v_subtotal\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  IF v_subtotal = 0 THEN\n    RAISE EXCEPTION 'Cart is empty';\n  END IF;\n\n  -- Coupon validation (server-side safety net)\n  IF v_coupon_code IS NOT NULL THEN\n    SELECT * INTO v_coupon FROM public.coupons\n    WHERE upper(code) = v_coupon_code\n    FOR UPDATE;\n\n    IF NOT FOUND OR v_coupon.is_active = false THEN\n      RAISE EXCEPTION 'Invalid coupon code';\n    END IF;\n    IF v_coupon.starts_at IS NOT NULL AND v_coupon.starts_at > now() THEN\n      RAISE EXCEPTION 'Coupon is not active yet';\n    END IF;\n    IF v_coupon.ends_at IS NOT NULL AND v_coupon.ends_at < now() THEN\n      RAISE EXCEPTION 'Coupon has expired';\n    END IF;\n    IF v_coupon.usage_limit IS NOT NULL AND v_coupon.usage_count >= v_coupon.usage_limit THEN\n      RAISE EXCEPTION 'Coupon usage limit reached';\n    END IF;\n    IF v_subtotal < COALESCE(v_coupon.min_order_amount, 0) THEN\n      RAISE EXCEPTION 'Order does not meet coupon minimum';\n    END IF;\n\n    SELECT COUNT(*) INTO v_user_redemptions\n    FROM public.coupon_redemptions\n    WHERE coupon_id = v_coupon.id AND user_id = p_user_id;\n\n    IF v_coupon.per_user_limit IS NOT NULL AND v_user_redemptions >= v_coupon.per_user_limit THEN\n      RAISE EXCEPTION 'You have already used this coupon';\n    END IF;\n    IF v_coupon.is_one_time AND v_user_redemptions > 0 THEN\n      RAISE EXCEPTION 'This one-time coupon was already used';\n    END IF;\n\n    IF v_coupon.free_delivery OR v_coupon.discount_type = 'free_delivery' THEN\n      v_free_delivery := true;\n      v_delivery_fee := 0;\n    END IF;\n  END IF;\n\n  -- Loyalty redemption\n  IF v_points > 0 THEN\n    v_loyalty := public.ensure_loyalty_account(p_user_id);\n    IF v_loyalty.points_balance < v_points THEN\n      RAISE EXCEPTION 'Insufficient loyalty points';\n    END IF;\n    SELECT * INTO v_rule FROM public.loyalty_rules\n    WHERE is_active = true ORDER BY created_at ASC LIMIT 1;\n    IF FOUND THEN\n      IF v_points < v_rule.min_redeem_points THEN\n        RAISE EXCEPTION 'Minimum % points required to redeem', v_rule.min_redeem_points;\n      END IF;\n      v_points_value := round(v_points / NULLIF(v_rule.redeem_points_per_currency, 0), 2);\n    ELSE\n      v_points_value := round(v_points / 10.0, 2);\n    END IF;\n    v_discount := v_discount + COALESCE(v_points_value, 0);\n  END IF;\n\n  -- Cap merchandise discount\n  IF v_discount > v_subtotal THEN\n    v_discount := v_subtotal;\n  END IF;\n\n  v_total := GREATEST(v_subtotal - v_discount, 0) + v_delivery_fee;\n\n  -- Gift card (partial redemption)\n  IF NULLIF(trim(p_gift_card_code), '') IS NOT NULL AND v_gift > 0 THEN\n    SELECT * INTO v_gift_card FROM public.gift_cards\n    WHERE upper(code) = upper(trim(p_gift_card_code))\n    FOR UPDATE;\n    IF NOT FOUND OR v_gift_card.status <> 'active' THEN\n      RAISE EXCEPTION 'Invalid gift card';\n    END IF;\n    IF v_gift_card.expires_at IS NOT NULL AND v_gift_card.expires_at < now() THEN\n      RAISE EXCEPTION 'Gift card expired';\n    END IF;\n    IF v_gift > v_gift_card.balance THEN\n      RAISE EXCEPTION 'Gift card balance too low';\n    END IF;\n    IF v_gift > v_total THEN\n      v_gift := v_total;\n    END IF;\n    v_total := v_total - v_gift;\n  ELSE\n    v_gift := 0;\n  END IF;\n\n  INSERT INTO public.orders (\n    user_id, status, total, payment_status, payment_method,\n    delivery_type, pickup_location_id, delivery_address,\n    delivery_fee, customer_note,\n    discount_amount, coupon_code, loyalty_points_redeemed,\n    gift_card_amount, free_delivery, promotions_applied, referral_code\n  )\n  VALUES (\n    p_user_id, 'pending', v_total, 'pending', v_payment_method,\n    p_delivery_type, p_pickup_location_id, p_delivery_address,\n    v_delivery_fee, NULLIF(trim(p_customer_note), ''),\n    v_discount, v_coupon_code, v_points,\n    v_gift, v_free_delivery,\n    COALESCE(p_promotions_applied, '[]'::jsonb),\n    NULLIF(upper(trim(p_referral_code)), '')\n  )\n  RETURNING id INTO v_order_id;\n\n  INSERT INTO public.order_items (order_id, product_id, name, price, quantity, image_url)\n  SELECT\n    v_order_id,\n    c.product_id,\n    p.name,\n    COALESCE(p.discount_price, p.price),\n    c.quantity,\n    COALESCE(\n      p.image_url,\n      CASE WHEN jsonb_typeof(p.images) = 'array'\n           THEN p.images->0->>'url'\n           ELSE NULL END\n    )\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  UPDATE public.products p\n  SET stock = p.stock - c.quantity\n  FROM public.cart_items c\n  WHERE c.user_id = p_user_id AND p.id = c.product_id;\n\n  DELETE FROM public.cart_items WHERE user_id = p_user_id;\n\n  -- Record coupon redemption\n  IF v_coupon.id IS NOT NULL THEN\n    INSERT INTO public.coupon_redemptions (coupon_id, user_id, order_id, discount_amount)\n    VALUES (v_coupon.id, p_user_id, v_order_id, v_discount);\n    UPDATE public.coupons SET usage_count = usage_count + 1 WHERE id = v_coupon.id;\n  END IF;\n\n  -- Deduct loyalty points\n  IF v_points > 0 THEN\n    UPDATE public.loyalty_accounts\n    SET points_balance = points_balance - v_points,\n        lifetime_redeemed = lifetime_redeemed + v_points\n    WHERE user_id = p_user_id\n    RETURNING * INTO v_loyalty;\n\n    INSERT INTO public.loyalty_transactions (\n      user_id, tx_type, points, balance_after, order_id, description\n    ) VALUES (\n      p_user_id, 'redeem_discount', -v_points, v_loyalty.points_balance, v_order_id,\n      'Redeemed at checkout'\n    );\n  END IF;\n\n  -- Gift card redeem\n  IF v_gift > 0 AND v_gift_card.id IS NOT NULL THEN\n    UPDATE public.gift_cards\n    SET balance = balance - v_gift,\n        status = CASE WHEN balance - v_gift <= 0 THEN 'depleted' ELSE status END\n    WHERE id = v_gift_card.id\n    RETURNING * INTO v_gift_card;\n\n    INSERT INTO public.gift_card_transactions (\n      gift_card_id, user_id, order_id, tx_type, amount, balance_after\n    ) VALUES (\n      v_gift_card.id, p_user_id, v_order_id, 'redeem', v_gift, v_gift_card.balance\n    );\n  END IF;\n\n  INSERT INTO public.reward_events (user_id, order_id, event_type, payload)\n  VALUES (\n    p_user_id, v_order_id, 'checkout_rewards_applied',\n    jsonb_build_object(\n      'discount', v_discount,\n      'gift_card', v_gift,\n      'points', v_points,\n      'coupon', v_coupon_code,\n      'free_delivery', v_free_delivery\n    )\n  );\n\n  PERFORM public.log_order_event(v_order_id, 'order_placed', jsonb_build_object(\n    'delivery_type', p_delivery_type,\n    'payment_method', v_payment_method,\n    'discount_amount', v_discount\n  ));\n\n  RETURN v_order_id;\nEND;\n$$","REVOKE ALL ON FUNCTION public.place_order(\n  uuid, text, uuid, jsonb, text, text, text, integer, text, numeric, numeric, boolean, jsonb, text\n) FROM PUBLIC","GRANT EXECUTE ON FUNCTION public.place_order(\n  uuid, text, uuid, jsonb, text, text, text, integer, text, numeric, numeric, boolean, jsonb, text\n) TO authenticated","-- Earn points when payment becomes paid / order delivered (simple helper)\nCREATE OR REPLACE FUNCTION public.award_loyalty_for_order(p_order_id uuid)\nRETURNS integer\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_order public.orders;\n  v_rule public.loyalty_rules;\n  v_points integer := 0;\n  v_loyalty public.loyalty_accounts;\n  v_existing integer;\nBEGIN\n  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Order not found';\n  END IF;\n\n  SELECT COUNT(*) INTO v_existing\n  FROM public.loyalty_transactions\n  WHERE order_id = p_order_id AND tx_type = 'earn_purchase';\n  IF v_existing > 0 THEN\n    RETURN 0;\n  END IF;\n\n  SELECT * INTO v_rule FROM public.loyalty_rules WHERE is_active = true ORDER BY created_at ASC LIMIT 1;\n  IF NOT FOUND THEN\n    v_points := floor(v_order.total * 0.01)::integer;\n  ELSE\n    v_points := floor(v_order.total * v_rule.earn_points_per_currency);\n  END IF;\n\n  IF v_points <= 0 THEN\n    RETURN 0;\n  END IF;\n\n  v_loyalty := public.ensure_loyalty_account(v_order.user_id);\n  UPDATE public.loyalty_accounts\n  SET points_balance = points_balance + v_points,\n      lifetime_earned = lifetime_earned + v_points\n  WHERE user_id = v_order.user_id\n  RETURNING * INTO v_loyalty;\n\n  INSERT INTO public.loyalty_transactions (\n    user_id, tx_type, points, balance_after, order_id, description\n  ) VALUES (\n    v_order.user_id, 'earn_purchase', v_points, v_loyalty.points_balance, p_order_id,\n    'Points earned from order'\n  );\n\n  RETURN v_points;\nEND;\n$$","REVOKE ALL ON FUNCTION public.award_loyalty_for_order(uuid) FROM PUBLIC","GRANT EXECUTE ON FUNCTION public.award_loyalty_for_order(uuid) TO authenticated","-- ---------------------------------------------------------------------------\n-- 12. Seed defaults + mock catalog\n-- ---------------------------------------------------------------------------\nINSERT INTO public.loyalty_rules (code, name, earn_points_per_currency, redeem_points_per_currency, free_delivery_points, min_redeem_points)\nVALUES ('default', 'Default loyalty rules', 0.01, 10, 500, 100)\nON CONFLICT (code) DO NOTHING","INSERT INTO public.promotions (\n  code, name, description, promo_type, status, priority, stackable,\n  percent_off, min_order_amount, starts_at, ends_at\n)\nSELECT\n  'STORE10', 'Storewide 10% off', 'Automatic 10% off orders over 2000 KES',\n  'storewide', 'active', 50, false, 10, 2000,\n  now() - interval '1 day', now() + interval '180 days'\nWHERE NOT EXISTS (SELECT 1 FROM public.promotions WHERE code = 'STORE10')","INSERT INTO public.coupons (\n  code, name, description, discount_type, percent_off, min_order_amount,\n  usage_limit, per_user_limit, is_one_time, is_active, starts_at, ends_at\n) VALUES (\n  'WELCOME15', 'Welcome 15% off', 'New customer coupon',\n  'percentage', 15, 500, 1000, 1, false, true,\n  now() - interval '1 day', now() + interval '365 days'\n), (\n  'FREESHIP', 'Free delivery', 'Waives delivery fee',\n  'free_delivery', NULL, 0, NULL, 5, false, true,\n  now() - interval '1 day', now() + interval '365 days'\n), (\n  'SAVE200', 'Save 200 KES', 'Fixed amount off',\n  'fixed', NULL, 1000, 500, 2, false, true,\n  now() - interval '1 day', now() + interval '365 days'\n) ON CONFLICT (code) DO NOTHING","-- Fix SAVE200 amount_off\nUPDATE public.coupons SET amount_off = 200 WHERE code = 'SAVE200' AND amount_off IS NULL","INSERT INTO public.gift_cards (code, initial_balance, balance, status, expires_at)\nVALUES (\n  'GIFT1000', 1000, 1000, 'active', now() + interval '365 days'\n) ON CONFLICT (code) DO NOTHING"}	promotions_loyalty
019	{"-- 019_operations.sql\n-- Workstream 9 — Operations: admin audit log (minimal schema change)\n-- Idempotent. No customer-facing schema.\n\nCREATE TABLE IF NOT EXISTS public.admin_audit_logs (\n  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),\n  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,\n  action text NOT NULL,\n  entity_type text NOT NULL,\n  entity_id text,\n  summary text,\n  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,\n  ip_hint text,\n  created_at timestamptz NOT NULL DEFAULT now(),\n  CONSTRAINT admin_audit_logs_action_check CHECK (char_length(action) > 0),\n  CONSTRAINT admin_audit_logs_entity_type_check CHECK (char_length(entity_type) > 0)\n)","CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_created\n  ON public.admin_audit_logs (created_at DESC)","CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_actor\n  ON public.admin_audit_logs (actor_id, created_at DESC)","CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_entity\n  ON public.admin_audit_logs (entity_type, entity_id)","ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY","DROP POLICY IF EXISTS admin_audit_logs_select_admin ON public.admin_audit_logs","CREATE POLICY admin_audit_logs_select_admin ON public.admin_audit_logs\n  FOR SELECT TO authenticated\n  USING (public.is_admin())","DROP POLICY IF EXISTS admin_audit_logs_insert_admin ON public.admin_audit_logs","CREATE POLICY admin_audit_logs_insert_admin ON public.admin_audit_logs\n  FOR INSERT TO authenticated\n  WITH CHECK (public.is_admin())","-- SECURITY DEFINER insert so non-admin paths cannot write; callers still check is_admin client-side\nCREATE OR REPLACE FUNCTION public.write_admin_audit(\n  p_action text,\n  p_entity_type text,\n  p_entity_id text DEFAULT NULL,\n  p_summary text DEFAULT NULL,\n  p_metadata jsonb DEFAULT '{}'::jsonb\n)\nRETURNS uuid\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_id uuid;\nBEGIN\n  IF NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Forbidden';\n  END IF;\n\n  INSERT INTO public.admin_audit_logs (\n    actor_id, action, entity_type, entity_id, summary, metadata\n  ) VALUES (\n    auth.uid(),\n    trim(p_action),\n    trim(p_entity_type),\n    NULLIF(trim(p_entity_id), ''),\n    NULLIF(trim(p_summary), ''),\n    COALESCE(p_metadata, '{}'::jsonb)\n  )\n  RETURNING id INTO v_id;\n\n  RETURN v_id;\nEND;\n$$","REVOKE ALL ON FUNCTION public.write_admin_audit(text, text, text, text, jsonb) FROM PUBLIC","GRANT EXECUTE ON FUNCTION public.write_admin_audit(text, text, text, text, jsonb) TO authenticated","COMMENT ON TABLE public.admin_audit_logs IS\n  'WS9 — administrator action audit trail.'"}	operations
020	{"-- 020_security_hardening.sql\n-- Production security / integrity hardening (v1.0 acceptance audit).\n--\n-- 1. place_order() — server-authoritative discounts (ignore client p_discount_amount / p_free_delivery)\n-- 2. finalize_payment() — caller must own payment or be admin\n-- 3. payments RLS — revoke direct customer UPDATE\n-- 4. orders — block direct PostgREST updates to sensitive columns (RPC bypass via definer role)\n-- 5. award_loyalty_for_order() — caller must own order or be admin\n\n-- ---------------------------------------------------------------------------\n-- 1. Server-side promotion computation for checkout\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.compute_checkout_promotions(p_user_id uuid)\nRETURNS jsonb\nLANGUAGE plpgsql\nSTABLE\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_subtotal numeric(12,2) := 0;\n  v_merch_discount numeric(12,2) := 0;\n  v_free_delivery boolean := false;\n  v_used_non_stackable boolean := false;\n  v_promo public.promotions%ROWTYPE;\n  v_line_discount numeric(12,2) := 0;\n  v_eligible_subtotal numeric(12,2) := 0;\n  v_applied jsonb := '[]'::jsonb;\n  v_qty integer := 0;\n  v_unit numeric(12,2) := 0;\n  v_sets integer := 0;\n  v_applicable boolean := false;\nBEGIN\n  SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)\n  INTO v_subtotal\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  FOR v_promo IN\n    SELECT *\n    FROM public.promotions\n    WHERE status = 'active'\n      AND (starts_at IS NULL OR starts_at <= now())\n      AND (ends_at IS NULL OR ends_at >= now())\n    ORDER BY priority DESC, created_at ASC\n  LOOP\n    IF NOT v_promo.stackable AND v_used_non_stackable THEN\n      CONTINUE;\n    END IF;\n\n    IF v_subtotal < COALESCE(v_promo.min_order_amount, 0) THEN\n      CONTINUE;\n    END IF;\n\n    IF v_promo.usage_limit IS NOT NULL AND v_promo.usage_count >= v_promo.usage_limit THEN\n      CONTINUE;\n    END IF;\n\n    v_line_discount := 0;\n    v_eligible_subtotal := v_subtotal;\n    v_applicable := false;\n\n    IF v_promo.promo_type = 'category' AND v_promo.category_id IS NOT NULL THEN\n      SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)\n      INTO v_eligible_subtotal\n      FROM public.cart_items c\n      JOIN public.products p ON p.id = c.product_id\n      WHERE c.user_id = p_user_id\n        AND p.category_id = v_promo.category_id;\n    ELSIF v_promo.promo_type = 'product' AND v_promo.product_id IS NOT NULL THEN\n      SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)\n      INTO v_eligible_subtotal\n      FROM public.cart_items c\n      JOIN public.products p ON p.id = c.product_id\n      WHERE c.user_id = p_user_id\n        AND p.id = v_promo.product_id;\n    END IF;\n\n    IF v_promo.promo_type = 'free_delivery' THEN\n      v_free_delivery := true;\n      v_applicable := true;\n    ELSIF v_promo.promo_type IN ('percentage', 'storewide', 'category', 'product') THEN\n      v_line_discount := round(v_eligible_subtotal * COALESCE(v_promo.percent_off, 0) / 100.0, 2);\n      v_applicable := v_line_discount > 0;\n    ELSIF v_promo.promo_type = 'fixed' THEN\n      v_line_discount := COALESCE(v_promo.amount_off, 0);\n      v_applicable := v_line_discount > 0;\n    ELSIF v_promo.promo_type = 'buy_x_get_y'\n      AND COALESCE(v_promo.buy_quantity, 0) > 0\n      AND COALESCE(v_promo.get_quantity, 0) > 0 THEN\n      SELECT COALESCE(SUM(c.quantity), 0)\n      INTO v_qty\n      FROM public.cart_items c\n      WHERE c.user_id = p_user_id\n        AND (v_promo.product_id IS NULL OR c.product_id = v_promo.product_id);\n\n      v_sets := v_qty / (v_promo.buy_quantity + v_promo.get_quantity);\n      IF v_sets > 0 THEN\n        SELECT MIN(COALESCE(p.discount_price, p.price))\n        INTO v_unit\n        FROM public.cart_items c\n        JOIN public.products p ON p.id = c.product_id\n        WHERE c.user_id = p_user_id\n          AND (v_promo.product_id IS NULL OR c.product_id = v_promo.product_id);\n\n        v_line_discount := round(v_sets * v_promo.get_quantity * COALESCE(v_unit, 0), 2);\n        v_applicable := v_line_discount > 0;\n      END IF;\n    END IF;\n\n    IF v_promo.max_discount_amount IS NOT NULL THEN\n      v_line_discount := LEAST(v_line_discount, v_promo.max_discount_amount);\n    END IF;\n    v_line_discount := LEAST(v_line_discount, v_subtotal);\n\n    IF v_applicable THEN\n      IF NOT v_promo.stackable THEN\n        v_used_non_stackable := true;\n      END IF;\n\n      v_merch_discount := v_merch_discount + v_line_discount;\n      IF v_promo.promo_type = 'free_delivery' THEN\n        v_free_delivery := true;\n      END IF;\n\n      v_applied := v_applied || jsonb_build_array(jsonb_build_object(\n        'id', v_promo.id,\n        'code', v_promo.code,\n        'name', v_promo.name,\n        'promoType', v_promo.promo_type,\n        'discount', v_line_discount,\n        'freeDelivery', v_promo.promo_type = 'free_delivery'\n      ));\n    END IF;\n  END LOOP;\n\n  v_merch_discount := LEAST(v_merch_discount, v_subtotal);\n\n  RETURN jsonb_build_object(\n    'merchandiseDiscount', v_merch_discount,\n    'freeDelivery', v_free_delivery,\n    'applied', v_applied,\n    'subtotal', v_subtotal\n  );\nEND;\n$$","REVOKE ALL ON FUNCTION public.compute_checkout_promotions(uuid) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.compute_checkout_promotions(uuid) TO authenticated","-- ---------------------------------------------------------------------------\n-- 2. Hardened place_order — server computes discounts; client params ignored\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.place_order(\n  p_user_id uuid DEFAULT auth.uid(),\n  p_delivery_type text DEFAULT NULL,\n  p_pickup_location_id uuid DEFAULT NULL,\n  p_delivery_address jsonb DEFAULT NULL,\n  p_customer_note text DEFAULT NULL,\n  p_payment_method text DEFAULT 'cod',\n  p_coupon_code text DEFAULT NULL,\n  p_loyalty_points integer DEFAULT 0,\n  p_gift_card_code text DEFAULT NULL,\n  p_gift_card_amount numeric DEFAULT 0,\n  p_discount_amount numeric DEFAULT 0,\n  p_free_delivery boolean DEFAULT false,\n  p_promotions_applied jsonb DEFAULT '[]'::jsonb,\n  p_referral_code text DEFAULT NULL\n)\nRETURNS uuid\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_order_id uuid;\n  v_subtotal numeric(12,2) := 0;\n  v_delivery_fee numeric(12,2) := 0;\n  v_total numeric(12,2) := 0;\n  v_discount numeric(12,2) := 0;\n  v_coupon_discount numeric(12,2) := 0;\n  v_gift numeric(12,2) := GREATEST(COALESCE(p_gift_card_amount, 0), 0);\n  v_points integer := GREATEST(COALESCE(p_loyalty_points, 0), 0);\n  v_free_delivery boolean := false;\n  v_payment_method text := COALESCE(NULLIF(trim(p_payment_method), ''), 'cod');\n  v_coupon public.coupons;\n  v_coupon_code text := NULLIF(upper(trim(p_coupon_code)), '');\n  v_gift_card public.gift_cards;\n  v_loyalty public.loyalty_accounts;\n  v_rule public.loyalty_rules;\n  v_points_value numeric(12,2) := 0;\n  v_remaining numeric(12,2) := 0;\n  v_max_loyalty numeric(12,2) := 0;\n  v_user_redemptions integer := 0;\n  v_promo_result jsonb;\n  v_applied jsonb := '[]'::jsonb;\n  r RECORD;\nBEGIN\n  -- p_discount_amount, p_free_delivery, and p_promotions_applied are accepted for\n  -- backwards-compatible signatures but are NOT trusted for pricing decisions.\n\n  IF p_user_id IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n  IF auth.uid() IS DISTINCT FROM p_user_id AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  IF v_payment_method NOT IN ('cod', 'mpesa', 'card', 'paypal', 'bank_transfer') THEN\n    RAISE EXCEPTION 'Invalid payment method: %', v_payment_method;\n  END IF;\n\n  IF p_delivery_type IS NULL OR p_delivery_type NOT IN ('pickup', 'delivery') THEN\n    RAISE EXCEPTION 'Delivery type is required (pickup or delivery)';\n  END IF;\n\n  IF p_delivery_type = 'pickup' THEN\n    IF p_pickup_location_id IS NULL THEN\n      RAISE EXCEPTION 'Pickup location is required';\n    END IF;\n    IF NOT EXISTS (\n      SELECT 1 FROM public.pickup_locations\n      WHERE id = p_pickup_location_id AND is_active = true\n    ) THEN\n      RAISE EXCEPTION 'Invalid or inactive pickup location';\n    END IF;\n  END IF;\n\n  IF p_delivery_type = 'delivery' THEN\n    IF p_delivery_address IS NULL\n       OR NULLIF(trim(p_delivery_address->>'line1'), '') IS NULL\n       OR NULLIF(trim(p_delivery_address->>'city'), '') IS NULL\n       OR NULLIF(trim(p_delivery_address->>'phone'), '') IS NULL THEN\n      RAISE EXCEPTION 'Delivery address (line1, city, phone) is required';\n    END IF;\n  END IF;\n\n  PERFORM 1\n  FROM public.products p\n  JOIN public.cart_items c ON c.product_id = p.id\n  WHERE c.user_id = p_user_id\n  FOR UPDATE OF p;\n\n  FOR r IN\n    SELECT c.product_id, c.quantity, p.stock, p.name, p.is_active\n    FROM public.cart_items c\n    JOIN public.products p ON p.id = c.product_id\n    WHERE c.user_id = p_user_id\n  LOOP\n    IF NOT COALESCE(r.is_active, true) THEN\n      RAISE EXCEPTION 'Product % is no longer available', r.name;\n    END IF;\n    IF r.stock < r.quantity THEN\n      RAISE EXCEPTION 'Insufficient stock for %', r.name;\n    END IF;\n  END LOOP;\n\n  SELECT COALESCE(SUM(COALESCE(p.discount_price, p.price) * c.quantity), 0)\n  INTO v_subtotal\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  IF v_subtotal = 0 THEN\n    RAISE EXCEPTION 'Cart is empty';\n  END IF;\n\n  -- Automatic promotions (authoritative)\n  v_promo_result := public.compute_checkout_promotions(p_user_id);\n  v_discount := COALESCE((v_promo_result->>'merchandiseDiscount')::numeric, 0);\n  v_free_delivery := COALESCE((v_promo_result->>'freeDelivery')::boolean, false);\n  v_applied := COALESCE(v_promo_result->'applied', '[]'::jsonb);\n\n  -- Coupon validation + server-computed discount\n  IF v_coupon_code IS NOT NULL THEN\n    SELECT * INTO v_coupon FROM public.coupons\n    WHERE upper(code) = v_coupon_code\n    FOR UPDATE;\n\n    IF NOT FOUND OR v_coupon.is_active = false THEN\n      RAISE EXCEPTION 'Invalid coupon code';\n    END IF;\n    IF v_coupon.starts_at IS NOT NULL AND v_coupon.starts_at > now() THEN\n      RAISE EXCEPTION 'Coupon is not active yet';\n    END IF;\n    IF v_coupon.ends_at IS NOT NULL AND v_coupon.ends_at < now() THEN\n      RAISE EXCEPTION 'Coupon has expired';\n    END IF;\n    IF v_coupon.usage_limit IS NOT NULL AND v_coupon.usage_count >= v_coupon.usage_limit THEN\n      RAISE EXCEPTION 'Coupon usage limit reached';\n    END IF;\n    IF v_subtotal < COALESCE(v_coupon.min_order_amount, 0) THEN\n      RAISE EXCEPTION 'Order does not meet coupon minimum';\n    END IF;\n\n    SELECT COUNT(*) INTO v_user_redemptions\n    FROM public.coupon_redemptions\n    WHERE coupon_id = v_coupon.id AND user_id = p_user_id;\n\n    IF v_coupon.per_user_limit IS NOT NULL AND v_user_redemptions >= v_coupon.per_user_limit THEN\n      RAISE EXCEPTION 'You have already used this coupon';\n    END IF;\n    IF v_coupon.is_one_time AND v_user_redemptions > 0 THEN\n      RAISE EXCEPTION 'This one-time coupon was already used';\n    END IF;\n\n    IF v_coupon.discount_type = 'percentage' THEN\n      v_coupon_discount := round(v_subtotal * COALESCE(v_coupon.percent_off, 0) / 100.0, 2);\n    ELSIF v_coupon.discount_type = 'fixed' THEN\n      v_coupon_discount := COALESCE(v_coupon.amount_off, 0);\n    ELSE\n      v_coupon_discount := 0;\n    END IF;\n\n    IF v_coupon.max_discount_amount IS NOT NULL THEN\n      v_coupon_discount := LEAST(v_coupon_discount, v_coupon.max_discount_amount);\n    END IF;\n    v_coupon_discount := LEAST(v_coupon_discount, v_subtotal);\n    v_discount := v_discount + v_coupon_discount;\n\n    IF v_coupon.free_delivery OR v_coupon.discount_type = 'free_delivery' THEN\n      v_free_delivery := true;\n    END IF;\n\n    v_applied := v_applied || jsonb_build_array(jsonb_build_object(\n      'id', v_coupon.id,\n      'code', v_coupon.code,\n      'name', v_coupon.name,\n      'promoType', 'coupon',\n      'discount', v_coupon_discount,\n      'freeDelivery', v_coupon.free_delivery OR v_coupon.discount_type = 'free_delivery'\n    ));\n  END IF;\n\n  IF v_discount > v_subtotal THEN\n    v_discount := v_subtotal;\n  END IF;\n\n  -- Loyalty redemption (server-computed value + max percent cap)\n  IF v_points > 0 THEN\n    v_loyalty := public.ensure_loyalty_account(p_user_id);\n    IF v_loyalty.points_balance < v_points THEN\n      RAISE EXCEPTION 'Insufficient loyalty points';\n    END IF;\n    SELECT * INTO v_rule FROM public.loyalty_rules\n    WHERE is_active = true ORDER BY created_at ASC LIMIT 1;\n    IF FOUND THEN\n      IF v_points < v_rule.min_redeem_points THEN\n        RAISE EXCEPTION 'Minimum % points required to redeem', v_rule.min_redeem_points;\n      END IF;\n      v_points_value := round(v_points / NULLIF(v_rule.redeem_points_per_currency, 0), 2);\n      v_remaining := GREATEST(v_subtotal - v_discount, 0);\n      v_max_loyalty := round(v_remaining * COALESCE(v_rule.max_redeem_percent, 50) / 100.0, 2);\n      v_points_value := LEAST(v_points_value, v_max_loyalty, v_remaining);\n    ELSE\n      v_points_value := round(v_points / 10.0, 2);\n      v_remaining := GREATEST(v_subtotal - v_discount, 0);\n      v_points_value := LEAST(v_points_value, v_remaining);\n    END IF;\n    v_discount := v_discount + COALESCE(v_points_value, 0);\n  END IF;\n\n  IF v_discount > v_subtotal THEN\n    v_discount := v_subtotal;\n  END IF;\n\n  IF p_delivery_type = 'delivery' THEN\n    IF NOT v_free_delivery THEN\n      v_delivery_fee := 200;\n    END IF;\n  END IF;\n\n  v_total := GREATEST(v_subtotal - v_discount, 0) + v_delivery_fee;\n\n  -- Gift card (partial redemption)\n  IF NULLIF(trim(p_gift_card_code), '') IS NOT NULL AND v_gift > 0 THEN\n    SELECT * INTO v_gift_card FROM public.gift_cards\n    WHERE upper(code) = upper(trim(p_gift_card_code))\n    FOR UPDATE;\n    IF NOT FOUND OR v_gift_card.status <> 'active' THEN\n      RAISE EXCEPTION 'Invalid gift card';\n    END IF;\n    IF v_gift_card.expires_at IS NOT NULL AND v_gift_card.expires_at < now() THEN\n      RAISE EXCEPTION 'Gift card expired';\n    END IF;\n    IF v_gift > v_gift_card.balance THEN\n      RAISE EXCEPTION 'Gift card balance too low';\n    END IF;\n    IF v_gift > v_total THEN\n      v_gift := v_total;\n    END IF;\n    v_total := v_total - v_gift;\n  ELSE\n    v_gift := 0;\n  END IF;\n\n  INSERT INTO public.orders (\n    user_id, status, total, payment_status, payment_method,\n    delivery_type, pickup_location_id, delivery_address,\n    delivery_fee, customer_note,\n    discount_amount, coupon_code, loyalty_points_redeemed,\n    gift_card_amount, free_delivery, promotions_applied, referral_code\n  )\n  VALUES (\n    p_user_id, 'pending', v_total, 'pending', v_payment_method,\n    p_delivery_type, p_pickup_location_id, p_delivery_address,\n    v_delivery_fee, NULLIF(trim(p_customer_note), ''),\n    v_discount, v_coupon_code, v_points,\n    v_gift, v_free_delivery,\n    v_applied,\n    NULLIF(upper(trim(p_referral_code)), '')\n  )\n  RETURNING id INTO v_order_id;\n\n  INSERT INTO public.order_items (order_id, product_id, name, price, quantity, image_url)\n  SELECT\n    v_order_id,\n    c.product_id,\n    p.name,\n    COALESCE(p.discount_price, p.price),\n    c.quantity,\n    COALESCE(\n      p.image_url,\n      CASE WHEN jsonb_typeof(p.images) = 'array'\n           THEN p.images->0->>'url'\n           ELSE NULL END\n    )\n  FROM public.cart_items c\n  JOIN public.products p ON p.id = c.product_id\n  WHERE c.user_id = p_user_id;\n\n  UPDATE public.products p\n  SET stock = p.stock - c.quantity\n  FROM public.cart_items c\n  WHERE c.user_id = p_user_id AND p.id = c.product_id;\n\n  DELETE FROM public.cart_items WHERE user_id = p_user_id;\n\n  IF v_coupon.id IS NOT NULL THEN\n    INSERT INTO public.coupon_redemptions (coupon_id, user_id, order_id, discount_amount)\n    VALUES (v_coupon.id, p_user_id, v_order_id, v_coupon_discount);\n    UPDATE public.coupons SET usage_count = usage_count + 1 WHERE id = v_coupon.id;\n  END IF;\n\n  IF v_points > 0 THEN\n    UPDATE public.loyalty_accounts\n    SET points_balance = points_balance - v_points,\n        lifetime_redeemed = lifetime_redeemed + v_points\n    WHERE user_id = p_user_id\n    RETURNING * INTO v_loyalty;\n\n    INSERT INTO public.loyalty_transactions (\n      user_id, tx_type, points, balance_after, order_id, description\n    ) VALUES (\n      p_user_id, 'redeem_discount', -v_points, v_loyalty.points_balance, v_order_id,\n      'Redeemed at checkout'\n    );\n  END IF;\n\n  IF v_gift > 0 AND v_gift_card.id IS NOT NULL THEN\n    UPDATE public.gift_cards\n    SET balance = balance - v_gift,\n        status = CASE WHEN balance - v_gift <= 0 THEN 'depleted' ELSE status END\n    WHERE id = v_gift_card.id\n    RETURNING * INTO v_gift_card;\n\n    INSERT INTO public.gift_card_transactions (\n      gift_card_id, user_id, order_id, tx_type, amount, balance_after\n    ) VALUES (\n      v_gift_card.id, p_user_id, v_order_id, 'redeem', v_gift, v_gift_card.balance\n    );\n  END IF;\n\n  INSERT INTO public.reward_events (user_id, order_id, event_type, payload)\n  VALUES (\n    p_user_id, v_order_id, 'checkout_rewards_applied',\n    jsonb_build_object(\n      'discount', v_discount,\n      'gift_card', v_gift,\n      'points', v_points,\n      'coupon', v_coupon_code,\n      'free_delivery', v_free_delivery,\n      'client_discount_ignored', COALESCE(p_discount_amount, 0),\n      'client_free_delivery_ignored', COALESCE(p_free_delivery, false)\n    )\n  );\n\n  PERFORM public.log_order_event(v_order_id, 'order_placed', jsonb_build_object(\n    'delivery_type', p_delivery_type,\n    'payment_method', v_payment_method,\n    'discount_amount', v_discount\n  ));\n\n  RETURN v_order_id;\nEND;\n$$","REVOKE ALL ON FUNCTION public.place_order(\n  uuid, text, uuid, jsonb, text, text, text, integer, text, numeric, numeric, boolean, jsonb, text\n) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.place_order(\n  uuid, text, uuid, jsonb, text, text, text, integer, text, numeric, numeric, boolean, jsonb, text\n) TO authenticated","-- ---------------------------------------------------------------------------\n-- 3. Harden finalize_payment — payment owner or admin only\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.finalize_payment(\n  p_payment_id uuid,\n  p_status text,\n  p_receipt_number text DEFAULT NULL,\n  p_transaction_reference text DEFAULT NULL,\n  p_failure_reason text DEFAULT NULL,\n  p_raw_callback jsonb DEFAULT '{}'::jsonb\n)\nRETURNS public.payments\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_payment public.payments%ROWTYPE;\n  v_order public.orders%ROWTYPE;\n  v_status text := lower(trim(p_status));\nBEGIN\n  IF auth.uid() IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n\n  IF v_status NOT IN ('paid', 'failed', 'cancelled', 'expired', 'processing') THEN\n    RAISE EXCEPTION 'Invalid finalize status: %', p_status;\n  END IF;\n\n  SELECT * INTO v_payment FROM public.payments WHERE id = p_payment_id FOR UPDATE;\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Payment not found';\n  END IF;\n\n  IF auth.uid() IS DISTINCT FROM v_payment.user_id AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  IF v_payment.status = 'paid' AND v_status = 'paid' THEN\n    INSERT INTO public.payment_events (payment_id, event_type, payload)\n    VALUES (\n      p_payment_id,\n      'duplicate_callback_ignored',\n      COALESCE(p_raw_callback, '{}'::jsonb)\n    );\n    RETURN v_payment;\n  END IF;\n\n  IF v_payment.status = 'paid' AND v_status <> 'paid' THEN\n    INSERT INTO public.payment_events (payment_id, event_type, payload)\n    VALUES (\n      p_payment_id,\n      'stale_callback_ignored',\n      jsonb_build_object('attempted_status', v_status)\n    );\n    RETURN v_payment;\n  END IF;\n\n  UPDATE public.payments\n  SET status = v_status,\n      receipt_number = COALESCE(NULLIF(trim(p_receipt_number), ''), receipt_number),\n      transaction_reference = COALESCE(NULLIF(trim(p_transaction_reference), ''), transaction_reference),\n      failure_reason = CASE\n        WHEN v_status IN ('failed', 'cancelled', 'expired')\n          THEN COALESCE(NULLIF(trim(p_failure_reason), ''), failure_reason)\n        ELSE NULL\n      END,\n      raw_callback = COALESCE(p_raw_callback, '{}'::jsonb),\n      paid_at = CASE WHEN v_status = 'paid' THEN now() ELSE paid_at END,\n      updated_at = now()\n  WHERE id = p_payment_id\n  RETURNING * INTO v_payment;\n\n  INSERT INTO public.payment_events (payment_id, event_type, payload)\n  VALUES (\n    p_payment_id,\n    'payment_' || v_status,\n    COALESCE(p_raw_callback, '{}'::jsonb)\n  );\n\n  SELECT * INTO v_order FROM public.orders WHERE id = v_payment.order_id FOR UPDATE;\n\n  IF v_status = 'paid' THEN\n    UPDATE public.orders\n    SET payment_status = 'paid',\n        mpesa_receipt_number = COALESCE(v_payment.receipt_number, mpesa_receipt_number),\n        payment_method = COALESCE(v_payment.method, payment_method),\n        updated_at = now()\n    WHERE id = v_payment.order_id;\n\n    PERFORM public.log_order_event(v_payment.order_id, 'payment_status_changed', jsonb_build_object(\n      'from', v_order.payment_status,\n      'to', 'paid',\n      'payment_id', p_payment_id,\n      'receipt_number', v_payment.receipt_number\n    ));\n  ELSIF v_status IN ('failed', 'cancelled', 'expired') THEN\n    IF v_order.payment_status IS DISTINCT FROM 'paid' THEN\n      UPDATE public.orders\n      SET payment_status = 'failed',\n          updated_at = now()\n      WHERE id = v_payment.order_id;\n\n      PERFORM public.log_order_event(v_payment.order_id, 'payment_status_changed', jsonb_build_object(\n        'from', v_order.payment_status,\n        'to', 'failed',\n        'payment_id', p_payment_id,\n        'reason', v_payment.failure_reason\n      ));\n    END IF;\n  END IF;\n\n  RETURN v_payment;\nEND;\n$$","REVOKE ALL ON FUNCTION public.finalize_payment(uuid, text, text, text, text, jsonb) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.finalize_payment(uuid, text, text, text, text, jsonb) TO authenticated","-- ---------------------------------------------------------------------------\n-- 4. Harden award_loyalty_for_order — order owner or admin only\n-- ---------------------------------------------------------------------------\nCREATE OR REPLACE FUNCTION public.award_loyalty_for_order(p_order_id uuid)\nRETURNS integer\nLANGUAGE plpgsql\nSECURITY DEFINER\nSET search_path = public\nAS $$\nDECLARE\n  v_order public.orders;\n  v_rule public.loyalty_rules;\n  v_points integer := 0;\n  v_loyalty public.loyalty_accounts;\n  v_existing integer;\nBEGIN\n  IF auth.uid() IS NULL THEN\n    RAISE EXCEPTION 'Not authenticated';\n  END IF;\n\n  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;\n  IF NOT FOUND THEN\n    RAISE EXCEPTION 'Order not found';\n  END IF;\n\n  IF auth.uid() IS DISTINCT FROM v_order.user_id AND NOT public.is_admin() THEN\n    RAISE EXCEPTION 'Unauthorized';\n  END IF;\n\n  SELECT COUNT(*) INTO v_existing\n  FROM public.loyalty_transactions\n  WHERE order_id = p_order_id AND tx_type = 'earn_purchase';\n  IF v_existing > 0 THEN\n    RETURN 0;\n  END IF;\n\n  SELECT * INTO v_rule FROM public.loyalty_rules WHERE is_active = true ORDER BY created_at ASC LIMIT 1;\n  IF NOT FOUND THEN\n    v_points := floor(v_order.total * 0.01)::integer;\n  ELSE\n    v_points := floor(v_order.total * v_rule.earn_points_per_currency)::integer;\n  END IF;\n\n  IF v_points <= 0 THEN\n    RETURN 0;\n  END IF;\n\n  v_loyalty := public.ensure_loyalty_account(v_order.user_id);\n  UPDATE public.loyalty_accounts\n  SET points_balance = points_balance + v_points,\n      lifetime_earned = lifetime_earned + v_points\n  WHERE user_id = v_order.user_id\n  RETURNING * INTO v_loyalty;\n\n  INSERT INTO public.loyalty_transactions (\n    user_id, tx_type, points, balance_after, order_id, description\n  ) VALUES (\n    v_order.user_id, 'earn_purchase', v_points, v_loyalty.points_balance, p_order_id,\n    'Points earned from order'\n  );\n\n  RETURN v_points;\nEND;\n$$","REVOKE ALL ON FUNCTION public.award_loyalty_for_order(uuid) FROM PUBLIC, anon","GRANT EXECUTE ON FUNCTION public.award_loyalty_for_order(uuid) TO authenticated","-- ---------------------------------------------------------------------------\n-- 5. payments RLS — admin-only direct UPDATE (RPCs handle customer flows)\n-- ---------------------------------------------------------------------------\nDROP POLICY IF EXISTS payments_update_own_or_admin ON public.payments","CREATE POLICY payments_update_admin_only ON public.payments\n  FOR UPDATE TO authenticated\n  USING (public.is_admin())\n  WITH CHECK (public.is_admin())","-- ---------------------------------------------------------------------------\n-- 6. orders — remove broad admin UPDATE; guard sensitive columns on direct UPDATE\n-- ---------------------------------------------------------------------------\nDROP POLICY IF EXISTS \\"Admins can update orders\\" ON public.orders","CREATE POLICY orders_update_admin_note ON public.orders\n  FOR UPDATE TO authenticated\n  USING (public.is_admin())\n  WITH CHECK (public.is_admin())","CREATE OR REPLACE FUNCTION public.guard_orders_direct_update()\nRETURNS trigger\nLANGUAGE plpgsql\nSET search_path = public\nAS $$\nBEGIN\n  -- SECURITY DEFINER RPCs run as the function owner (postgres) and may update freely.\n  IF current_user IN ('postgres', 'supabase_admin', 'service_role') THEN\n    RETURN NEW;\n  END IF;\n\n  IF TG_OP = 'UPDATE' THEN\n    IF NEW.status IS DISTINCT FROM OLD.status\n       OR NEW.payment_status IS DISTINCT FROM OLD.payment_status\n       OR NEW.total IS DISTINCT FROM OLD.total\n       OR NEW.discount_amount IS DISTINCT FROM OLD.discount_amount\n       OR NEW.delivery_fee IS DISTINCT FROM OLD.delivery_fee\n       OR NEW.user_id IS DISTINCT FROM OLD.user_id\n       OR NEW.delivery_type IS DISTINCT FROM OLD.delivery_type\n       OR NEW.pickup_location_id IS DISTINCT FROM OLD.pickup_location_id\n       OR NEW.delivery_address IS DISTINCT FROM OLD.delivery_address\n       OR NEW.payment_method IS DISTINCT FROM OLD.payment_method\n       OR NEW.gift_card_amount IS DISTINCT FROM OLD.gift_card_amount\n       OR NEW.loyalty_points_redeemed IS DISTINCT FROM OLD.loyalty_points_redeemed\n       OR NEW.free_delivery IS DISTINCT FROM OLD.free_delivery\n       OR NEW.coupon_code IS DISTINCT FROM OLD.coupon_code\n       OR NEW.mpesa_receipt_number IS DISTINCT FROM OLD.mpesa_receipt_number\n    THEN\n      RAISE EXCEPTION 'Direct order updates to status, payment, or financial fields are not allowed. Use order RPCs.';\n    END IF;\n  END IF;\n\n  RETURN NEW;\nEND;\n$$","DROP TRIGGER IF EXISTS orders_guard_sensitive_update ON public.orders","CREATE TRIGGER orders_guard_sensitive_update\n  BEFORE UPDATE ON public.orders\n  FOR EACH ROW\n  EXECUTE FUNCTION public.guard_orders_direct_update()"}	security_hardening
\.


--
-- Data for Name: secrets; Type: TABLE DATA; Schema: vault; Owner: -
--

COPY vault.secrets (id, name, description, secret, key_id, nonce, created_at, updated_at) FROM stdin;
\.


--
-- Name: refresh_tokens_id_seq; Type: SEQUENCE SET; Schema: auth; Owner: -
--

SELECT pg_catalog.setval('auth.refresh_tokens_id_seq', 104, true);


--
-- Name: subscription_id_seq; Type: SEQUENCE SET; Schema: realtime; Owner: -
--

SELECT pg_catalog.setval('realtime.subscription_id_seq', 1, false);


--
-- Name: mfa_amr_claims amr_id_pk; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT amr_id_pk PRIMARY KEY (id);


--
-- Name: audit_log_entries audit_log_entries_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.audit_log_entries
    ADD CONSTRAINT audit_log_entries_pkey PRIMARY KEY (id);


--
-- Name: custom_oauth_providers custom_oauth_providers_identifier_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.custom_oauth_providers
    ADD CONSTRAINT custom_oauth_providers_identifier_key UNIQUE (identifier);


--
-- Name: custom_oauth_providers custom_oauth_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.custom_oauth_providers
    ADD CONSTRAINT custom_oauth_providers_pkey PRIMARY KEY (id);


--
-- Name: flow_state flow_state_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.flow_state
    ADD CONSTRAINT flow_state_pkey PRIMARY KEY (id);


--
-- Name: identities identities_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_pkey PRIMARY KEY (id);


--
-- Name: identities identities_provider_id_provider_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_provider_id_provider_unique UNIQUE (provider_id, provider);


--
-- Name: instances instances_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.instances
    ADD CONSTRAINT instances_pkey PRIMARY KEY (id);


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_authentication_method_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_authentication_method_pkey UNIQUE (session_id, authentication_method);


--
-- Name: mfa_challenges mfa_challenges_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_pkey PRIMARY KEY (id);


--
-- Name: mfa_factors mfa_factors_last_challenged_at_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_last_challenged_at_key UNIQUE (last_challenged_at);


--
-- Name: mfa_factors mfa_factors_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_pkey PRIMARY KEY (id);


--
-- Name: mfa_recovery_code_sets mfa_recovery_code_sets_mfa_factor_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_code_sets
    ADD CONSTRAINT mfa_recovery_code_sets_mfa_factor_id_key UNIQUE (mfa_factor_id);


--
-- Name: mfa_recovery_code_sets mfa_recovery_code_sets_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_code_sets
    ADD CONSTRAINT mfa_recovery_code_sets_pkey PRIMARY KEY (id);


--
-- Name: mfa_recovery_code_sets mfa_recovery_code_sets_user_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_code_sets
    ADD CONSTRAINT mfa_recovery_code_sets_user_id_key UNIQUE (user_id);


--
-- Name: mfa_recovery_codes mfa_recovery_codes_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_codes
    ADD CONSTRAINT mfa_recovery_codes_pkey PRIMARY KEY (id);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_code_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_code_key UNIQUE (authorization_code);


--
-- Name: oauth_authorizations oauth_authorizations_authorization_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_authorization_id_key UNIQUE (authorization_id);


--
-- Name: oauth_authorizations oauth_authorizations_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_pkey PRIMARY KEY (id);


--
-- Name: oauth_client_states oauth_client_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_client_states
    ADD CONSTRAINT oauth_client_states_pkey PRIMARY KEY (id);


--
-- Name: oauth_clients oauth_clients_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_clients
    ADD CONSTRAINT oauth_clients_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_pkey PRIMARY KEY (id);


--
-- Name: oauth_consents oauth_consents_user_client_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_client_unique UNIQUE (user_id, client_id);


--
-- Name: one_time_tokens one_time_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_pkey PRIMARY KEY (id);


--
-- Name: refresh_tokens refresh_tokens_token_unique; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_token_unique UNIQUE (token);


--
-- Name: saml_providers saml_providers_entity_id_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_entity_id_key UNIQUE (entity_id);


--
-- Name: saml_providers saml_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_pkey PRIMARY KEY (id);


--
-- Name: saml_relay_states saml_relay_states_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: scim_tokens scim_tokens_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.scim_tokens
    ADD CONSTRAINT scim_tokens_pkey PRIMARY KEY (id);


--
-- Name: scim_users scim_users_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.scim_users
    ADD CONSTRAINT scim_users_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sso_domains sso_domains_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_pkey PRIMARY KEY (id);


--
-- Name: sso_providers sso_providers_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_providers
    ADD CONSTRAINT sso_providers_pkey PRIMARY KEY (id);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: webauthn_challenges webauthn_challenges_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.webauthn_challenges
    ADD CONSTRAINT webauthn_challenges_pkey PRIMARY KEY (id);


--
-- Name: webauthn_credentials webauthn_credentials_pkey; Type: CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.webauthn_credentials
    ADD CONSTRAINT webauthn_credentials_pkey PRIMARY KEY (id);


--
-- Name: admin_audit_logs admin_audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_audit_logs
    ADD CONSTRAINT admin_audit_logs_pkey PRIMARY KEY (id);


--
-- Name: cart_items cart_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_pkey PRIMARY KEY (id);


--
-- Name: cart_items cart_items_user_product_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_user_product_key UNIQUE (user_id, product_id);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: coupon_redemptions coupon_redemptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupon_redemptions
    ADD CONSTRAINT coupon_redemptions_pkey PRIMARY KEY (id);


--
-- Name: coupons coupons_code_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_code_unique UNIQUE (code);


--
-- Name: coupons coupons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_pkey PRIMARY KEY (id);


--
-- Name: customer_addresses customer_addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_addresses
    ADD CONSTRAINT customer_addresses_pkey PRIMARY KEY (id);


--
-- Name: customer_preferences customer_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_preferences
    ADD CONSTRAINT customer_preferences_pkey PRIMARY KEY (user_id);


--
-- Name: gift_card_transactions gift_card_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gift_card_transactions
    ADD CONSTRAINT gift_card_transactions_pkey PRIMARY KEY (id);


--
-- Name: gift_cards gift_cards_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gift_cards
    ADD CONSTRAINT gift_cards_code_key UNIQUE (code);


--
-- Name: gift_cards gift_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gift_cards
    ADD CONSTRAINT gift_cards_pkey PRIMARY KEY (id);


--
-- Name: loyalty_accounts loyalty_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_accounts
    ADD CONSTRAINT loyalty_accounts_pkey PRIMARY KEY (user_id);


--
-- Name: loyalty_accounts loyalty_accounts_referral_code_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_accounts
    ADD CONSTRAINT loyalty_accounts_referral_code_unique UNIQUE (referral_code);


--
-- Name: loyalty_rules loyalty_rules_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_rules
    ADD CONSTRAINT loyalty_rules_code_key UNIQUE (code);


--
-- Name: loyalty_rules loyalty_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_rules
    ADD CONSTRAINT loyalty_rules_pkey PRIMARY KEY (id);


--
-- Name: loyalty_transactions loyalty_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_transactions
    ADD CONSTRAINT loyalty_transactions_pkey PRIMARY KEY (id);


--
-- Name: notification_deliveries notification_deliveries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_deliveries
    ADD CONSTRAINT notification_deliveries_pkey PRIMARY KEY (id);


--
-- Name: notification_events notification_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events
    ADD CONSTRAINT notification_events_pkey PRIMARY KEY (id);


--
-- Name: notification_preferences notification_preferences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_preferences
    ADD CONSTRAINT notification_preferences_pkey PRIMARY KEY (user_id);


--
-- Name: notification_templates notification_templates_code_channel_unique; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_templates
    ADD CONSTRAINT notification_templates_code_channel_unique UNIQUE (code, channel);


--
-- Name: notification_templates notification_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_templates
    ADD CONSTRAINT notification_templates_pkey PRIMARY KEY (id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: order_events order_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_events
    ADD CONSTRAINT order_events_pkey PRIMARY KEY (id);


--
-- Name: order_items order_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_pkey PRIMARY KEY (id);


--
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (id);


--
-- Name: payment_events payment_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_events
    ADD CONSTRAINT payment_events_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: pickup_locations pickup_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pickup_locations
    ADD CONSTRAINT pickup_locations_pkey PRIMARY KEY (id);


--
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: promotion_rules promotion_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotion_rules
    ADD CONSTRAINT promotion_rules_pkey PRIMARY KEY (id);


--
-- Name: promotions promotions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_pkey PRIMARY KEY (id);


--
-- Name: referrals referrals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_pkey PRIMARY KEY (id);


--
-- Name: reward_events reward_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reward_events
    ADD CONSTRAINT reward_events_pkey PRIMARY KEY (id);


--
-- Name: wishlists wishlists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wishlists
    ADD CONSTRAINT wishlists_pkey PRIMARY KEY (id);


--
-- Name: wishlists wishlists_user_product_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wishlists
    ADD CONSTRAINT wishlists_user_product_key UNIQUE (user_id, product_id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_09_21 messages_2026_09_21_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_09_21
    ADD CONSTRAINT messages_2026_09_21_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_09_22 messages_2026_09_22_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_09_22
    ADD CONSTRAINT messages_2026_09_22_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_09_23 messages_2026_09_23_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_09_23
    ADD CONSTRAINT messages_2026_09_23_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_09_24 messages_2026_09_24_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_09_24
    ADD CONSTRAINT messages_2026_09_24_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_09_25 messages_2026_09_25_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_09_25
    ADD CONSTRAINT messages_2026_09_25_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_09_26 messages_2026_09_26_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_09_26
    ADD CONSTRAINT messages_2026_09_26_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_09_27 messages_2026_09_27_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_09_27
    ADD CONSTRAINT messages_2026_09_27_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages_2026_09_28 messages_2026_09_28_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.messages_2026_09_28
    ADD CONSTRAINT messages_2026_09_28_pkey PRIMARY KEY (id, inserted_at);


--
-- Name: messages messages_payload_exclusive; Type: CHECK CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE realtime.messages
    ADD CONSTRAINT messages_payload_exclusive CHECK (((payload IS NULL) OR (binary_payload IS NULL))) NOT VALID;


--
-- Name: subscription pk_subscription; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.subscription
    ADD CONSTRAINT pk_subscription PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: realtime; Owner: -
--

ALTER TABLE ONLY realtime.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: buckets_analytics buckets_analytics_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets_analytics
    ADD CONSTRAINT buckets_analytics_pkey PRIMARY KEY (id);


--
-- Name: buckets buckets_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets
    ADD CONSTRAINT buckets_pkey PRIMARY KEY (id);


--
-- Name: buckets_vectors buckets_vectors_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.buckets_vectors
    ADD CONSTRAINT buckets_vectors_pkey PRIMARY KEY (id);


--
-- Name: migrations migrations_name_key; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_name_key UNIQUE (name);


--
-- Name: migrations migrations_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.migrations
    ADD CONSTRAINT migrations_pkey PRIMARY KEY (id);


--
-- Name: objects objects_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT objects_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_pkey PRIMARY KEY (id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_pkey PRIMARY KEY (id);


--
-- Name: vector_indexes vector_indexes_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: supabase_migrations; Owner: -
--

ALTER TABLE ONLY supabase_migrations.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: audit_logs_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX audit_logs_instance_id_idx ON auth.audit_log_entries USING btree (instance_id);


--
-- Name: confirmation_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX confirmation_token_idx ON auth.users USING btree (confirmation_token) WHERE ((confirmation_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: custom_oauth_providers_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_created_at_idx ON auth.custom_oauth_providers USING btree (created_at);


--
-- Name: custom_oauth_providers_enabled_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_enabled_idx ON auth.custom_oauth_providers USING btree (enabled);


--
-- Name: custom_oauth_providers_identifier_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_identifier_idx ON auth.custom_oauth_providers USING btree (identifier);


--
-- Name: custom_oauth_providers_provider_type_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX custom_oauth_providers_provider_type_idx ON auth.custom_oauth_providers USING btree (provider_type);


--
-- Name: email_change_token_current_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX email_change_token_current_idx ON auth.users USING btree (email_change_token_current) WHERE ((email_change_token_current)::text !~ '^[0-9 ]*$'::text);


--
-- Name: email_change_token_new_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX email_change_token_new_idx ON auth.users USING btree (email_change_token_new) WHERE ((email_change_token_new)::text !~ '^[0-9 ]*$'::text);


--
-- Name: factor_id_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX factor_id_created_at_idx ON auth.mfa_factors USING btree (user_id, created_at);


--
-- Name: flow_state_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX flow_state_created_at_idx ON auth.flow_state USING btree (created_at DESC);


--
-- Name: identities_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX identities_email_idx ON auth.identities USING btree (email text_pattern_ops);


--
-- Name: INDEX identities_email_idx; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON INDEX auth.identities_email_idx IS 'Auth: Ensures indexed queries on the email column';


--
-- Name: identities_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX identities_user_id_idx ON auth.identities USING btree (user_id);


--
-- Name: idx_auth_code; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_auth_code ON auth.flow_state USING btree (auth_code);


--
-- Name: idx_oauth_client_states_created_at; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_oauth_client_states_created_at ON auth.oauth_client_states USING btree (created_at);


--
-- Name: idx_user_id_auth_method; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_user_id_auth_method ON auth.flow_state USING btree (user_id, authentication_method);


--
-- Name: idx_users_created_at_desc; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_users_created_at_desc ON auth.users USING btree (created_at DESC);


--
-- Name: idx_users_email; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_users_email ON auth.users USING btree (email);


--
-- Name: idx_users_last_sign_in_at_desc; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_users_last_sign_in_at_desc ON auth.users USING btree (last_sign_in_at DESC);


--
-- Name: idx_users_name; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX idx_users_name ON auth.users USING btree (((raw_user_meta_data ->> 'name'::text))) WHERE ((raw_user_meta_data ->> 'name'::text) IS NOT NULL);


--
-- Name: mfa_challenge_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX mfa_challenge_created_at_idx ON auth.mfa_challenges USING btree (created_at DESC);


--
-- Name: mfa_factors_user_friendly_name_unique; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX mfa_factors_user_friendly_name_unique ON auth.mfa_factors USING btree (friendly_name, user_id) WHERE (TRIM(BOTH FROM friendly_name) <> ''::text);


--
-- Name: mfa_factors_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX mfa_factors_user_id_idx ON auth.mfa_factors USING btree (user_id);


--
-- Name: mfa_recovery_codes_set_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX mfa_recovery_codes_set_id_idx ON auth.mfa_recovery_codes USING btree (mfa_recovery_code_set_id);


--
-- Name: oauth_auth_pending_exp_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_auth_pending_exp_idx ON auth.oauth_authorizations USING btree (expires_at) WHERE (status = 'pending'::auth.oauth_authorization_status);


--
-- Name: oauth_clients_deleted_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_clients_deleted_at_idx ON auth.oauth_clients USING btree (deleted_at);


--
-- Name: oauth_consents_active_client_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_active_client_idx ON auth.oauth_consents USING btree (client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_active_user_client_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_active_user_client_idx ON auth.oauth_consents USING btree (user_id, client_id) WHERE (revoked_at IS NULL);


--
-- Name: oauth_consents_user_order_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX oauth_consents_user_order_idx ON auth.oauth_consents USING btree (user_id, granted_at DESC);


--
-- Name: one_time_tokens_relates_to_hash_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX one_time_tokens_relates_to_hash_idx ON auth.one_time_tokens USING hash (relates_to);


--
-- Name: one_time_tokens_token_hash_hash_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX one_time_tokens_token_hash_hash_idx ON auth.one_time_tokens USING hash (token_hash);


--
-- Name: one_time_tokens_user_id_token_type_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX one_time_tokens_user_id_token_type_key ON auth.one_time_tokens USING btree (user_id, token_type);


--
-- Name: reauthentication_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX reauthentication_token_idx ON auth.users USING btree (reauthentication_token) WHERE ((reauthentication_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: recovery_token_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX recovery_token_idx ON auth.users USING btree (recovery_token) WHERE ((recovery_token)::text !~ '^[0-9 ]*$'::text);


--
-- Name: refresh_tokens_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_instance_id_idx ON auth.refresh_tokens USING btree (instance_id);


--
-- Name: refresh_tokens_instance_id_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_instance_id_user_id_idx ON auth.refresh_tokens USING btree (instance_id, user_id);


--
-- Name: refresh_tokens_parent_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_parent_idx ON auth.refresh_tokens USING btree (parent);


--
-- Name: refresh_tokens_session_id_revoked_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_session_id_revoked_idx ON auth.refresh_tokens USING btree (session_id, revoked);


--
-- Name: refresh_tokens_updated_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX refresh_tokens_updated_at_idx ON auth.refresh_tokens USING btree (updated_at DESC);


--
-- Name: saml_providers_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_providers_sso_provider_id_idx ON auth.saml_providers USING btree (sso_provider_id);


--
-- Name: saml_relay_states_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_created_at_idx ON auth.saml_relay_states USING btree (created_at DESC);


--
-- Name: saml_relay_states_for_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_for_email_idx ON auth.saml_relay_states USING btree (for_email);


--
-- Name: saml_relay_states_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX saml_relay_states_sso_provider_id_idx ON auth.saml_relay_states USING btree (sso_provider_id);


--
-- Name: scim_tokens_expires_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_tokens_expires_at_idx ON auth.scim_tokens USING btree (expires_at);


--
-- Name: scim_tokens_revoked_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_tokens_revoked_at_idx ON auth.scim_tokens USING btree (revoked_at);


--
-- Name: scim_tokens_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_tokens_sso_provider_id_idx ON auth.scim_tokens USING btree (sso_provider_id);


--
-- Name: scim_tokens_token_hash_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX scim_tokens_token_hash_key ON auth.scim_tokens USING btree (token_hash);


--
-- Name: scim_users_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_created_at_idx ON auth.scim_users USING btree (sso_provider_id, created_at, id) WHERE (deleted_at IS NULL);


--
-- Name: scim_users_deleted_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_deleted_at_idx ON auth.scim_users USING btree (deleted_at);


--
-- Name: scim_users_external_id_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX scim_users_external_id_key ON auth.scim_users USING btree (sso_provider_id, external_id) WHERE ((external_id IS NOT NULL) AND (deleted_at IS NULL));


--
-- Name: scim_users_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_id_idx ON auth.scim_users USING btree (sso_provider_id, id) WHERE (deleted_at IS NULL);


--
-- Name: scim_users_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_sso_provider_id_idx ON auth.scim_users USING btree (sso_provider_id);


--
-- Name: scim_users_updated_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_updated_at_idx ON auth.scim_users USING btree (sso_provider_id, updated_at, id) WHERE (deleted_at IS NULL);


--
-- Name: scim_users_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_user_id_idx ON auth.scim_users USING btree (user_id);


--
-- Name: scim_users_user_name_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX scim_users_user_name_idx ON auth.scim_users USING btree (sso_provider_id, user_name COLLATE "C", id) WHERE (deleted_at IS NULL);


--
-- Name: scim_users_user_name_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX scim_users_user_name_key ON auth.scim_users USING btree (sso_provider_id, user_name) WHERE (deleted_at IS NULL);


--
-- Name: sessions_not_after_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_not_after_idx ON auth.sessions USING btree (not_after DESC);


--
-- Name: sessions_oauth_client_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_oauth_client_id_idx ON auth.sessions USING btree (oauth_client_id);


--
-- Name: sessions_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sessions_user_id_idx ON auth.sessions USING btree (user_id);


--
-- Name: sso_domains_domain_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX sso_domains_domain_idx ON auth.sso_domains USING btree (lower(domain));


--
-- Name: sso_domains_sso_provider_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sso_domains_sso_provider_id_idx ON auth.sso_domains USING btree (sso_provider_id);


--
-- Name: sso_providers_resource_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX sso_providers_resource_id_idx ON auth.sso_providers USING btree (lower(resource_id));


--
-- Name: sso_providers_resource_id_pattern_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX sso_providers_resource_id_pattern_idx ON auth.sso_providers USING btree (resource_id text_pattern_ops);


--
-- Name: unique_phone_factor_per_user; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX unique_phone_factor_per_user ON auth.mfa_factors USING btree (user_id, phone);


--
-- Name: user_id_created_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX user_id_created_at_idx ON auth.sessions USING btree (user_id, created_at);


--
-- Name: users_email_partial_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX users_email_partial_key ON auth.users USING btree (email) WHERE (is_sso_user = false);


--
-- Name: INDEX users_email_partial_key; Type: COMMENT; Schema: auth; Owner: -
--

COMMENT ON INDEX auth.users_email_partial_key IS 'Auth: A partial unique index that applies only when is_sso_user is false';


--
-- Name: users_instance_id_email_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_instance_id_email_idx ON auth.users USING btree (instance_id, lower((email)::text));


--
-- Name: users_instance_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_instance_id_idx ON auth.users USING btree (instance_id);


--
-- Name: users_is_anonymous_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX users_is_anonymous_idx ON auth.users USING btree (is_anonymous);


--
-- Name: webauthn_challenges_expires_at_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX webauthn_challenges_expires_at_idx ON auth.webauthn_challenges USING btree (expires_at);


--
-- Name: webauthn_challenges_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX webauthn_challenges_user_id_idx ON auth.webauthn_challenges USING btree (user_id);


--
-- Name: webauthn_credentials_credential_id_key; Type: INDEX; Schema: auth; Owner: -
--

CREATE UNIQUE INDEX webauthn_credentials_credential_id_key ON auth.webauthn_credentials USING btree (credential_id);


--
-- Name: webauthn_credentials_user_id_idx; Type: INDEX; Schema: auth; Owner: -
--

CREATE INDEX webauthn_credentials_user_id_idx ON auth.webauthn_credentials USING btree (user_id);


--
-- Name: idx_admin_audit_logs_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_audit_logs_actor ON public.admin_audit_logs USING btree (actor_id, created_at DESC);


--
-- Name: idx_admin_audit_logs_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_audit_logs_created ON public.admin_audit_logs USING btree (created_at DESC);


--
-- Name: idx_admin_audit_logs_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_admin_audit_logs_entity ON public.admin_audit_logs USING btree (entity_type, entity_id);


--
-- Name: idx_cart_items_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cart_items_product_id ON public.cart_items USING btree (product_id);


--
-- Name: idx_categories_slug_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_categories_slug_unique ON public.categories USING btree (slug) WHERE ((slug IS NOT NULL) AND (TRIM(BOTH FROM slug) <> ''::text));


--
-- Name: idx_coupon_redemptions_coupon_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_coupon_redemptions_coupon_user ON public.coupon_redemptions USING btree (coupon_id, user_id);


--
-- Name: idx_coupon_redemptions_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_coupon_redemptions_order ON public.coupon_redemptions USING btree (order_id);


--
-- Name: idx_coupons_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_coupons_active ON public.coupons USING btree (is_active, starts_at, ends_at);


--
-- Name: idx_customer_addresses_user_default; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_addresses_user_default ON public.customer_addresses USING btree (user_id, is_default) WHERE (is_default = true);


--
-- Name: idx_customer_addresses_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_customer_addresses_user_id ON public.customer_addresses USING btree (user_id);


--
-- Name: idx_gift_card_transactions_card; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gift_card_transactions_card ON public.gift_card_transactions USING btree (gift_card_id, created_at DESC);


--
-- Name: idx_gift_cards_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_gift_cards_status ON public.gift_cards USING btree (status);


--
-- Name: idx_loyalty_transactions_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_loyalty_transactions_user_created ON public.loyalty_transactions USING btree (user_id, created_at DESC);


--
-- Name: idx_notification_deliveries_notification_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_deliveries_notification_id ON public.notification_deliveries USING btree (notification_id);


--
-- Name: idx_notification_deliveries_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_deliveries_status ON public.notification_deliveries USING btree (status);


--
-- Name: idx_notification_deliveries_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_deliveries_user_created ON public.notification_deliveries USING btree (user_id, created_at DESC);


--
-- Name: idx_notification_events_type_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_events_type_created ON public.notification_events USING btree (event_type, created_at DESC);


--
-- Name: idx_notification_events_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_events_user_created ON public.notification_events USING btree (user_id, created_at DESC);


--
-- Name: idx_notification_templates_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notification_templates_code ON public.notification_templates USING btree (code);


--
-- Name: idx_notifications_audience_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_audience_created ON public.notifications USING btree (audience, created_at DESC) WHERE (audience = 'admin'::text);


--
-- Name: idx_notifications_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_event_type ON public.notifications USING btree (event_type);


--
-- Name: idx_notifications_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_user_created ON public.notifications USING btree (user_id, created_at DESC);


--
-- Name: idx_notifications_user_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_user_status ON public.notifications USING btree (user_id, status);


--
-- Name: idx_order_events_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_events_order_id ON public.order_events USING btree (order_id, created_at DESC);


--
-- Name: idx_order_items_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_items_order_id ON public.order_items USING btree (order_id);


--
-- Name: idx_order_items_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_order_items_product_id ON public.order_items USING btree (product_id);


--
-- Name: idx_orders_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_created_at ON public.orders USING btree (created_at DESC);


--
-- Name: idx_orders_payment_method; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_payment_method ON public.orders USING btree (payment_method);


--
-- Name: idx_orders_payment_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_payment_status ON public.orders USING btree (payment_status);


--
-- Name: idx_orders_pickup_location_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_pickup_location_id ON public.orders USING btree (pickup_location_id) WHERE (pickup_location_id IS NOT NULL);


--
-- Name: idx_orders_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_status ON public.orders USING btree (status);


--
-- Name: idx_orders_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_orders_user_id ON public.orders USING btree (user_id);


--
-- Name: idx_payment_events_payment_id_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payment_events_payment_id_created ON public.payment_events USING btree (payment_id, created_at);


--
-- Name: idx_payments_checkout_request_id_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_payments_checkout_request_id_unique ON public.payments USING btree (checkout_request_id) WHERE (checkout_request_id IS NOT NULL);


--
-- Name: idx_payments_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_created_at ON public.payments USING btree (created_at DESC);


--
-- Name: idx_payments_merchant_request_id_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_payments_merchant_request_id_unique ON public.payments USING btree (merchant_request_id) WHERE (merchant_request_id IS NOT NULL);


--
-- Name: idx_payments_order_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_order_id ON public.payments USING btree (order_id);


--
-- Name: idx_payments_receipt_number_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_payments_receipt_number_unique ON public.payments USING btree (receipt_number) WHERE (receipt_number IS NOT NULL);


--
-- Name: idx_payments_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_status ON public.payments USING btree (status);


--
-- Name: idx_payments_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_user_id ON public.payments USING btree (user_id);


--
-- Name: idx_pickup_locations_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_pickup_locations_is_active ON public.pickup_locations USING btree (is_active) WHERE (is_active = true);


--
-- Name: idx_products_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_category_id ON public.products USING btree (category_id);


--
-- Name: idx_products_is_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_is_active ON public.products USING btree (is_active);


--
-- Name: idx_products_search; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_products_search ON public.products USING gin (to_tsvector('simple'::regconfig, ((COALESCE(name, ''::text) || ' '::text) || COALESCE(description, ''::text))));


--
-- Name: idx_products_slug_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_products_slug_unique ON public.products USING btree (slug) WHERE ((slug IS NOT NULL) AND (TRIM(BOTH FROM slug) <> ''::text));


--
-- Name: idx_promotion_rules_promotion_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promotion_rules_promotion_id ON public.promotion_rules USING btree (promotion_id);


--
-- Name: idx_promotions_code_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_promotions_code_unique ON public.promotions USING btree (lower(code)) WHERE (code IS NOT NULL);


--
-- Name: idx_promotions_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promotions_dates ON public.promotions USING btree (starts_at, ends_at);


--
-- Name: idx_promotions_status_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_promotions_status_priority ON public.promotions USING btree (status, priority DESC);


--
-- Name: idx_referrals_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_referrals_code ON public.referrals USING btree (referral_code);


--
-- Name: idx_referrals_referred_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_referrals_referred_user ON public.referrals USING btree (referred_user_id) WHERE (referred_user_id IS NOT NULL);


--
-- Name: idx_referrals_referrer; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_referrals_referrer ON public.referrals USING btree (referrer_user_id);


--
-- Name: idx_reward_events_user_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reward_events_user_created ON public.reward_events USING btree (user_id, created_at DESC);


--
-- Name: idx_wishlists_product_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wishlists_product_id ON public.wishlists USING btree (product_id);


--
-- Name: ix_realtime_subscription_entity; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX ix_realtime_subscription_entity ON realtime.subscription USING btree (entity);


--
-- Name: messages_inserted_at_topic_index; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_inserted_at_topic_index ON ONLY realtime.messages USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_09_21_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_09_21_inserted_at_topic_idx ON realtime.messages_2026_09_21 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_09_22_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_09_22_inserted_at_topic_idx ON realtime.messages_2026_09_22 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_09_23_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_09_23_inserted_at_topic_idx ON realtime.messages_2026_09_23 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_09_24_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_09_24_inserted_at_topic_idx ON realtime.messages_2026_09_24 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_09_25_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_09_25_inserted_at_topic_idx ON realtime.messages_2026_09_25 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_09_26_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_09_26_inserted_at_topic_idx ON realtime.messages_2026_09_26 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_09_27_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_09_27_inserted_at_topic_idx ON realtime.messages_2026_09_27 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: messages_2026_09_28_inserted_at_topic_idx; Type: INDEX; Schema: realtime; Owner: -
--

CREATE INDEX messages_2026_09_28_inserted_at_topic_idx ON realtime.messages_2026_09_28 USING btree (inserted_at DESC, topic) WHERE ((extension = 'broadcast'::text) AND (private IS TRUE));


--
-- Name: subscription_subscription_id_entity_filters_action_filter_selec; Type: INDEX; Schema: realtime; Owner: -
--

CREATE UNIQUE INDEX subscription_subscription_id_entity_filters_action_filter_selec ON realtime.subscription USING btree (subscription_id, entity, filters, action_filter, COALESCE(selected_columns, '{}'::text[]));


--
-- Name: bname; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX bname ON storage.buckets USING btree (name);


--
-- Name: buckets_analytics_unique_name_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX buckets_analytics_unique_name_idx ON storage.buckets_analytics USING btree (name) WHERE (deleted_at IS NULL);


--
-- Name: idx_multipart_uploads_list; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_multipart_uploads_list ON storage.s3_multipart_uploads USING btree (bucket_id, key, created_at);


--
-- Name: idx_objects_bucket_id_name; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_bucket_id_name ON storage.objects USING btree (bucket_id, name COLLATE "C");


--
-- Name: idx_objects_bucket_id_name_lower; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_bucket_id_name_lower ON storage.objects USING btree (bucket_id, lower(name) COLLATE "C");


--
-- Name: idx_objects_current_version; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX idx_objects_current_version ON storage.objects USING btree (bucket_id, name COLLATE "C") WHERE (archived_at IS NULL);


--
-- Name: idx_objects_delete_markers; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX idx_objects_delete_markers ON storage.objects USING btree (bucket_id, name COLLATE "C") WHERE is_delete_marker;


--
-- Name: idx_objects_null_version; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX idx_objects_null_version ON storage.objects USING btree (bucket_id, name COLLATE "C") WHERE (NOT is_versioned);


--
-- Name: name_prefix_search; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX name_prefix_search ON storage.objects USING btree (name text_pattern_ops);


--
-- Name: objects_bucket_id_name_version_key; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX objects_bucket_id_name_version_key ON storage.objects USING btree (bucket_id, name COLLATE "C", version) NULLS NOT DISTINCT;


--
-- Name: vector_indexes_name_bucket_id_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX vector_indexes_name_bucket_id_idx ON storage.vector_indexes USING btree (name, bucket_id);


--
-- Name: messages_2026_09_21_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_09_21_inserted_at_topic_idx;


--
-- Name: messages_2026_09_21_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_09_21_pkey;


--
-- Name: messages_2026_09_22_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_09_22_inserted_at_topic_idx;


--
-- Name: messages_2026_09_22_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_09_22_pkey;


--
-- Name: messages_2026_09_23_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_09_23_inserted_at_topic_idx;


--
-- Name: messages_2026_09_23_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_09_23_pkey;


--
-- Name: messages_2026_09_24_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_09_24_inserted_at_topic_idx;


--
-- Name: messages_2026_09_24_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_09_24_pkey;


--
-- Name: messages_2026_09_25_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_09_25_inserted_at_topic_idx;


--
-- Name: messages_2026_09_25_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_09_25_pkey;


--
-- Name: messages_2026_09_26_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_09_26_inserted_at_topic_idx;


--
-- Name: messages_2026_09_26_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_09_26_pkey;


--
-- Name: messages_2026_09_27_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_09_27_inserted_at_topic_idx;


--
-- Name: messages_2026_09_27_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_09_27_pkey;


--
-- Name: messages_2026_09_28_inserted_at_topic_idx; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_inserted_at_topic_index ATTACH PARTITION realtime.messages_2026_09_28_inserted_at_topic_idx;


--
-- Name: messages_2026_09_28_pkey; Type: INDEX ATTACH; Schema: realtime; Owner: -
--

ALTER INDEX realtime.messages_pkey ATTACH PARTITION realtime.messages_2026_09_28_pkey;


--
-- Name: users on_auth_user_created; Type: TRIGGER; Schema: auth; Owner: -
--

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


--
-- Name: coupons coupons_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER coupons_set_updated_at BEFORE UPDATE ON public.coupons FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: customer_addresses customer_addresses_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER customer_addresses_set_updated_at BEFORE UPDATE ON public.customer_addresses FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: customer_addresses customer_addresses_single_default; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER customer_addresses_single_default AFTER INSERT OR UPDATE OF is_default ON public.customer_addresses FOR EACH ROW WHEN ((new.is_default = true)) EXECUTE FUNCTION public.enforce_single_default_address();


--
-- Name: customer_preferences customer_preferences_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER customer_preferences_set_updated_at BEFORE UPDATE ON public.customer_preferences FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: gift_cards gift_cards_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER gift_cards_set_updated_at BEFORE UPDATE ON public.gift_cards FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: loyalty_accounts loyalty_accounts_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER loyalty_accounts_set_updated_at BEFORE UPDATE ON public.loyalty_accounts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: loyalty_rules loyalty_rules_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER loyalty_rules_set_updated_at BEFORE UPDATE ON public.loyalty_rules FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: notification_deliveries notification_deliveries_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notification_deliveries_set_updated_at BEFORE UPDATE ON public.notification_deliveries FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: notification_preferences notification_preferences_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notification_preferences_set_updated_at BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: notification_templates notification_templates_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notification_templates_set_updated_at BEFORE UPDATE ON public.notification_templates FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: notifications notifications_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER notifications_set_updated_at BEFORE UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: orders orders_guard_sensitive_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER orders_guard_sensitive_update BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.guard_orders_direct_update();


--
-- Name: payments payments_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payments_set_updated_at BEFORE UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: promotions promotions_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER promotions_set_updated_at BEFORE UPDATE ON public.promotions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: referrals referrals_set_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER referrals_set_updated_at BEFORE UPDATE ON public.referrals FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: orders set_orders_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_orders_updated_at BEFORE UPDATE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: products set_products_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_products_updated_at BEFORE UPDATE ON public.products FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: profiles set_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER set_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: subscription tr_check_filters; Type: TRIGGER; Schema: realtime; Owner: -
--

CREATE TRIGGER tr_check_filters BEFORE INSERT OR UPDATE ON realtime.subscription FOR EACH ROW EXECUTE FUNCTION realtime.subscription_check_filters();


--
-- Name: buckets enforce_bucket_name_length_trigger; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER enforce_bucket_name_length_trigger BEFORE INSERT OR UPDATE OF name ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_name_length();


--
-- Name: buckets protect_bucket_control_insert; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_bucket_control_insert BEFORE INSERT ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.protect_bucket_control_columns('service_role');


--
-- Name: buckets protect_bucket_control_update; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_bucket_control_update BEFORE UPDATE OF lifecycle_configuration, lifecycle_configuration_generation ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.protect_bucket_control_columns();


--
-- Name: buckets protect_bucket_control_update_role; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_bucket_control_update_role AFTER UPDATE OF lifecycle_configuration, lifecycle_configuration_generation ON storage.buckets FOR EACH ROW EXECUTE FUNCTION storage.enforce_bucket_lifecycle_service_role('service_role');


--
-- Name: buckets protect_buckets_delete; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_buckets_delete BEFORE DELETE ON storage.buckets FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects protect_objects_delete; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER protect_objects_delete BEFORE DELETE ON storage.objects FOR EACH STATEMENT EXECUTE FUNCTION storage.protect_delete();


--
-- Name: objects update_objects_updated_at; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER update_objects_updated_at BEFORE UPDATE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.update_updated_at_column();


--
-- Name: identities identities_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.identities
    ADD CONSTRAINT identities_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mfa_amr_claims mfa_amr_claims_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_amr_claims
    ADD CONSTRAINT mfa_amr_claims_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: mfa_challenges mfa_challenges_auth_factor_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_challenges
    ADD CONSTRAINT mfa_challenges_auth_factor_id_fkey FOREIGN KEY (factor_id) REFERENCES auth.mfa_factors(id) ON DELETE CASCADE;


--
-- Name: mfa_factors mfa_factors_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_factors
    ADD CONSTRAINT mfa_factors_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mfa_recovery_code_sets mfa_recovery_code_sets_mfa_factor_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_code_sets
    ADD CONSTRAINT mfa_recovery_code_sets_mfa_factor_id_fkey FOREIGN KEY (mfa_factor_id) REFERENCES auth.mfa_factors(id) ON DELETE CASCADE;


--
-- Name: mfa_recovery_code_sets mfa_recovery_code_sets_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_code_sets
    ADD CONSTRAINT mfa_recovery_code_sets_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: mfa_recovery_codes mfa_recovery_codes_mfa_recovery_code_set_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.mfa_recovery_codes
    ADD CONSTRAINT mfa_recovery_codes_mfa_recovery_code_set_id_fkey FOREIGN KEY (mfa_recovery_code_set_id) REFERENCES auth.mfa_recovery_code_sets(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_authorizations oauth_authorizations_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_authorizations
    ADD CONSTRAINT oauth_authorizations_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_client_id_fkey FOREIGN KEY (client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: oauth_consents oauth_consents_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.oauth_consents
    ADD CONSTRAINT oauth_consents_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: one_time_tokens one_time_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.one_time_tokens
    ADD CONSTRAINT one_time_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: refresh_tokens refresh_tokens_session_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.refresh_tokens
    ADD CONSTRAINT refresh_tokens_session_id_fkey FOREIGN KEY (session_id) REFERENCES auth.sessions(id) ON DELETE CASCADE;


--
-- Name: saml_providers saml_providers_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_providers
    ADD CONSTRAINT saml_providers_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_flow_state_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_flow_state_id_fkey FOREIGN KEY (flow_state_id) REFERENCES auth.flow_state(id) ON DELETE CASCADE;


--
-- Name: saml_relay_states saml_relay_states_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.saml_relay_states
    ADD CONSTRAINT saml_relay_states_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: scim_tokens scim_tokens_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.scim_tokens
    ADD CONSTRAINT scim_tokens_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: scim_users scim_users_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.scim_users
    ADD CONSTRAINT scim_users_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: scim_users scim_users_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.scim_users
    ADD CONSTRAINT scim_users_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: sessions sessions_oauth_client_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_oauth_client_id_fkey FOREIGN KEY (oauth_client_id) REFERENCES auth.oauth_clients(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sessions
    ADD CONSTRAINT sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: sso_domains sso_domains_sso_provider_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.sso_domains
    ADD CONSTRAINT sso_domains_sso_provider_id_fkey FOREIGN KEY (sso_provider_id) REFERENCES auth.sso_providers(id) ON DELETE CASCADE;


--
-- Name: webauthn_challenges webauthn_challenges_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.webauthn_challenges
    ADD CONSTRAINT webauthn_challenges_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: webauthn_credentials webauthn_credentials_user_id_fkey; Type: FK CONSTRAINT; Schema: auth; Owner: -
--

ALTER TABLE ONLY auth.webauthn_credentials
    ADD CONSTRAINT webauthn_credentials_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: admin_audit_logs admin_audit_logs_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.admin_audit_logs
    ADD CONSTRAINT admin_audit_logs_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: cart_items cart_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE NOT VALID;


--
-- Name: cart_items cart_items_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cart_items
    ADD CONSTRAINT cart_items_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;


--
-- Name: coupon_redemptions coupon_redemptions_coupon_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupon_redemptions
    ADD CONSTRAINT coupon_redemptions_coupon_id_fkey FOREIGN KEY (coupon_id) REFERENCES public.coupons(id) ON DELETE CASCADE;


--
-- Name: coupon_redemptions coupon_redemptions_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupon_redemptions
    ADD CONSTRAINT coupon_redemptions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE SET NULL;


--
-- Name: coupon_redemptions coupon_redemptions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupon_redemptions
    ADD CONSTRAINT coupon_redemptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: coupons coupons_promotion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coupons
    ADD CONSTRAINT coupons_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id) ON DELETE SET NULL;


--
-- Name: customer_addresses customer_addresses_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_addresses
    ADD CONSTRAINT customer_addresses_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: customer_preferences customer_preferences_preferred_pickup_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_preferences
    ADD CONSTRAINT customer_preferences_preferred_pickup_location_id_fkey FOREIGN KEY (preferred_pickup_location_id) REFERENCES public.pickup_locations(id) ON DELETE SET NULL;


--
-- Name: customer_preferences customer_preferences_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.customer_preferences
    ADD CONSTRAINT customer_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: gift_card_transactions gift_card_transactions_gift_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gift_card_transactions
    ADD CONSTRAINT gift_card_transactions_gift_card_id_fkey FOREIGN KEY (gift_card_id) REFERENCES public.gift_cards(id) ON DELETE CASCADE;


--
-- Name: gift_card_transactions gift_card_transactions_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gift_card_transactions
    ADD CONSTRAINT gift_card_transactions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE SET NULL;


--
-- Name: gift_card_transactions gift_card_transactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gift_card_transactions
    ADD CONSTRAINT gift_card_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: gift_cards gift_cards_purchased_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.gift_cards
    ADD CONSTRAINT gift_cards_purchased_by_fkey FOREIGN KEY (purchased_by) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: loyalty_accounts loyalty_accounts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_accounts
    ADD CONSTRAINT loyalty_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: loyalty_transactions loyalty_transactions_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_transactions
    ADD CONSTRAINT loyalty_transactions_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE SET NULL;


--
-- Name: loyalty_transactions loyalty_transactions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.loyalty_transactions
    ADD CONSTRAINT loyalty_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: notification_deliveries notification_deliveries_notification_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_deliveries
    ADD CONSTRAINT notification_deliveries_notification_id_fkey FOREIGN KEY (notification_id) REFERENCES public.notifications(id) ON DELETE SET NULL;


--
-- Name: notification_deliveries notification_deliveries_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_deliveries
    ADD CONSTRAINT notification_deliveries_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: notification_events notification_events_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_events
    ADD CONSTRAINT notification_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: notification_preferences notification_preferences_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_preferences
    ADD CONSTRAINT notification_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: order_events order_events_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_events
    ADD CONSTRAINT order_events_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: order_items order_items_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.order_items
    ADD CONSTRAINT order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE SET NULL NOT VALID;


--
-- Name: orders orders_pickup_location_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pickup_location_id_fkey FOREIGN KEY (pickup_location_id) REFERENCES public.pickup_locations(id) ON DELETE SET NULL;


--
-- Name: orders orders_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;


--
-- Name: payment_events payment_events_payment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payment_events
    ADD CONSTRAINT payment_events_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES public.payments(id) ON DELETE CASCADE;


--
-- Name: payments payments_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;


--
-- Name: payments payments_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: products products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE SET NULL;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: promotion_rules promotion_rules_promotion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotion_rules
    ADD CONSTRAINT promotion_rules_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(id) ON DELETE CASCADE;


--
-- Name: promotions promotions_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE SET NULL;


--
-- Name: referrals referrals_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE SET NULL;


--
-- Name: referrals referrals_referred_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_referred_user_id_fkey FOREIGN KEY (referred_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: referrals referrals_referrer_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.referrals
    ADD CONSTRAINT referrals_referrer_user_id_fkey FOREIGN KEY (referrer_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: reward_events reward_events_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reward_events
    ADD CONSTRAINT reward_events_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE SET NULL;


--
-- Name: reward_events reward_events_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reward_events
    ADD CONSTRAINT reward_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;


--
-- Name: wishlists wishlists_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wishlists
    ADD CONSTRAINT wishlists_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id) ON DELETE CASCADE NOT VALID;


--
-- Name: wishlists wishlists_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wishlists
    ADD CONSTRAINT wishlists_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE NOT VALID;


--
-- Name: objects objects_bucketId_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.objects
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads s3_multipart_uploads_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads
    ADD CONSTRAINT s3_multipart_uploads_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);


--
-- Name: s3_multipart_uploads_parts s3_multipart_uploads_parts_upload_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.s3_multipart_uploads_parts
    ADD CONSTRAINT s3_multipart_uploads_parts_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES storage.s3_multipart_uploads(id) ON DELETE CASCADE;


--
-- Name: vector_indexes vector_indexes_bucket_id_fkey; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.vector_indexes
    ADD CONSTRAINT vector_indexes_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets_vectors(id);


--
-- Name: audit_log_entries; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.audit_log_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: flow_state; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.flow_state ENABLE ROW LEVEL SECURITY;

--
-- Name: identities; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.identities ENABLE ROW LEVEL SECURITY;

--
-- Name: instances; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.instances ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_amr_claims; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_amr_claims ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_challenges; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_challenges ENABLE ROW LEVEL SECURITY;

--
-- Name: mfa_factors; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.mfa_factors ENABLE ROW LEVEL SECURITY;

--
-- Name: one_time_tokens; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.one_time_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: refresh_tokens; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.refresh_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_providers; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.saml_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: saml_relay_states; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.saml_relay_states ENABLE ROW LEVEL SECURITY;

--
-- Name: schema_migrations; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.schema_migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: sessions; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_domains; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sso_domains ENABLE ROW LEVEL SECURITY;

--
-- Name: sso_providers; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.sso_providers ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: auth; Owner: -
--

ALTER TABLE auth.users ENABLE ROW LEVEL SECURITY;

--
-- Name: orders Admins can view all orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Admins can view all orders" ON public.orders FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'admin'::text)))));


--
-- Name: products Allow public read access; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Allow public read access" ON public.products FOR SELECT USING (true);


--
-- Name: order_items Block direct insert order items; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Block direct insert order items" ON public.order_items FOR INSERT WITH CHECK (false);


--
-- Name: orders Users can view own orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own orders" ON public.orders FOR SELECT USING ((auth.uid() = user_id));


--
-- Name: admin_audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.admin_audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: admin_audit_logs admin_audit_logs_insert_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_audit_logs_insert_admin ON public.admin_audit_logs FOR INSERT TO authenticated WITH CHECK (public.is_admin());


--
-- Name: admin_audit_logs admin_audit_logs_select_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY admin_audit_logs_select_admin ON public.admin_audit_logs FOR SELECT TO authenticated USING (public.is_admin());


--
-- Name: cart_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;

--
-- Name: cart_items cart_items_all_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY cart_items_all_own ON public.cart_items USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: categories; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;

--
-- Name: categories categories_modify_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_modify_admin ON public.categories USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: categories categories_select_public; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY categories_select_public ON public.categories FOR SELECT USING (true);


--
-- Name: coupon_redemptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.coupon_redemptions ENABLE ROW LEVEL SECURITY;

--
-- Name: coupon_redemptions coupon_redemptions_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY coupon_redemptions_insert_own ON public.coupon_redemptions FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: coupon_redemptions coupon_redemptions_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY coupon_redemptions_select_own_or_admin ON public.coupon_redemptions FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: coupons; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;

--
-- Name: coupons coupons_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY coupons_admin_all ON public.coupons TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: coupons coupons_select_active_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY coupons_select_active_or_admin ON public.coupons FOR SELECT TO authenticated USING (((is_active = true) OR public.is_admin()));


--
-- Name: customer_addresses; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_addresses customer_addresses_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_addresses_delete_own ON public.customer_addresses FOR DELETE USING ((user_id = auth.uid()));


--
-- Name: customer_addresses customer_addresses_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_addresses_insert_own ON public.customer_addresses FOR INSERT WITH CHECK ((user_id = auth.uid()));


--
-- Name: customer_addresses customer_addresses_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_addresses_select_own ON public.customer_addresses FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: customer_addresses customer_addresses_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_addresses_update_own ON public.customer_addresses FOR UPDATE USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: customer_preferences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.customer_preferences ENABLE ROW LEVEL SECURITY;

--
-- Name: customer_preferences customer_preferences_delete_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_preferences_delete_own ON public.customer_preferences FOR DELETE USING ((user_id = auth.uid()));


--
-- Name: customer_preferences customer_preferences_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_preferences_insert_own ON public.customer_preferences FOR INSERT WITH CHECK ((user_id = auth.uid()));


--
-- Name: customer_preferences customer_preferences_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_preferences_select_own ON public.customer_preferences FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: customer_preferences customer_preferences_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY customer_preferences_update_own ON public.customer_preferences FOR UPDATE USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: gift_card_transactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gift_card_transactions ENABLE ROW LEVEL SECURITY;

--
-- Name: gift_card_transactions gift_card_transactions_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gift_card_transactions_select_own_or_admin ON public.gift_card_transactions FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: gift_cards; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.gift_cards ENABLE ROW LEVEL SECURITY;

--
-- Name: gift_cards gift_cards_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gift_cards_admin_all ON public.gift_cards TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: gift_cards gift_cards_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY gift_cards_select_own_or_admin ON public.gift_cards FOR SELECT TO authenticated USING (((purchased_by = auth.uid()) OR public.is_admin()));


--
-- Name: loyalty_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.loyalty_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: loyalty_accounts loyalty_accounts_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY loyalty_accounts_insert_own ON public.loyalty_accounts FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: loyalty_accounts loyalty_accounts_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY loyalty_accounts_select_own_or_admin ON public.loyalty_accounts FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: loyalty_accounts loyalty_accounts_update_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY loyalty_accounts_update_own_or_admin ON public.loyalty_accounts FOR UPDATE TO authenticated USING (((user_id = auth.uid()) OR public.is_admin())) WITH CHECK (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: loyalty_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.loyalty_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: loyalty_rules loyalty_rules_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY loyalty_rules_admin_all ON public.loyalty_rules TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: loyalty_rules loyalty_rules_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY loyalty_rules_select ON public.loyalty_rules FOR SELECT TO authenticated USING (((is_active = true) OR public.is_admin()));


--
-- Name: loyalty_transactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.loyalty_transactions ENABLE ROW LEVEL SECURITY;

--
-- Name: loyalty_transactions loyalty_transactions_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY loyalty_transactions_select_own_or_admin ON public.loyalty_transactions FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: notification_deliveries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;

--
-- Name: notification_deliveries notification_deliveries_insert_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_deliveries_insert_own_or_admin ON public.notification_deliveries FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: notification_deliveries notification_deliveries_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_deliveries_select_own_or_admin ON public.notification_deliveries FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: notification_deliveries notification_deliveries_update_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_deliveries_update_own_or_admin ON public.notification_deliveries FOR UPDATE TO authenticated USING (((user_id = auth.uid()) OR public.is_admin())) WITH CHECK (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: notification_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification_events ENABLE ROW LEVEL SECURITY;

--
-- Name: notification_events notification_events_insert_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_events_insert_authenticated ON public.notification_events FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) OR public.is_admin() OR (user_id IS NULL)));


--
-- Name: notification_events notification_events_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_events_select_own_or_admin ON public.notification_events FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.is_admin() OR (user_id IS NULL)));


--
-- Name: notification_preferences; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

--
-- Name: notification_preferences notification_preferences_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_preferences_insert_own ON public.notification_preferences FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));


--
-- Name: notification_preferences notification_preferences_select_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_preferences_select_own ON public.notification_preferences FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: notification_preferences notification_preferences_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_preferences_update_own ON public.notification_preferences FOR UPDATE TO authenticated USING ((user_id = auth.uid())) WITH CHECK ((user_id = auth.uid()));


--
-- Name: notification_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: notification_templates notification_templates_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_templates_admin_all ON public.notification_templates TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: notification_templates notification_templates_select_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notification_templates_select_authenticated ON public.notification_templates FOR SELECT TO authenticated USING (((is_active = true) OR public.is_admin()));


--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications notifications_insert_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_insert_own_or_admin ON public.notifications FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: notifications notifications_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_select_own_or_admin ON public.notifications FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: notifications notifications_update_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_update_own_or_admin ON public.notifications FOR UPDATE TO authenticated USING (((user_id = auth.uid()) OR public.is_admin())) WITH CHECK (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: order_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_events ENABLE ROW LEVEL SECURITY;

--
-- Name: order_events order_events_select_owner_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_events_select_owner_or_admin ON public.order_events FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.orders o
  WHERE ((o.id = order_events.order_id) AND ((o.user_id = auth.uid()) OR public.is_admin())))));


--
-- Name: order_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

--
-- Name: order_items order_items_select_owner_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY order_items_select_owner_or_admin ON public.order_items FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.orders o
  WHERE ((o.id = order_items.order_id) AND ((o.user_id = auth.uid()) OR public.is_admin())))));


--
-- Name: orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

--
-- Name: orders orders_update_admin_note; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY orders_update_admin_note ON public.orders FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: payment_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payment_events ENABLE ROW LEVEL SECURITY;

--
-- Name: payment_events payment_events_insert_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_events_insert_own_or_admin ON public.payment_events FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.payments p
  WHERE ((p.id = payment_events.payment_id) AND ((p.user_id = auth.uid()) OR public.is_admin())))));


--
-- Name: payment_events payment_events_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payment_events_select_own_or_admin ON public.payment_events FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.payments p
  WHERE ((p.id = payment_events.payment_id) AND ((p.user_id = auth.uid()) OR public.is_admin())))));


--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: payments payments_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payments_insert_own ON public.payments FOR INSERT TO authenticated WITH CHECK ((user_id = auth.uid()));


--
-- Name: payments payments_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payments_select_own_or_admin ON public.payments FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: payments payments_update_admin_only; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payments_update_admin_only ON public.payments FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: pickup_locations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pickup_locations ENABLE ROW LEVEL SECURITY;

--
-- Name: pickup_locations pickup_locations_modify_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pickup_locations_modify_admin ON public.pickup_locations USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: pickup_locations pickup_locations_select_active; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pickup_locations_select_active ON public.pickup_locations FOR SELECT USING (((is_active = true) OR public.is_admin()));


--
-- Name: products; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

--
-- Name: products products_write_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY products_write_admin ON public.products USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_insert_own ON public.profiles FOR INSERT WITH CHECK ((auth.uid() = id));


--
-- Name: profiles profiles_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_select_own_or_admin ON public.profiles FOR SELECT USING (((auth.uid() = id) OR public.is_admin()));


--
-- Name: profiles profiles_update_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_update_admin ON public.profiles FOR UPDATE USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: profiles profiles_update_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_update_own ON public.profiles FOR UPDATE USING ((auth.uid() = id)) WITH CHECK (((auth.uid() = id) AND (role = ( SELECT p.role
   FROM public.profiles p
  WHERE (p.id = auth.uid())))));


--
-- Name: promotion_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.promotion_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: promotion_rules promotion_rules_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY promotion_rules_admin_all ON public.promotion_rules TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: promotion_rules promotion_rules_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY promotion_rules_select ON public.promotion_rules FOR SELECT TO authenticated USING (true);


--
-- Name: promotions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;

--
-- Name: promotions promotions_admin_all; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY promotions_admin_all ON public.promotions TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());


--
-- Name: promotions promotions_select_active_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY promotions_select_active_or_admin ON public.promotions FOR SELECT TO authenticated USING (((status = 'active'::text) OR public.is_admin()));


--
-- Name: referrals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

--
-- Name: referrals referrals_insert_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY referrals_insert_own ON public.referrals FOR INSERT TO authenticated WITH CHECK (((referrer_user_id = auth.uid()) OR public.is_admin()));


--
-- Name: referrals referrals_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY referrals_select_own_or_admin ON public.referrals FOR SELECT TO authenticated USING (((referrer_user_id = auth.uid()) OR (referred_user_id = auth.uid()) OR public.is_admin()));


--
-- Name: reward_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reward_events ENABLE ROW LEVEL SECURITY;

--
-- Name: reward_events reward_events_insert_authenticated; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reward_events_insert_authenticated ON public.reward_events FOR INSERT TO authenticated WITH CHECK (((user_id = auth.uid()) OR public.is_admin() OR (user_id IS NULL)));


--
-- Name: reward_events reward_events_select_own_or_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reward_events_select_own_or_admin ON public.reward_events FOR SELECT TO authenticated USING (((user_id = auth.uid()) OR public.is_admin()));


--
-- Name: wishlists; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.wishlists ENABLE ROW LEVEL SECURITY;

--
-- Name: wishlists wishlists_all_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wishlists_all_own ON public.wishlists USING ((auth.uid() = user_id)) WITH CHECK ((auth.uid() = user_id));


--
-- Name: messages; Type: ROW SECURITY; Schema: realtime; Owner: -
--

ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_analytics; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets_analytics ENABLE ROW LEVEL SECURITY;

--
-- Name: buckets_vectors; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.buckets_vectors ENABLE ROW LEVEL SECURITY;

--
-- Name: migrations; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.migrations ENABLE ROW LEVEL SECURITY;

--
-- Name: objects; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

--
-- Name: objects products_admin_delete; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY products_admin_delete ON storage.objects FOR DELETE USING (((bucket_id = 'products'::text) AND public.is_admin()));


--
-- Name: objects products_admin_insert; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY products_admin_insert ON storage.objects FOR INSERT WITH CHECK (((bucket_id = 'products'::text) AND public.is_admin()));


--
-- Name: objects products_admin_update; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY products_admin_update ON storage.objects FOR UPDATE USING (((bucket_id = 'products'::text) AND public.is_admin())) WITH CHECK (((bucket_id = 'products'::text) AND public.is_admin()));


--
-- Name: objects products_public_read; Type: POLICY; Schema: storage; Owner: -
--

CREATE POLICY products_public_read ON storage.objects FOR SELECT USING ((bucket_id = 'products'::text));


--
-- Name: s3_multipart_uploads; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads ENABLE ROW LEVEL SECURITY;

--
-- Name: s3_multipart_uploads_parts; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.s3_multipart_uploads_parts ENABLE ROW LEVEL SECURITY;

--
-- Name: vector_indexes; Type: ROW SECURITY; Schema: storage; Owner: -
--

ALTER TABLE storage.vector_indexes ENABLE ROW LEVEL SECURITY;

--
-- Name: supabase_realtime; Type: PUBLICATION; Schema: -; Owner: -
--

CREATE PUBLICATION supabase_realtime WITH (publish = 'insert, update, delete, truncate');


--
-- Name: supabase_realtime_messages_publication; Type: PUBLICATION; Schema: -; Owner: -
--

CREATE PUBLICATION supabase_realtime_messages_publication WITH (publish = 'insert, update, delete, truncate');


--
-- Name: supabase_realtime_messages_publication messages; Type: PUBLICATION TABLE; Schema: realtime; Owner: -
--

ALTER PUBLICATION supabase_realtime_messages_publication ADD TABLE ONLY realtime.messages;


--
-- Name: issue_graphql_placeholder; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_graphql_placeholder ON sql_drop
         WHEN TAG IN ('DROP EXTENSION')
   EXECUTE FUNCTION extensions.set_graphql_placeholder();


--
-- Name: issue_pg_cron_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_cron_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_cron_access();


--
-- Name: issue_pg_graphql_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_graphql_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_graphql_access();


--
-- Name: issue_pg_net_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_net_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_net_access();


--
-- Name: pgrst_ddl_watch; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER pgrst_ddl_watch ON ddl_command_end
   EXECUTE FUNCTION extensions.pgrst_ddl_watch();


--
-- Name: pgrst_drop_watch; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER pgrst_drop_watch ON sql_drop
   EXECUTE FUNCTION extensions.pgrst_drop_watch();


--
-- PostgreSQL database dump complete
--

\unrestrict J3v86YyNcQAyNHXxaKPJWfyPnHBwOXc379q74FXlQwcN6laUglUbQzN7AkIjFNg

