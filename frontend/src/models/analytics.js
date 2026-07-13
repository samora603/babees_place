/**
 * Business analytics models and pure aggregation helpers.
 * Revenue recognition and rollups live here; analyticsService fetches data and delegates.
 */

/** @typedef {Object} RevenueSummary
 * @property {number} today
 * @property {number} thisWeek
 * @property {number} thisMonth
 * @property {number} allTime
 */

/** @typedef {Object} SalesSummary
 * @property {number} averageOrderValue
 * @property {number} totalRevenue
 * @property {number} totalOrders
 * @property {number} completedOrders
 * @property {number} cancelledOrders
 * @property {number} pendingOrders
 */

/** @typedef {Object} StatusCount
 * @property {string} key
 * @property {string} label
 * @property {number} count
 */

/** @typedef {Object} TopProductRow
 * @property {string | null} productId
 * @property {string} productName
 * @property {number} unitsSold
 * @property {number} revenueGenerated
 */

/** @typedef {Object} TopCategoryRow
 * @property {string} categoryName
 * @property {number} unitsSold
 * @property {number} revenue
 */

/** Chart-ready status buckets (schema key → display label). */
export const ANALYTICS_STATUS_BUCKETS = [
  { key: 'pending', label: 'Pending' },
  { key: 'confirmed', label: 'Confirmed' },
  { key: 'processing', label: 'Processing' },
  { key: 'ready_for_pickup', label: 'Ready for Pickup' },
  { key: 'shipped', label: 'Out for Delivery' },
  { key: 'delivered', label: 'Completed' },
  { key: 'cancelled', label: 'Cancelled' },
];

export const ANALYTICS_PAYMENT_BUCKETS = [
  { key: 'pending', label: 'Pending' },
  { key: 'paid', label: 'Paid' },
  { key: 'refunded', label: 'Refunded' },
  { key: 'failed', label: 'Failed' },
];

export const ANALYTICS_FULFILLMENT_BUCKETS = [
  { key: 'pickup', label: 'Pickup' },
  { key: 'delivery', label: 'Delivery' },
];

export const EMPTY_REVENUE_SUMMARY = {
  today: 0,
  thisWeek: 0,
  thisMonth: 0,
  allTime: 0,
};

export const EMPTY_SALES_SUMMARY = {
  averageOrderValue: 0,
  totalRevenue: 0,
  totalOrders: 0,
  completedOrders: 0,
  cancelledOrders: 0,
  pendingOrders: 0,
};

/**
 * Revenue recognition rule (COD): paid orders that were not cancelled.
 * @param {{ status?: string, payment_status?: string } | null | undefined} order
 */
export function isRecognizedRevenueOrder(order) {
  if (!order || order.status === 'cancelled') return false;
  return order.payment_status === 'paid';
}

/**
 * @param {Date} [reference]
 */
export function startOfCalendarDay(reference = new Date()) {
  return new Date(reference.getFullYear(), reference.getMonth(), reference.getDate());
}

/**
 * Week starts Monday (local calendar).
 * @param {Date} [reference]
 */
export function startOfCalendarWeek(reference = new Date()) {
  const start = new Date(reference);
  const day = start.getDay();
  const diff = day === 0 ? 6 : day - 1;
  start.setDate(start.getDate() - diff);
  start.setHours(0, 0, 0, 0);
  return start;
}

/**
 * @param {Date} [reference]
 */
export function startOfCalendarMonth(reference = new Date()) {
  return new Date(reference.getFullYear(), reference.getMonth(), 1);
}

/**
 * @param {string | Date | null | undefined} value
 */
export function parseOrderDate(value) {
  if (!value) return null;
  const d = value instanceof Date ? value : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * @param {Array<{ total?: number, created_at?: string, status?: string, payment_status?: string }>} orders
 * @param {Date} [now]
 * @returns {RevenueSummary}
 */
export function buildRevenueSummary(orders = [], now = new Date()) {
  const dayStart = startOfCalendarDay(now);
  const weekStart = startOfCalendarWeek(now);
  const monthStart = startOfCalendarMonth(now);

  const summary = { ...EMPTY_REVENUE_SUMMARY };

  for (const order of orders) {
    if (!isRecognizedRevenueOrder(order)) continue;
    const amount = Number(order.total || 0);
    const created = parseOrderDate(order.created_at);
    summary.allTime += amount;
    if (!created) continue;
    if (created >= dayStart) summary.today += amount;
    if (created >= weekStart) summary.thisWeek += amount;
    if (created >= monthStart) summary.thisMonth += amount;
  }

  return summary;
}

/**
 * @param {Array<{ total?: number, status?: string, payment_status?: string }>} orders
 * @returns {SalesSummary}
 */
export function buildSalesSummary(orders = []) {
  const totalOrders = orders.length;
  const recognized = orders.filter(isRecognizedRevenueOrder);
  const totalRevenue = recognized.reduce((sum, o) => sum + Number(o.total || 0), 0);

  return {
    averageOrderValue: recognized.length > 0 ? totalRevenue / recognized.length : 0,
    totalRevenue,
    totalOrders,
    completedOrders: orders.filter((o) => o.status === 'delivered').length,
    cancelledOrders: orders.filter((o) => o.status === 'cancelled').length,
    pendingOrders: orders.filter((o) => o.status === 'pending').length,
  };
}

/**
 * @param {Array<{ status?: string }>} orders
 * @returns {StatusCount[]}
 */
export function buildOrdersByStatus(orders = []) {
  const counts = Object.fromEntries(ANALYTICS_STATUS_BUCKETS.map((b) => [b.key, 0]));

  for (const order of orders) {
    const key = order.status;
    if (key && key in counts) counts[key] += 1;
  }

  return ANALYTICS_STATUS_BUCKETS.map(({ key, label }) => ({
    key,
    label,
    count: counts[key] ?? 0,
  }));
}

/**
 * @param {Array<{ delivery_type?: string | null }>} orders
 * @returns {StatusCount[]}
 */
export function buildOrdersByFulfillment(orders = []) {
  const counts = Object.fromEntries(ANALYTICS_FULFILLMENT_BUCKETS.map((b) => [b.key, 0]));

  for (const order of orders) {
    const key = order.delivery_type;
    if (key && key in counts) counts[key] += 1;
  }

  return ANALYTICS_FULFILLMENT_BUCKETS.map(({ key, label }) => ({
    key,
    label,
    count: counts[key] ?? 0,
  }));
}

/**
 * @param {Array<{ payment_status?: string }>} orders
 * @returns {StatusCount[]}
 */
export function buildOrdersByPaymentStatus(orders = []) {
  const counts = Object.fromEntries(ANALYTICS_PAYMENT_BUCKETS.map((b) => [b.key, 0]));

  for (const order of orders) {
    const key = order.payment_status || 'pending';
    if (key in counts) counts[key] += 1;
  }

  return ANALYTICS_PAYMENT_BUCKETS.map(({ key, label }) => ({
    key,
    label,
    count: counts[key] ?? 0,
  }));
}

/**
 * @param {Array<{ product_id?: string, name?: string, price?: number, quantity?: number, orders?: object }>} items
 * @param {number} [limit=10]
 * @returns {TopProductRow[]}
 */
export function aggregateTopProducts(items = [], limit = 10) {
  /** @type {Map<string, TopProductRow>} */
  const byProduct = new Map();

  for (const item of items) {
    if (!isRecognizedRevenueOrder(item.orders)) continue;

    const productId = item.product_id || null;
    const mapKey = productId || item.name || 'unknown';
    const qty = Number(item.quantity || 0);
    const lineRevenue = qty * Number(item.price || 0);

    if (!byProduct.has(mapKey)) {
      byProduct.set(mapKey, {
        productId,
        productName: item.name || 'Unknown product',
        unitsSold: 0,
        revenueGenerated: 0,
      });
    }

    const row = byProduct.get(mapKey);
    row.unitsSold += qty;
    row.revenueGenerated += lineRevenue;
  }

  return [...byProduct.values()]
    .sort((a, b) => b.revenueGenerated - a.revenueGenerated || b.unitsSold - a.unitsSold)
    .slice(0, limit);
}

/**
 * Resolve category label from an order_items row embed.
 * @param {object} item
 */
function resolveCategoryName(item) {
  const fromRelation = item.products?.categories?.name;
  if (fromRelation) return fromRelation;
  const fromText = item.products?.category;
  if (fromText) return fromText;
  return 'Uncategorized';
}

/**
 * @param {Array<{ product_id?: string, name?: string, price?: number, quantity?: number, orders?: object, products?: object }>} items
 * @param {number} [limit=10]
 * @returns {TopCategoryRow[]}
 */
export function aggregateTopCategories(items = [], limit = 10) {
  /** @type {Map<string, TopCategoryRow>} */
  const byCategory = new Map();

  for (const item of items) {
    if (!isRecognizedRevenueOrder(item.orders)) continue;

    const categoryName = resolveCategoryName(item);
    const qty = Number(item.quantity || 0);
    const lineRevenue = qty * Number(item.price || 0);

    if (!byCategory.has(categoryName)) {
      byCategory.set(categoryName, { categoryName, unitsSold: 0, revenue: 0 });
    }

    const row = byCategory.get(categoryName);
    row.unitsSold += qty;
    row.revenue += lineRevenue;
  }

  return [...byCategory.values()]
    .sort((a, b) => b.revenue - a.revenue || b.unitsSold - a.unitsSold)
    .slice(0, limit);
}

/**
 * Display descriptors for RevenueSummaryCard (currency formatting in UI).
 * @param {RevenueSummary} summary
 */
export function revenueSummaryToDisplayItems(summary) {
  return [
    { key: 'today', label: 'Today', value: summary.today },
    { key: 'thisWeek', label: 'This Week', value: summary.thisWeek },
    { key: 'thisMonth', label: 'This Month', value: summary.thisMonth },
    { key: 'allTime', label: 'All Time', value: summary.allTime },
  ];
}

/**
 * Display descriptors for SalesSummaryCard.
 * @param {SalesSummary} summary
 */
export function salesSummaryToDisplayItems(summary) {
  return [
    { key: 'averageOrderValue', label: 'Average Order Value', value: summary.averageOrderValue, format: 'currency' },
    { key: 'totalRevenue', label: 'Total Revenue', value: summary.totalRevenue, format: 'currency' },
    { key: 'totalOrders', label: 'Total Orders', value: summary.totalOrders, format: 'number' },
    { key: 'completedOrders', label: 'Completed Orders', value: summary.completedOrders, format: 'number' },
    { key: 'cancelledOrders', label: 'Cancelled Orders', value: summary.cancelledOrders, format: 'number' },
    { key: 'pendingOrders', label: 'Pending Orders', value: summary.pendingOrders, format: 'number' },
  ];
}
