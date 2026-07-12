-- =============================================================================
-- 003_functions_and_triggers.sql — Server logic  (Strategy: M4)
-- Babees Place — Phase 1.7B Workstream 1 forward migration
-- =============================================================================
-- PURPOSE:
--   Recreate the server-authoritative logic against the CANONICAL/live schema:
--     * is_admin()          — central admin check used by RLS (avoids recursion)
--     * handle_new_user()   — auto-create a profile row on signup (role customer)
--     * set_updated_at()    — maintain updated_at on write
--     * place_order()       — atomic, server-priced checkout with stock locking
--   Definitions are DERIVED from the archived repo 001 + verified live columns,
--   adapted to live names (cart_items, orders.total, products.discount_price).
--   Nothing is fabricated.
--
-- DEPENDENCIES:
--   * 002_additive_columns.sql — place_order/handle_new_user/set_updated_at
--     require the columns added there (profiles.full_name/updated_at,
--     orders.payment_status/updated_at, products.stock/discount_price/images/
--     image_url, order_items.image_url).
--
-- RISK: Medium. Checkout depends on place_order(); validate on staging (signup
--   -> profile row; browse -> cart -> checkout). Functions are pinned to
--   search_path=public and SECURITY DEFINER where elevation is required.
--
-- ROLLBACK:
--   DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
--   DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
--   DROP TRIGGER IF EXISTS set_products_updated_at ON public.products;
--   DROP TRIGGER IF EXISTS set_orders_updated_at   ON public.orders;
--   DROP FUNCTION IF EXISTS public.place_order(uuid);
--   DROP FUNCTION IF EXISTS public.set_updated_at();
--   DROP FUNCTION IF EXISTS public.handle_new_user();
--   DROP FUNCTION IF EXISTS public.is_admin();
--
-- EXPECTED SCHEMA CHANGES:
--   + functions: is_admin, handle_new_user, set_updated_at, place_order
--   + triggers : on_auth_user_created (auth.users),
--                set_updated_at on profiles/products/orders
--
-- IDEMPOTENCY: CREATE OR REPLACE FUNCTION; DROP TRIGGER IF EXISTS before CREATE.
-- FORWARD-ONLY. Authored in Phase 1.7B WS1 — DO NOT EXECUTE in this workstream.
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- is_admin(): central admin predicate. SECURITY DEFINER so RLS on profiles
-- does not recurse; STABLE (single value per statement).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

-- ---------------------------------------------------------------------------
-- handle_new_user(): auto-provision a profile on auth signup.
-- Canonical role vocabulary is 'customer' (D-CUST-1), matching the live default.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ---------------------------------------------------------------------------
-- set_updated_at(): generic updated_at maintainer.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
CREATE TRIGGER set_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_products_updated_at ON public.products;
CREATE TRIGGER set_products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_orders_updated_at ON public.orders;
CREATE TRIGGER set_orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ---------------------------------------------------------------------------
-- place_order(): the ONLY path that writes orders/order_items.
--   * caller must be the cart owner (or an admin)
--   * locks product rows (FOR UPDATE) to prevent oversell TOCTOU races
--   * computes total server-side from live prices (never trust the client)
--   * snapshots name/price/image into order_items
--   * decrements stock and clears the cart atomically
-- Adapted from archived repo 001/002 to live columns: cart_items (not cart),
-- orders.total (not total_amount), products.discount_price (not "discountPrice").
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

  -- Lock the product rows referenced by this cart for the transaction.
  PERFORM 1
  FROM public.products p
  JOIN public.cart_items c ON c.product_id = p.id
  WHERE c.user_id = p_user_id
  FOR UPDATE OF p;

  -- Validate stock.
  FOR r IN
    SELECT c.product_id, c.quantity, p.stock, p.name
    FROM public.cart_items c
    JOIN public.products p ON p.id = c.product_id
    WHERE c.user_id = p_user_id
  LOOP
    IF r.stock < r.quantity THEN
      RAISE EXCEPTION 'Insufficient stock for %', r.name;
    END IF;
  END LOOP;

  -- Server-computed total (discount price preferred).
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

-- Restrict execution to authenticated users only. The baseline default
-- privileges (001) grant EXECUTE to anon on newly-created functions, so revoke
-- anon explicitly in addition to PUBLIC; keep authenticated (service_role retains
-- its default-privilege grant for server-side use).
REVOKE ALL ON FUNCTION public.place_order(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_order(uuid) TO authenticated;

COMMIT;
