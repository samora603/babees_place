/** Shared chart palette aligned with the admin design system. */

export const CHART_AXIS = {
  tick: '#94a3b8',
  grid: 'rgba(212, 175, 55, 0.08)',
};

export const CHART_BRAND = {
  primary: '#d4af37',
  secondary: '#b8941f',
  accent: '#f0c654',
};

export const STATUS_CHART_COLORS = {
  pending: '#facc15',
  confirmed: '#60a5fa',
  processing: '#c084fc',
  ready_for_pickup: '#fbbf24',
  shipped: '#22d3ee',
  delivered: '#4ade80',
  cancelled: '#f87171',
};

export const PAYMENT_CHART_COLORS = {
  pending: '#facc15',
  paid: '#4ade80',
  refunded: '#60a5fa',
  failed: '#f87171',
};

export const FULFILLMENT_CHART_COLORS = {
  pickup: '#d4af37',
  delivery: '#38bdf8',
};

export const REVENUE_TREND_COLORS = ['#d4af37', '#f0c654', '#b8941f', '#a67c00'];

/** @param {Record<string, string>} map @param {string} key @param {number} index */
export function chartColorForKey(map, key, index = 0) {
  return map[key] || REVENUE_TREND_COLORS[index % REVENUE_TREND_COLORS.length];
}
