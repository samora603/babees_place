import { supabase } from '@/lib/supabaseClient';
import { LOW_STOCK_THRESHOLD } from '@/constants/inventory';
import {
  buildDashboardSnapshot,
  createEmptyDashboardSnapshot,
  mapActivityEventRow,
  mapLowStockProductRow,
  mapRecentOrderRow,
} from '@/models/dashboard';
import {
  EMPTY_REVENUE_SUMMARY,
  EMPTY_SALES_SUMMARY,
  buildRevenueSummary,
  buildSalesSummary,
  buildOrdersByStatus,
  buildOrdersByFulfillment,
  buildOrdersByPaymentStatus,
  aggregateTopProducts,
  aggregateTopCategories,
} from '@/models/analytics';
import { fetchOrdersForAnalytics, fetchOrderItemsForAnalytics } from '@/services/analyticsQueries';
import { attachProfilesToOrders, attachProfilesToOrderEvents } from '@/services/profileLookup';

/**
 * Fetch core dashboard KPIs (counts + total revenue).
 *
 * @returns {Promise<{ data: import('@/models/dashboard').DashboardSnapshot, error: Error | null }>}
 */
export async function getDashboardSnapshot() {
  try {
    const [usersResult, productsResult, ordersResult, revenueResult] = await Promise.all([
      supabase.from('profiles').select('*', { count: 'exact', head: true }),
      supabase.from('products').select('*', { count: 'exact', head: true }),
      supabase.from('orders').select('*', { count: 'exact', head: true }),
      supabase.from('orders').select('total'),
    ]);

    const errors = [usersResult.error, productsResult.error, ordersResult.error, revenueResult.error]
      .filter(Boolean);
    if (errors.length > 0) {
      throw errors[0];
    }

    const orders = revenueResult.data || [];
    const totalRevenue = orders.reduce((sum, order) => sum + Number(order.total || 0), 0);

    const snapshot = buildDashboardSnapshot({
      totalRevenue,
      totalOrders: ordersResult.count ?? 0,
      totalProducts: productsResult.count ?? 0,
      totalUsers: usersResult.count ?? 0,
    });

    return { data: snapshot, error: null };
  } catch (error) {
    console.error('analyticsService.getDashboardSnapshot error:', error);
    return { data: createEmptyDashboardSnapshot(), error };
  }
}

/**
 * Latest orders for the dashboard recent-orders widget.
 * @param {number} [limit=10]
 * @returns {Promise<{ data: import('@/models/dashboard').RecentOrderRow[], error: Error | null }>}
 */
export async function getRecentOrders(limit = 10) {
  try {
    const { data, error } = await supabase
      .from('orders')
      .select(`
        id,
        status,
        total,
        payment_status,
        delivery_type,
        created_at,
        user_id
      `)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (error) throw error;

    const enriched = await attachProfilesToOrders(data || []);
    return { data: enriched.map(mapRecentOrderRow), error: null };
  } catch (error) {
    console.error('analyticsService.getRecentOrders error:', error);
    return { data: [], error };
  }
}

/**
 * Products at or below the low-stock threshold (stock < LOW_STOCK_THRESHOLD).
 * @returns {Promise<{ data: import('@/models/dashboard').LowStockProductRow[], error: Error | null }>}
 */
export async function getLowStockProducts() {
  try {
    const { data, error } = await supabase
      .from('products')
      .select('id, name, stock')
      .lt('stock', LOW_STOCK_THRESHOLD)
      .order('stock', { ascending: true });

    if (error) throw error;

    return { data: (data || []).map(mapLowStockProductRow), error: null };
  } catch (error) {
    console.error('analyticsService.getLowStockProducts error:', error);
    return { data: [], error };
  }
}

/**
 * Recent order_events for the activity feed (newest first).
 * @param {number} [limit=15]
 * @returns {Promise<{ data: import('@/models/dashboard').ActivityEventRow[], error: Error | null }>}
 */
export async function getDashboardActivity(limit = 15) {
  try {
    const { data, error } = await supabase
      .from('order_events')
      .select(`
        id,
        event_type,
        payload,
        created_at,
        order_id,
        orders (
          id,
          user_id
        )
      `)
      .order('created_at', { ascending: false })
      .limit(limit);

    if (error) throw error;

    const enriched = await attachProfilesToOrderEvents(data || []);
    return { data: enriched.map(mapActivityEventRow), error: null };
  } catch (error) {
    console.error('analyticsService.getDashboardActivity error:', error);
    return { data: [], error };
  }
}

/**
 * Revenue totals for recognized (paid, non-cancelled) orders by period.
 * @returns {Promise<{ data: import('@/models/analytics').RevenueSummary, error: Error | null }>}
 */
export async function getRevenueSummary() {
  try {
    const { data, error } = await fetchOrdersForAnalytics();
    if (error) throw error;
    return { data: buildRevenueSummary(data || []), error: null };
  } catch (error) {
    console.error('analyticsService.getRevenueSummary error:', error);
    return { data: { ...EMPTY_REVENUE_SUMMARY }, error };
  }
}

/**
 * High-level sales metrics across all orders.
 * @returns {Promise<{ data: import('@/models/analytics').SalesSummary, error: Error | null }>}
 */
export async function getSalesSummary() {
  try {
    const { data, error } = await fetchOrdersForAnalytics();
    if (error) throw error;
    return { data: buildSalesSummary(data || []), error: null };
  } catch (error) {
    console.error('analyticsService.getSalesSummary error:', error);
    return { data: { ...EMPTY_SALES_SUMMARY }, error };
  }
}

/**
 * Order counts grouped by fulfillment status (chart-ready).
 * @returns {Promise<{ data: import('@/models/analytics').StatusCount[], error: Error | null }>}
 */
export async function getOrdersByStatus() {
  try {
    const { data, error } = await fetchOrdersForAnalytics();
    if (error) throw error;
    return { data: buildOrdersByStatus(data || []), error: null };
  } catch (error) {
    console.error('analyticsService.getOrdersByStatus error:', error);
    return { data: buildOrdersByStatus([]), error };
  }
}

/**
 * Order counts grouped by fulfillment type (chart-ready).
 * @returns {Promise<{ data: import('@/models/analytics').StatusCount[], error: Error | null }>}
 */
export async function getOrdersByFulfillment() {
  try {
    const { data, error } = await fetchOrdersForAnalytics();
    if (error) throw error;
    return { data: buildOrdersByFulfillment(data || []), error: null };
  } catch (error) {
    console.error('analyticsService.getOrdersByFulfillment error:', error);
    return { data: buildOrdersByFulfillment([]), error };
  }
}

/**
 * Order counts grouped by payment status (chart-ready).
 * @returns {Promise<{ data: import('@/models/analytics').StatusCount[], error: Error | null }>}
 */
export async function getOrdersByPaymentStatus() {
  try {
    const { data, error } = await fetchOrdersForAnalytics();
    if (error) throw error;
    return { data: buildOrdersByPaymentStatus(data || []), error: null };
  } catch (error) {
    console.error('analyticsService.getOrdersByPaymentStatus error:', error);
    return { data: buildOrdersByPaymentStatus([]), error };
  }
}

/**
 * Best-selling products by recognized revenue.
 * @param {number} [limit=10]
 * @returns {Promise<{ data: import('@/models/analytics').TopProductRow[], error: Error | null }>}
 */
export async function getTopSellingProducts(limit = 10) {
  try {
    const { data, error } = await fetchOrderItemsForAnalytics();
    if (error) throw error;
    return { data: aggregateTopProducts(data || [], limit), error: null };
  } catch (error) {
    console.error('analyticsService.getTopSellingProducts error:', error);
    return { data: [], error };
  }
}

/**
 * Best-performing categories by recognized revenue.
 * @param {number} [limit=10]
 * @returns {Promise<{ data: import('@/models/analytics').TopCategoryRow[], error: Error | null }>}
 */
export async function getTopCategories(limit = 10) {
  try {
    const { data, error } = await fetchOrderItemsForAnalytics();
    if (error) throw error;
    return { data: aggregateTopCategories(data || [], limit), error: null };
  } catch (error) {
    console.error('analyticsService.getTopCategories error:', error);
    return { data: [], error };
  }
}

export const analyticsService = {
  getDashboardSnapshot,
  getRecentOrders,
  getLowStockProducts,
  getDashboardActivity,
  getRevenueSummary,
  getSalesSummary,
  getOrdersByStatus,
  getOrdersByFulfillment,
  getOrdersByPaymentStatus,
  getTopSellingProducts,
  getTopCategories,
};
