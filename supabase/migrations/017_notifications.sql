-- 017_notifications.sql
-- Workstream 7 — Notifications & customer communications foundation
--
-- In-app inbox, delivery ledger, templates, preferences, event audit.
-- Mock email/SMS providers are used in the app; live Resend / Africa's Talking
-- / Twilio swap via provider factory (no secrets in this migration).
-- Idempotent where practical.

-- ---------------------------------------------------------------------------
-- 1. Extend customer_preferences (backwards-compatible flags)
-- ---------------------------------------------------------------------------
ALTER TABLE public.customer_preferences
  ADD COLUMN IF NOT EXISTS email_notifications boolean NOT NULL DEFAULT true;

ALTER TABLE public.customer_preferences
  ADD COLUMN IF NOT EXISTS order_updates boolean NOT NULL DEFAULT true;

ALTER TABLE public.customer_preferences
  ADD COLUMN IF NOT EXISTS payment_updates boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.customer_preferences.email_notifications IS
  'WS7 — allow transactional email (orders/payments/account).';
COMMENT ON COLUMN public.customer_preferences.order_updates IS
  'WS7 — order lifecycle notifications.';
COMMENT ON COLUMN public.customer_preferences.payment_updates IS
  'WS7 — payment lifecycle notifications.';

-- ---------------------------------------------------------------------------
-- 2. notification_templates
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  channel text NOT NULL DEFAULT 'in_app',
  subject text,
  body text NOT NULL,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT notification_templates_channel_check
    CHECK (channel IN ('in_app', 'email', 'sms', 'push')),
  CONSTRAINT notification_templates_code_channel_unique UNIQUE (code, channel)
);

CREATE INDEX IF NOT EXISTS idx_notification_templates_code
  ON public.notification_templates (code);

DROP TRIGGER IF EXISTS notification_templates_set_updated_at ON public.notification_templates;
CREATE TRIGGER notification_templates_set_updated_at
  BEFORE UPDATE ON public.notification_templates
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. notification_preferences (per-user channel/category toggles)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email_enabled boolean NOT NULL DEFAULT true,
  sms_enabled boolean NOT NULL DEFAULT false,
  in_app_enabled boolean NOT NULL DEFAULT true,
  push_enabled boolean NOT NULL DEFAULT false,
  marketing_emails boolean NOT NULL DEFAULT false,
  order_updates boolean NOT NULL DEFAULT true,
  payment_updates boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS notification_preferences_set_updated_at ON public.notification_preferences;
CREATE TRIGGER notification_preferences_set_updated_at
  BEFORE UPDATE ON public.notification_preferences
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. notifications (in-app inbox)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  channel text NOT NULL DEFAULT 'in_app',
  title text NOT NULL,
  body text NOT NULL,
  link text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'unread',
  audience text NOT NULL DEFAULT 'customer',
  read_at timestamptz,
  archived_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT notifications_channel_check
    CHECK (channel IN ('in_app', 'email', 'sms', 'push')),
  CONSTRAINT notifications_status_check
    CHECK (status IN ('unread', 'read', 'archived')),
  CONSTRAINT notifications_audience_check
    CHECK (audience IN ('customer', 'admin', 'system'))
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON public.notifications (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_user_status
  ON public.notifications (user_id, status);

CREATE INDEX IF NOT EXISTS idx_notifications_event_type
  ON public.notifications (event_type);

CREATE INDEX IF NOT EXISTS idx_notifications_audience_created
  ON public.notifications (audience, created_at DESC)
  WHERE audience = 'admin';

DROP TRIGGER IF EXISTS notifications_set_updated_at ON public.notifications;
CREATE TRIGGER notifications_set_updated_at
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 5. notification_deliveries (per-channel send attempts)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid REFERENCES public.notifications(id) ON DELETE SET NULL,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  channel text NOT NULL,
  provider text NOT NULL DEFAULT 'mock',
  status text NOT NULL DEFAULT 'pending',
  retry_count integer NOT NULL DEFAULT 0,
  max_retries integer NOT NULL DEFAULT 3,
  external_id text,
  error_message text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  response jsonb NOT NULL DEFAULT '{}'::jsonb,
  scheduled_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT notification_deliveries_channel_check
    CHECK (channel IN ('in_app', 'email', 'sms', 'push')),
  CONSTRAINT notification_deliveries_status_check
    CHECK (status IN (
      'pending', 'queued', 'sending', 'sent', 'delivered',
      'failed', 'skipped', 'cancelled'
    )),
  CONSTRAINT notification_deliveries_retry_nonneg CHECK (retry_count >= 0)
);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_user_created
  ON public.notification_deliveries (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_status
  ON public.notification_deliveries (status);

CREATE INDEX IF NOT EXISTS idx_notification_deliveries_notification_id
  ON public.notification_deliveries (notification_id);

DROP TRIGGER IF EXISTS notification_deliveries_set_updated_at ON public.notification_deliveries;
CREATE TRIGGER notification_deliveries_set_updated_at
  BEFORE UPDATE ON public.notification_deliveries
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 6. notification_events (emit / dispatch audit)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type text NOT NULL,
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  result jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notification_events_type_created
  ON public.notification_events (event_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notification_events_user_created
  ON public.notification_events (user_id, created_at DESC);

-- ---------------------------------------------------------------------------
-- 7. RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.notification_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_events ENABLE ROW LEVEL SECURITY;

-- Templates: authenticated read active; admin write
DROP POLICY IF EXISTS notification_templates_select_authenticated ON public.notification_templates;
CREATE POLICY notification_templates_select_authenticated ON public.notification_templates
  FOR SELECT TO authenticated
  USING (is_active = true OR public.is_admin());

DROP POLICY IF EXISTS notification_templates_admin_all ON public.notification_templates;
CREATE POLICY notification_templates_admin_all ON public.notification_templates
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Preferences: owner only
DROP POLICY IF EXISTS notification_preferences_select_own ON public.notification_preferences;
CREATE POLICY notification_preferences_select_own ON public.notification_preferences
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS notification_preferences_insert_own ON public.notification_preferences;
CREATE POLICY notification_preferences_insert_own ON public.notification_preferences
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS notification_preferences_update_own ON public.notification_preferences;
CREATE POLICY notification_preferences_update_own ON public.notification_preferences
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Inbox: owner or admin
DROP POLICY IF EXISTS notifications_select_own_or_admin ON public.notifications;
CREATE POLICY notifications_select_own_or_admin ON public.notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS notifications_insert_own_or_admin ON public.notifications;
CREATE POLICY notifications_insert_own_or_admin ON public.notifications
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS notifications_update_own_or_admin ON public.notifications;
CREATE POLICY notifications_update_own_or_admin ON public.notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

-- Deliveries: owner or admin
DROP POLICY IF EXISTS notification_deliveries_select_own_or_admin ON public.notification_deliveries;
CREATE POLICY notification_deliveries_select_own_or_admin ON public.notification_deliveries
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS notification_deliveries_insert_own_or_admin ON public.notification_deliveries;
CREATE POLICY notification_deliveries_insert_own_or_admin ON public.notification_deliveries
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS notification_deliveries_update_own_or_admin ON public.notification_deliveries;
CREATE POLICY notification_deliveries_update_own_or_admin ON public.notification_deliveries
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR public.is_admin())
  WITH CHECK (user_id = auth.uid() OR public.is_admin());

-- Events: own or admin read; insert own or admin
DROP POLICY IF EXISTS notification_events_select_own_or_admin ON public.notification_events;
CREATE POLICY notification_events_select_own_or_admin ON public.notification_events
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin() OR user_id IS NULL);

DROP POLICY IF EXISTS notification_events_insert_authenticated ON public.notification_events;
CREATE POLICY notification_events_insert_authenticated ON public.notification_events
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() OR public.is_admin() OR user_id IS NULL);

-- ---------------------------------------------------------------------------
-- 8. Helpers — preferences bootstrap + admin fan-out + mark read
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_notification_preferences(p_user_id uuid DEFAULT auth.uid())
RETURNS public.notification_preferences
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

REVOKE ALL ON FUNCTION public.ensure_notification_preferences(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_notification_preferences(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.notify_admin_users(
  p_event_type text,
  p_title text,
  p_body text,
  p_link text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

REVOKE ALL ON FUNCTION public.notify_admin_users(text, text, text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.notify_admin_users(text, text, text, text, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_notification_read(p_notification_id uuid)
RETURNS public.notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

REVOKE ALL ON FUNCTION public.mark_notification_read(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read(p_audience text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

REVOKE ALL ON FUNCTION public.mark_all_notifications_read(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.archive_notification(p_notification_id uuid)
RETURNS public.notifications
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

REVOKE ALL ON FUNCTION public.archive_notification(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.archive_notification(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- 9. Seed templates ({{variable}} placeholders)
-- ---------------------------------------------------------------------------
INSERT INTO public.notification_templates (code, channel, subject, body, description)
VALUES
  ('account_registration', 'in_app', NULL,
   'Welcome to Babees Place, {{name}}! Your account is ready.',
   'Account registration confirmation'),
  ('welcome', 'email', 'Welcome to Babees Place',
   'Hi {{name}},\n\nWelcome to Babees Place. Start exploring our collection today.',
   'Welcome email'),
  ('password_reset', 'email', 'Reset your Babees Place password',
   'Hi {{name}},\n\nUse this link to reset your password: {{reset_link}}\n\nIf you did not request this, ignore this email.',
   'Password reset'),
  ('email_verification', 'email', 'Verify your Babees Place email',
   'Hi {{name}},\n\nPlease verify your email: {{verify_link}}',
   'Email verification'),
  ('order_created', 'in_app', NULL,
   'Order {{order_number}} was placed successfully. Total: {{amount}} {{currency}}.',
   'Customer order created'),
  ('order_confirmed', 'in_app', NULL,
   'Order {{order_number}} has been confirmed and is being prepared.',
   'Order confirmed'),
  ('order_cancelled', 'in_app', NULL,
   'Order {{order_number}} has been cancelled.',
   'Order cancelled'),
  ('order_ready_for_pickup', 'in_app', NULL,
   'Order {{order_number}} is ready for pickup at {{location}}.',
   'Ready for pickup'),
  ('out_for_delivery', 'in_app', NULL,
   'Order {{order_number}} is out for delivery.',
   'Out for delivery'),
  ('delivered', 'in_app', NULL,
   'Order {{order_number}} has been delivered. Enjoy!',
   'Delivered'),
  ('payment_initiated', 'in_app', NULL,
   'Payment of {{amount}} {{currency}} initiated for order {{order_number}}. Check your phone for M-Pesa.',
   'Payment initiated'),
  ('payment_successful', 'in_app', NULL,
   'Payment received for order {{order_number}}. Receipt: {{receipt_number}}.',
   'Payment successful'),
  ('payment_failed', 'in_app', NULL,
   'Payment for order {{order_number}} failed. You can retry from your order page.',
   'Payment failed'),
  ('payment_retry', 'in_app', NULL,
   'A new payment attempt was started for order {{order_number}}.',
   'Payment retry'),
  ('admin_new_order', 'in_app', NULL,
   'New order {{order_number}} — {{amount}} {{currency}} ({{payment_method}}).',
   'Admin new order'),
  ('admin_low_inventory', 'in_app', NULL,
   'Low stock: {{product_name}} has {{stock}} units left.',
   'Admin low inventory'),
  ('admin_payment_received', 'in_app', NULL,
   'Payment received for order {{order_number}}. Receipt: {{receipt_number}}.',
   'Admin payment received'),
  ('order_created', 'email', 'Order confirmation — {{order_number}}',
   'Hi {{name}},\n\nThanks for your order {{order_number}}. Total: {{amount}} {{currency}}.',
   'Order confirmation email'),
  ('payment_successful', 'email', 'Payment received — {{order_number}}',
   'Hi {{name}},\n\nWe received your payment for {{order_number}}. Receipt: {{receipt_number}}.',
   'Payment success email'),
  ('payment_failed', 'email', 'Payment failed — {{order_number}}',
   'Hi {{name}},\n\nPayment for {{order_number}} did not complete. Please retry from your orders.',
   'Payment failed email'),
  ('order_ready_for_pickup', 'sms', NULL,
   'Babees Place: Order {{order_number}} is ready for pickup.',
   'Pickup SMS'),
  ('payment_successful', 'sms', NULL,
   'Babees Place: Payment confirmed for {{order_number}}. Receipt {{receipt_number}}.',
   'Payment SMS')
ON CONFLICT (code, channel) DO NOTHING;
