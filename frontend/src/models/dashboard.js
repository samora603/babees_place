/**
 * Dashboard analytics data models.
 * JSDoc types for the admin analytics layer (foundation for future widgets/charts).
 */

import { LOW_STOCK_THRESHOLD } from '@/constants/inventory';
import { ORDER_STATUSES } from '@/utils/constants';

/** @typedef {'currency' | 'number'} KPIFormat */

/** @typedef {'out' | 'critical' | 'warning'} LowStockSeverity */

/** @typedef {'placed' | 'cancelled' | 'payment' | 'pickup' | 'delivered' | 'shipped' | 'status' | 'default'} ActivityIconKey */

/**
 * @typedef {Object} KPIValue
 * @property {string} key
 * @property {string} label
 * @property {number} value
 * @property {KPIFormat} [format]
 */

/**
 * Core KPI metrics shown on the admin dashboard.
 * @typedef {Object} DashboardKPIs
 * @property {number} totalRevenue
 * @property {number} totalOrders
 * @property {number} totalProducts
 * @property {number} totalUsers
 */

/**
 * Snapshot returned by analyticsService for the dashboard shell.
 * @typedef {Object} DashboardSnapshot
 * @property {DashboardKPIs} kpis
 * @property {string} fetchedAt ISO-8601 timestamp
 */

/**
 * @typedef {Object} RecentOrderRow
 * @property {string} id
 * @property {string} orderNumber
 * @property {string} customerName
 * @property {string} status
 * @property {string} paymentStatus
 * @property {string | null} fulfillmentType
 * @property {number} total
 * @property {string} createdAt
 */

/**
 * @typedef {Object} LowStockProductRow
 * @property {string} id
 * @property {string} name
 * @property {string} sku Product reference (short id — no SKU column in schema)
 * @property {number} stock
 * @property {number} threshold
 * @property {LowStockSeverity} severity
 */

/**
 * @typedef {Object} ActivityEventRow
 * @property {string} id
 * @property {string} orderId
 * @property {string} orderNumber
 * @property {string} eventType
 * @property {string} description
 * @property {ActivityIconKey} iconKey
 * @property {string | null} userName
 * @property {string} createdAt
 */

/** @type {DashboardKPIs} */
export const EMPTY_DASHBOARD_KPIS = {
  totalRevenue: 0,
  totalOrders: 0,
  totalProducts: 0,
  totalUsers: 0,
};

/**
 * @returns {DashboardSnapshot}
 */
export function createEmptyDashboardSnapshot() {
  return {
    kpis: { ...EMPTY_DASHBOARD_KPIS },
    fetchedAt: new Date().toISOString(),
  };
}

/**
 * Normalize raw counts into a DashboardSnapshot.
 * @param {Partial<DashboardKPIs>} raw
 * @returns {DashboardSnapshot}
 */
export function buildDashboardSnapshot(raw = {}) {
  return {
    kpis: {
      totalRevenue: Number(raw.totalRevenue ?? 0),
      totalOrders: Number(raw.totalOrders ?? 0),
      totalProducts: Number(raw.totalProducts ?? 0),
      totalUsers: Number(raw.totalUsers ?? 0),
    },
    fetchedAt: new Date().toISOString(),
  };
}

/**
 * Map KPI object to display-ready card descriptors.
 * @param {DashboardKPIs} kpis
 * @returns {KPIValue[]}
 */
export function kpisToCardValues(kpis) {
  return [
    { key: 'totalRevenue', label: 'Total Revenue', value: kpis.totalRevenue, format: 'currency' },
    { key: 'totalOrders', label: 'Total Orders', value: kpis.totalOrders, format: 'number' },
    { key: 'totalProducts', label: 'Products', value: kpis.totalProducts, format: 'number' },
    { key: 'totalUsers', label: 'Clients', value: kpis.totalUsers, format: 'number' },
  ];
}

/**
 * True when the store has no meaningful activity yet (all KPIs zero).
 * @param {DashboardKPIs} kpis
 */
export function isDashboardEmpty(kpis) {
  return (
    kpis.totalRevenue === 0
    && kpis.totalOrders === 0
    && kpis.totalProducts === 0
    && kpis.totalUsers === 0
  );
}

/**
 * @param {string} orderId
 * @returns {string}
 */
export function formatOrderNumber(orderId) {
  return `#${String(orderId).slice(0, 8).toUpperCase()}`;
}

/**
 * @param {number | null | undefined} stock
 * @returns {LowStockSeverity}
 */
export function getLowStockSeverity(stock) {
  const s = Number(stock ?? 0);
  if (s <= 0) return 'out';
  if (s <= 2) return 'critical';
  return 'warning';
}

/** @param {LowStockSeverity} severity */
export function getLowStockSeverityLabel(severity) {
  const labels = {
    out: 'Out of Stock',
    critical: 'Critical',
    warning: 'Warning',
  };
  return labels[severity] || 'Warning';
}

/** @param {LowStockSeverity} severity */
export function getLowStockSeverityStyles(severity) {
  const styles = {
    out: 'text-red-400 bg-red-400/10 border-red-400/20',
    critical: 'text-orange-400 bg-orange-400/10 border-orange-400/20',
    warning: 'text-yellow-400 bg-yellow-400/10 border-yellow-400/20',
  };
  return styles[severity] || styles.warning;
}

/**
 * @param {string} dateStr ISO timestamp
 * @param {number} [nowMs] Optional fixed "now" for tests
 */
export function formatRelativeTime(dateStr, nowMs = Date.now()) {
  const then = new Date(dateStr).getTime();
  if (Number.isNaN(then)) return '—';
  const diffSec = Math.floor((nowMs - then) / 1000);
  if (diffSec < 0) return 'just now';
  if (diffSec < 60) return 'just now';
  const diffMin = Math.floor(diffSec / 60);
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return `${diffHr}h ago`;
  const diffDay = Math.floor(diffHr / 24);
  if (diffDay < 7) return `${diffDay}d ago`;
  return new Date(dateStr).toLocaleDateString('en-KE', { day: 'numeric', month: 'short' });
}

/**
 * @param {{ event_type: string, payload?: object }} event
 */
export function describeOrderEvent(event) {
  const payload = event.payload || {};
  const statusLabel = (key) => ORDER_STATUSES[key]?.label || String(key || '').replace(/_/g, ' ');

  switch (event.event_type) {
    case 'order_placed':
      return 'Order Created';
    case 'order_cancelled':
      return 'Cancelled';
    case 'payment_status_changed':
      if (payload.to === 'paid') return 'Payment Confirmed';
      if (payload.to === 'refunded') return 'Payment Refunded';
      return `Payment ${statusLabel(payload.to) || 'Updated'}`;
    case 'status_changed':
      if (payload.to === 'ready_for_pickup') return 'Ready for Pickup';
      if (payload.to === 'delivered') return 'Delivered';
      if (payload.to === 'cancelled') return 'Cancelled';
      if (payload.to) return `Status → ${statusLabel(payload.to)}`;
      return 'Status Updated';
    default:
      return String(event.event_type || 'Event').replace(/_/g, ' ');
  }
}

/**
 * @param {string} eventType
 * @param {object} [payload]
 * @returns {ActivityIconKey}
 */
export function getEventIconKey(eventType, payload = {}) {
  if (eventType === 'order_placed') return 'placed';
  if (eventType === 'order_cancelled') return 'cancelled';
  if (eventType === 'payment_status_changed') return 'payment';
  if (eventType === 'status_changed') {
    if (payload.to === 'ready_for_pickup') return 'pickup';
    if (payload.to === 'delivered') return 'delivered';
    if (payload.to === 'shipped') return 'shipped';
    return 'status';
  }
  return 'default';
}

/**
 * @param {object} row Supabase order row with profiles embed
 * @returns {RecentOrderRow}
 */
export function mapRecentOrderRow(row) {
  return {
    id: row.id,
    orderNumber: formatOrderNumber(row.id),
    customerName: row.profiles?.full_name || 'Guest',
    status: row.status,
    paymentStatus: row.payment_status || 'pending',
    fulfillmentType: row.delivery_type || null,
    total: Number(row.total || 0),
    createdAt: row.created_at,
  };
}

/**
 * @param {object} row Supabase product row
 * @returns {LowStockProductRow}
 */
export function mapLowStockProductRow(row) {
  const stock = Number(row.stock ?? 0);
  return {
    id: row.id,
    name: row.name,
    sku: String(row.id).slice(0, 8).toUpperCase(),
    stock,
    threshold: LOW_STOCK_THRESHOLD,
    severity: getLowStockSeverity(stock),
  };
}

/**
 * @param {object} row Supabase order_events row with orders embed
 * @returns {ActivityEventRow}
 */
export function mapActivityEventRow(row) {
  return {
    id: row.id,
    orderId: row.order_id,
    orderNumber: formatOrderNumber(row.order_id),
    eventType: row.event_type,
    description: describeOrderEvent(row),
    iconKey: getEventIconKey(row.event_type, row.payload),
    userName: row.orders?.profiles?.full_name || null,
    createdAt: row.created_at,
  };
}
