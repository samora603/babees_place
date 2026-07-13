-- =============================================================================
-- 014_customer_profile.sql — Saved addresses & account preferences
-- Babees Place — Phase 2 Workstream 5 Milestone 5.1
-- =============================================================================
-- PURPOSE:
--   * customer_addresses — multi-address book per customer
--   * customer_preferences — fulfillment & notification prefs (storage only)
--   * RLS: customers access own rows only
--   * Single default address enforced via trigger
--
-- DEPENDENCIES: 001–013 applied
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- customer_addresses
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.customer_addresses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  label text NOT NULL,
  recipient_name text NOT NULL,
  phone text NOT NULL,
  county text NOT NULL,
  town text NOT NULL,
  street_address text NOT NULL,
  additional_directions text,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT customer_addresses_label_check
    CHECK (label IN ('home', 'work', 'other'))
);

CREATE INDEX IF NOT EXISTS idx_customer_addresses_user_id
  ON public.customer_addresses (user_id);

CREATE INDEX IF NOT EXISTS idx_customer_addresses_user_default
  ON public.customer_addresses (user_id, is_default)
  WHERE is_default = true;

ALTER TABLE public.customer_addresses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customer_addresses_select_own ON public.customer_addresses;
CREATE POLICY customer_addresses_select_own ON public.customer_addresses
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS customer_addresses_insert_own ON public.customer_addresses;
CREATE POLICY customer_addresses_insert_own ON public.customer_addresses
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS customer_addresses_update_own ON public.customer_addresses;
CREATE POLICY customer_addresses_update_own ON public.customer_addresses
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS customer_addresses_delete_own ON public.customer_addresses;
CREATE POLICY customer_addresses_delete_own ON public.customer_addresses
  FOR DELETE USING (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- customer_preferences (one row per customer)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.customer_preferences (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  preferred_fulfillment text,
  preferred_pickup_location_id uuid REFERENCES public.pickup_locations(id) ON DELETE SET NULL,
  marketing_emails boolean NOT NULL DEFAULT false,
  sms_notifications boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT customer_preferences_fulfillment_check
    CHECK (preferred_fulfillment IS NULL OR preferred_fulfillment IN ('pickup', 'delivery'))
);

ALTER TABLE public.customer_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS customer_preferences_select_own ON public.customer_preferences;
CREATE POLICY customer_preferences_select_own ON public.customer_preferences
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS customer_preferences_insert_own ON public.customer_preferences;
CREATE POLICY customer_preferences_insert_own ON public.customer_preferences
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS customer_preferences_update_own ON public.customer_preferences;
CREATE POLICY customer_preferences_update_own ON public.customer_preferences
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS customer_preferences_delete_own ON public.customer_preferences;
CREATE POLICY customer_preferences_delete_own ON public.customer_preferences
  FOR DELETE USING (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- updated_at triggers (set_updated_at from 003)
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS customer_addresses_set_updated_at ON public.customer_addresses;
CREATE TRIGGER customer_addresses_set_updated_at
  BEFORE UPDATE ON public.customer_addresses
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS customer_preferences_set_updated_at ON public.customer_preferences;
CREATE TRIGGER customer_preferences_set_updated_at
  BEFORE UPDATE ON public.customer_preferences
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Ensure at most one default address per user
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.enforce_single_default_address()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS $$
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

DROP TRIGGER IF EXISTS customer_addresses_single_default ON public.customer_addresses;
CREATE TRIGGER customer_addresses_single_default
  AFTER INSERT OR UPDATE OF is_default ON public.customer_addresses
  FOR EACH ROW
  WHEN (NEW.is_default = true)
  EXECUTE FUNCTION public.enforce_single_default_address();

COMMIT;
