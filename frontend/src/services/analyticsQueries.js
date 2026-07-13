/**
 * Shared Supabase fetch helpers for analytics (in-flight deduplication).
 * Prevents duplicate queries when AdminDashboard loads aggregations in parallel.
 */

import { supabase } from '@/lib/supabaseClient';

/** @type {Promise<{ data: object[] | null, error: object | null }> | null} */
let ordersAnalyticsInFlight = null;

/** @type {Promise<{ data: object[] | null, error: object | null }> | null} */
let orderItemsAnalyticsInFlight = null;

export function fetchOrdersForAnalytics() {
  if (!ordersAnalyticsInFlight) {
    ordersAnalyticsInFlight = (async () => {
      try {
        return await supabase
          .from('orders')
          .select('id, status, payment_status, delivery_type, total, created_at');
      } catch (error) {
        return { data: null, error };
      } finally {
        ordersAnalyticsInFlight = null;
      }
    })();
  }
  return ordersAnalyticsInFlight;
}

export function fetchOrderItemsForAnalytics() {
  if (!orderItemsAnalyticsInFlight) {
    orderItemsAnalyticsInFlight = (async () => {
      try {
        return await supabase
          .from('order_items')
          .select(`
            product_id,
            name,
            price,
            quantity,
            orders!inner (status, payment_status),
            products (category, categories (name))
          `);
      } catch (error) {
        return { data: null, error };
      } finally {
        orderItemsAnalyticsInFlight = null;
      }
    })();
  }
  return orderItemsAnalyticsInFlight;
}

/** Reset in-flight caches (testing only). */
export function resetAnalyticsQueryCache() {
  ordersAnalyticsInFlight = null;
  orderItemsAnalyticsInFlight = null;
}
