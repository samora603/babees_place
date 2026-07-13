-- 018_promotions_loyalty.sql
-- Workstream 8 — Promotions, loyalty, coupons, referrals, gift cards
--
-- Extends place_order with optional reward params (defaults preserve COD path).
-- Idempotent where practical.

-- ---------------------------------------------------------------------------
-- 1. Order reward columns (backwards compatible)
-- ---------------------------------------------------------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS discount_amount numeric(12,2) NOT NULL DEFAULT 0;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS coupon_code text;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS loyalty_points_redeemed integer NOT NULL DEFAULT 0;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS gift_card_amount numeric(12,2) NOT NULL DEFAULT 0;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS free_delivery boolean NOT NULL DEFAULT false;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS promotions_applied jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS referral_code text;

COMMENT ON COLUMN public.orders.discount_amount IS 'WS8 — merchandise discount (excl. gift card).';
COMMENT ON COLUMN public.orders.promotions_applied IS 'WS8 — snapshot of applied promo/coupon ids.';

-- ---------------------------------------------------------------------------
-- 2. promotions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.promotions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text,
  name text NOT NULL,
  description text,
  promo_type text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  priority integer NOT NULL DEFAULT 100,
  stackable boolean NOT NULL DEFAULT false,
  percent_off numeric(5,2),
  amount_off numeric(12,2),
  buy_quantity integer,
  get_quantity integer,
  category_id uuid REFERENCES public.categories(id) ON DELETE SET NULL,
  product_id uuid,
  min_order_amount numeric(12,2) NOT NULL DEFAULT 0,
  max_discount_amount numeric(12,2),
  usage_limit integer,
  usage_count integer NOT NULL DEFAULT 0,
  per_user_limit integer,
  starts_at timestamptz,
  ends_at timestamptz,
  eligibility jsonb NOT NULL DEFAULT '{}'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT promotions_type_check CHECK (promo_type IN (
    'percentage', 'fixed', 'free_delivery', 'buy_x_get_y',
    'category', 'product', 'storewide'
  )),
  CONSTRAINT promotions_status_check CHECK (status IN ('draft', 'active', 'paused', 'expired'))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_promotions_code_unique
  ON public.promotions (lower(code)) WHERE code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_promotions_status_priority
  ON public.promotions (status, priority DESC);
CREATE INDEX IF NOT EXISTS idx_promotions_dates
  ON public.promotions (starts_at, ends_at);

DROP TRIGGER IF EXISTS promotions_set_updated_at ON public.promotions;
CREATE TRIGGER promotions_set_updated_at
  BEFORE UPDATE ON public.promotions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. promotion_rules (extra targeting / conditions)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.promotion_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  promotion_id uuid NOT NULL REFERENCES public.promotions(id) ON DELETE CASCADE,
  rule_type text NOT NULL,
  rule_value jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT promotion_rules_type_check CHECK (rule_type IN (
    'min_quantity', 'max_uses_per_day', 'customer_segment', 'first_order_only', 'exclude_sale_items'
  ))
);

CREATE INDEX IF NOT EXISTS idx_promotion_rules_promotion_id
  ON public.promotion_rules (promotion_id);

-- ---------------------------------------------------------------------------
-- 4. coupons
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.coupons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  name text NOT NULL,
  description text,
  discount_type text NOT NULL,
  percent_off numeric(5,2),
  amount_off numeric(12,2),
  free_delivery boolean NOT NULL DEFAULT false,
  min_order_amount numeric(12,2) NOT NULL DEFAULT 0,
  max_discount_amount numeric(12,2),
  usage_limit integer,
  usage_count integer NOT NULL DEFAULT 0,
  per_user_limit integer DEFAULT 1,
  is_one_time boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  starts_at timestamptz,
  ends_at timestamptz,
  promotion_id uuid REFERENCES public.promotions(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT coupons_discount_type_check CHECK (discount_type IN (
    'percentage', 'fixed', 'free_delivery'
  )),
  CONSTRAINT coupons_code_unique UNIQUE (code)
);

CREATE INDEX IF NOT EXISTS idx_coupons_active ON public.coupons (is_active, starts_at, ends_at);

DROP TRIGGER IF EXISTS coupons_set_updated_at ON public.coupons;
CREATE TRIGGER coupons_set_updated_at
  BEFORE UPDATE ON public.coupons
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.coupon_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id uuid NOT NULL REFERENCES public.coupons(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  discount_amount numeric(12,2) NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_coupon_user
  ON public.coupon_redemptions (coupon_id, user_id);
CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_order
  ON public.coupon_redemptions (order_id);

-- ---------------------------------------------------------------------------
-- 5. loyalty
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.loyalty_accounts (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  points_balance integer NOT NULL DEFAULT 0,
  lifetime_earned integer NOT NULL DEFAULT 0,
  lifetime_redeemed integer NOT NULL DEFAULT 0,
  referral_code text NOT NULL,
  tier text NOT NULL DEFAULT 'member',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT loyalty_accounts_balance_nonneg CHECK (points_balance >= 0),
  CONSTRAINT loyalty_accounts_referral_code_unique UNIQUE (referral_code)
);

DROP TRIGGER IF EXISTS loyalty_accounts_set_updated_at ON public.loyalty_accounts;
CREATE TRIGGER loyalty_accounts_set_updated_at
  BEFORE UPDATE ON public.loyalty_accounts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.loyalty_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tx_type text NOT NULL,
  points integer NOT NULL,
  balance_after integer NOT NULL,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  description text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT loyalty_transactions_type_check CHECK (tx_type IN (
    'earn_purchase', 'earn_promotion', 'earn_referral', 'earn_bonus',
    'redeem_discount', 'redeem_delivery', 'redeem_product', 'adjust', 'expire'
  ))
);

CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_user_created
  ON public.loyalty_transactions (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.loyalty_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  earn_points_per_currency numeric(12,4) NOT NULL DEFAULT 0.01,
  redeem_points_per_currency numeric(12,4) NOT NULL DEFAULT 10,
  free_delivery_points integer NOT NULL DEFAULT 500,
  min_redeem_points integer NOT NULL DEFAULT 100,
  max_redeem_percent numeric(5,2) NOT NULL DEFAULT 50,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS loyalty_rules_set_updated_at ON public.loyalty_rules;
CREATE TRIGGER loyalty_rules_set_updated_at
  BEFORE UPDATE ON public.loyalty_rules
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 6. gift cards
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gift_cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  initial_balance numeric(12,2) NOT NULL,
  balance numeric(12,2) NOT NULL,
  currency text NOT NULL DEFAULT 'KES',
  status text NOT NULL DEFAULT 'active',
  purchased_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  recipient_email text,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT gift_cards_balance_nonneg CHECK (balance >= 0),
  CONSTRAINT gift_cards_status_check CHECK (status IN ('active', 'depleted', 'expired', 'disabled'))
);

CREATE INDEX IF NOT EXISTS idx_gift_cards_status ON public.gift_cards (status);

DROP TRIGGER IF EXISTS gift_cards_set_updated_at ON public.gift_cards;
CREATE TRIGGER gift_cards_set_updated_at
  BEFORE UPDATE ON public.gift_cards
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TABLE IF NOT EXISTS public.gift_card_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gift_card_id uuid NOT NULL REFERENCES public.gift_cards(id) ON DELETE CASCADE,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  tx_type text NOT NULL,
  amount numeric(12,2) NOT NULL,
  balance_after numeric(12,2) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT gift_card_transactions_type_check CHECK (tx_type IN (
    'issue', 'redeem', 'refund', 'adjust', 'expire'
  ))
);

CREATE INDEX IF NOT EXISTS idx_gift_card_transactions_card
  ON public.gift_card_transactions (gift_card_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 7. referrals
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  referred_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  referral_code text NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  reward_points integer NOT NULL DEFAULT 0,
  referred_reward_points integer NOT NULL DEFAULT 0,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  rewarded_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT referrals_status_check CHECK (status IN (
    'pending', 'signed_up', 'qualified', 'rewarded', 'cancelled'
  ))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_referrals_referred_user
  ON public.referrals (referred_user_id) WHERE referred_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON public.referrals (referrer_user_id);
CREATE INDEX IF NOT EXISTS idx_referrals_code ON public.referrals (referral_code);

DROP TRIGGER IF EXISTS referrals_set_updated_at ON public.referrals;
CREATE TRIGGER referrals_set_updated_at
  BEFORE UPDATE ON public.referrals
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 8. reward_events (audit)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.reward_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  order_id uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  event_type text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reward_events_user_created
  ON public.reward_events (user_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 9. RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.promotions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotion_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_redemptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gift_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gift_card_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reward_events ENABLE ROW LEVEL SECURITY;

-- Promotions: public read active; admin write
DROP POLICY IF EXISTS promotions_select_active_or_admin ON public.promotions;
CREATE POLICY promotions_select_active_or_admin ON public.promotions
  FOR SELECT TO authenticated
  USING (status = 'active' OR public.is_admin());

DROP POLICY IF EXISTS promotions_admin_all ON public.promotions;
CREATE POLICY promotions_admin_all ON public.promotions
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS promotion_rules_select ON public.promotion_rules;
CREATE POLICY promotion_rules_select ON public.promotion_rules
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS promotion_rules_admin_all ON public.promotion_rules;
CREATE POLICY promotion_rules_admin_all ON public.promotion_rules
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS coupons_select_active_or_admin ON public.coupons;
CREATE POLICY coupons_select_active_or_admin ON public.coupons
  FOR SELECT TO authenticated
  USING (is_active = true OR public.is_admin());

DROP POLICY IF EXISTS coupons_admin_all ON public.coupons;
CREATE POLICY coupons_admin_all ON public.coupons
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS coupon_redemptions_select_own_or_admin ON public.coupon_redemptions;
CREATE POLICY coupon_redemptions_select_own_or_admin ON public.coupon_redemptions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS coupon_redemptions_insert_own ON public.coupon_redemptions;
CREATE POLICY coupon_redemptions_insert_own ON public.coupon_redemptions
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS loyalty_accounts_select_own_or_admin ON public.loyalty_accounts;
CREATE POLICY loyalty_accounts_select_own_or_admin ON public.loyalty_accounts
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS loyalty_accounts_update_own_or_admin ON public.loyalty_accounts;
CREATE POLICY loyalty_accounts_update_own_or_admin ON public.loyalty_accounts
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS loyalty_accounts_insert_own ON public.loyalty_accounts;
CREATE POLICY loyalty_accounts_insert_own ON public.loyalty_accounts
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS loyalty_transactions_select_own_or_admin ON public.loyalty_transactions;
CREATE POLICY loyalty_transactions_select_own_or_admin ON public.loyalty_transactions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS loyalty_rules_select ON public.loyalty_rules;
CREATE POLICY loyalty_rules_select ON public.loyalty_rules
  FOR SELECT TO authenticated USING (is_active = true OR public.is_admin());

DROP POLICY IF EXISTS loyalty_rules_admin_all ON public.loyalty_rules;
CREATE POLICY loyalty_rules_admin_all ON public.loyalty_rules
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- Gift cards: lookup by code via RPC; owners/admins see own purchases
DROP POLICY IF EXISTS gift_cards_select_own_or_admin ON public.gift_cards;
CREATE POLICY gift_cards_select_own_or_admin ON public.gift_cards
  FOR SELECT TO authenticated
  USING (purchased_by = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS gift_cards_admin_all ON public.gift_cards;
CREATE POLICY gift_cards_admin_all ON public.gift_cards
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS gift_card_transactions_select_own_or_admin ON public.gift_card_transactions;
CREATE POLICY gift_card_transactions_select_own_or_admin ON public.gift_card_transactions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS referrals_select_own_or_admin ON public.referrals;
CREATE POLICY referrals_select_own_or_admin ON public.referrals
  FOR SELECT TO authenticated
  USING (
    referrer_user_id = auth.uid()
    OR referred_user_id = auth.uid()
    OR public.is_admin()
  );

DROP POLICY IF EXISTS referrals_insert_own ON public.referrals;
CREATE POLICY referrals_insert_own ON public.referrals
  FOR INSERT TO authenticated
  WITH CHECK (referrer_user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS reward_events_select_own_or_admin ON public.reward_events;
CREATE POLICY reward_events_select_own_or_admin ON public.reward_events
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS reward_events_insert_authenticated ON public.reward_events;
CREATE POLICY reward_events_insert_authenticated ON public.reward_events
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() OR public.is_admin() OR user_id IS NULL);

-- ---------------------------------------------------------------------------
-- 10. Helpers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_referral_code()
RETURNS text
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

CREATE OR REPLACE FUNCTION public.ensure_loyalty_account(p_user_id uuid DEFAULT auth.uid())
RETURNS public.loyalty_accounts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

REVOKE ALL ON FUNCTION public.ensure_loyalty_account(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_loyalty_account(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.lookup_gift_card(p_code text)
RETURNS TABLE (
  id uuid,
  code text,
  balance numeric,
  status text,
  expires_at timestamptz,
  currency text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT g.id, g.code, g.balance, g.status, g.expires_at, g.currency
  FROM public.gift_cards g
  WHERE upper(g.code) = upper(trim(p_code))
  LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.lookup_gift_card(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lookup_gift_card(text) TO authenticated;

-- ---------------------------------------------------------------------------
-- 11. Extended place_order (optional rewards; defaults = prior behavior)
-- Drop prior overloads so only the extended signature remains.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.place_order(uuid, text, uuid, jsonb, text);
DROP FUNCTION IF EXISTS public.place_order(uuid, text, uuid, jsonb, text, text);

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
  v_discount numeric(12,2) := GREATEST(COALESCE(p_discount_amount, 0), 0);
  v_gift numeric(12,2) := GREATEST(COALESCE(p_gift_card_amount, 0), 0);
  v_points integer := GREATEST(COALESCE(p_loyalty_points, 0), 0);
  v_free_delivery boolean := COALESCE(p_free_delivery, false);
  v_payment_method text := COALESCE(NULLIF(trim(p_payment_method), ''), 'cod');
  v_coupon public.coupons;
  v_coupon_code text := NULLIF(upper(trim(p_coupon_code)), '');
  v_gift_card public.gift_cards;
  v_loyalty public.loyalty_accounts;
  v_rule public.loyalty_rules;
  v_points_value numeric(12,2) := 0;
  v_user_redemptions integer := 0;
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
    IF NOT v_free_delivery THEN
      v_delivery_fee := 200;
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

  -- Coupon validation (server-side safety net)
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

    IF v_coupon.free_delivery OR v_coupon.discount_type = 'free_delivery' THEN
      v_free_delivery := true;
      v_delivery_fee := 0;
    END IF;
  END IF;

  -- Loyalty redemption
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
    ELSE
      v_points_value := round(v_points / 10.0, 2);
    END IF;
    v_discount := v_discount + COALESCE(v_points_value, 0);
  END IF;

  -- Cap merchandise discount
  IF v_discount > v_subtotal THEN
    v_discount := v_subtotal;
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
    COALESCE(p_promotions_applied, '[]'::jsonb),
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

  -- Record coupon redemption
  IF v_coupon.id IS NOT NULL THEN
    INSERT INTO public.coupon_redemptions (coupon_id, user_id, order_id, discount_amount)
    VALUES (v_coupon.id, p_user_id, v_order_id, v_discount);
    UPDATE public.coupons SET usage_count = usage_count + 1 WHERE id = v_coupon.id;
  END IF;

  -- Deduct loyalty points
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

  -- Gift card redeem
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
      'free_delivery', v_free_delivery
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
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.place_order(
  uuid, text, uuid, jsonb, text, text, text, integer, text, numeric, numeric, boolean, jsonb, text
) TO authenticated;

-- Earn points when payment becomes paid / order delivered (simple helper)
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
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  SELECT COUNT(*) INTO v_existing
  FROM public.loyalty_transactions
  WHERE order_id = p_order_id AND tx_type = 'earn_purchase';
  IF v_existing > 0 THEN
    RETURN 0;
  END IF;

  SELECT * INTO v_rule FROM public.loyalty_rules WHERE is_active = true ORDER BY created_at ASC LIMIT 1;
  IF NOT FOUND THEN
    v_points := floor(v_order.total * 0.01)::
  ELSE
    v_points := floor(v_order.total * v_rule.earn_points_per_currency);
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

REVOKE ALL ON FUNCTION public.award_loyalty_for_order(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.award_loyalty_for_order(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 12. Seed defaults + mock catalog
-- ---------------------------------------------------------------------------
INSERT INTO public.loyalty_rules (code, name, earn_points_per_currency, redeem_points_per_currency, free_delivery_points, min_redeem_points)
VALUES ('default', 'Default loyalty rules', 0.01, 10, 500, 100)
ON CONFLICT (code) DO NOTHING;

INSERT INTO public.promotions (
  code, name, description, promo_type, status, priority, stackable,
  percent_off, min_order_amount, starts_at, ends_at
)
SELECT
  'STORE10', 'Storewide 10% off', 'Automatic 10% off orders over 2000 KES',
  'storewide', 'active', 50, false, 10, 2000,
  now() - interval '1 day', now() + interval '180 days'
WHERE NOT EXISTS (SELECT 1 FROM public.promotions WHERE code = 'STORE10');

INSERT INTO public.coupons (
  code, name, description, discount_type, percent_off, min_order_amount,
  usage_limit, per_user_limit, is_one_time, is_active, starts_at, ends_at
) VALUES (
  'WELCOME15', 'Welcome 15% off', 'New customer coupon',
  'percentage', 15, 500, 1000, 1, false, true,
  now() - interval '1 day', now() + interval '365 days'
), (
  'FREESHIP', 'Free delivery', 'Waives delivery fee',
  'free_delivery', NULL, 0, NULL, 5, false, true,
  now() - interval '1 day', now() + interval '365 days'
), (
  'SAVE200', 'Save 200 KES', 'Fixed amount off',
  'fixed', NULL, 1000, 500, 2, false, true,
  now() - interval '1 day', now() + interval '365 days'
) ON CONFLICT (code) DO NOTHING;

-- Fix SAVE200 amount_off
UPDATE public.coupons SET amount_off = 200 WHERE code = 'SAVE200' AND amount_off IS NULL;

INSERT INTO public.gift_cards (code, initial_balance, balance, status, expires_at)
VALUES (
  'GIFT1000', 1000, 1000, 'active', now() + interval '365 days'
) ON CONFLICT (code) DO NOTHING;
