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

CREATE TABLE public.cart_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    product_id uuid,
    quantity smallint DEFAULT '1'::smallint,
    created_at timestamp without time zone DEFAULT now(),
    CONSTRAINT cart_items_quantity_check CHECK ((quantity > 0))
);

CREATE TABLE public.categories (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    slug text,
    created_at timestamp without time zone DEFAULT now()
);

CREATE TABLE public.coupon_redemptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    coupon_id uuid NOT NULL,
    user_id uuid NOT NULL,
    order_id uuid,
    discount_amount numeric(12,2) DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

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

CREATE TABLE public.notification_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_type text NOT NULL,
    user_id uuid,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

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

CREATE TABLE public.order_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    order_id uuid NOT NULL,
    event_type text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

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

CREATE TABLE public.payment_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payment_id uuid NOT NULL,
    event_type text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

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

CREATE TABLE public.promotion_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    promotion_id uuid NOT NULL,
    rule_type text NOT NULL,
    rule_value jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT promotion_rules_type_check CHECK ((rule_type = ANY (ARRAY['min_quantity'::text, 'max_uses_per_day'::text, 'customer_segment'::text, 'first_order_only'::text, 'exclude_sale_items'::text])))
);

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

CREATE TABLE public.reward_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    order_id uuid,
    event_type text NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.wishlists (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    product_id uuid,
    created_at timestamp without time zone DEFAULT now()
);

