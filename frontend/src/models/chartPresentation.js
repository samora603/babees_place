/**
 * Presentation adapters for dashboard charts (no business rules — shapes API data for UI).
 */

import { revenueSummaryToDisplayItems } from '@/models/analytics';

/**
 * @typedef {Object} ChartPoint
 * @property {string} key
 * @property {string} label
 * @property {number} value
 */

/**
 * @typedef {import('@/models/analytics').TopProductRow & { revenueBarPercent: number }} TopProductDisplayRow
 */

/**
 * @typedef {import('@/models/analytics').TopCategoryRow & { revenuePercent: number }} TopCategoryDisplayRow
 */

/**
 * @param {import('@/models/analytics').RevenueSummary} summary
 * @returns {ChartPoint[]}
 */
export function revenueSummaryToChartData(summary) {
  return revenueSummaryToDisplayItems(summary).map((item) => ({
    key: item.key,
    label: item.label,
    value: Number(item.value ?? 0),
  }));
}

/**
 * @param {import('@/models/analytics').StatusCount[]} rows
 * @returns {ChartPoint[]}
 */
export function statusCountsToChartData(rows = []) {
  return rows.map((row) => ({
    key: row.key,
    label: row.label,
    value: Number(row.count ?? 0),
  }));
}

/**
 * @param {ChartPoint[]} data
 */
export function isChartDataEmpty(data) {
  return !data?.length || data.every((point) => (point.value ?? 0) === 0);
}

/**
 * @param {import('@/models/analytics').TopProductRow[]} products
 * @returns {TopProductDisplayRow[]}
 */
export function topProductsToDisplayRows(products = []) {
  const maxRevenue = Math.max(...products.map((p) => p.revenueGenerated), 0);
  return products.map((product) => ({
    ...product,
    revenueBarPercent: maxRevenue > 0 ? (product.revenueGenerated / maxRevenue) * 100 : 0,
  }));
}

/**
 * @param {import('@/models/analytics').TopCategoryRow[]} categories
 * @returns {TopCategoryDisplayRow[]}
 */
export function topCategoriesToDisplayRows(categories = []) {
  const totalRevenue = categories.reduce((sum, c) => sum + c.revenue, 0);
  return categories.map((category) => ({
    ...category,
    revenuePercent: totalRevenue > 0 ? (category.revenue / totalRevenue) * 100 : 0,
  }));
}
