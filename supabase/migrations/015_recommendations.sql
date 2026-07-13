-- 015_recommendations.sql
-- Phase 2 WS5 Milestone 5.3 — storefront recommendation helpers
--
-- Best-seller aggregates require reading across customers' order_items.
-- RLS on order_items is owner-or-admin, so a SECURITY DEFINER RPC exposes
-- only anonymized product_id + units_sold for active, in-stock products.
-- No new tables. Idempotent.

CREATE OR REPLACE FUNCTION public.get_bestseller_product_ids(p_limit integer DEFAULT 12)
RETURNS TABLE (product_id uuid, units_sold bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
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

COMMENT ON FUNCTION public.get_bestseller_product_ids(integer) IS
  'WS5 M5.3 — anonymized bestseller ids for storefront recommendations (SECURITY DEFINER).';

REVOKE ALL ON FUNCTION public.get_bestseller_product_ids(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_bestseller_product_ids(integer) TO anon, authenticated;
