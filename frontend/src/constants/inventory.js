/** Shared inventory thresholds and helpers (Phase 2 WS1). */

export const LOW_STOCK_THRESHOLD = 5;

export function isOutOfStock(stock) {
  return (stock ?? 0) <= 0;
}

/** Low stock: has units but below replenishment threshold. */
export function isLowStock(stock) {
  const s = stock ?? 0;
  return s > 0 && s < LOW_STOCK_THRESHOLD;
}

/** In stock with comfortable quantity (not low, not out). */
export function isInStock(stock) {
  return (stock ?? 0) >= LOW_STOCK_THRESHOLD;
}

/** Any units available for sale (stock > 0). */
export function hasAvailableStock(stock) {
  return (stock ?? 0) > 0;
}

export function capQuantity(requested, stock) {
  const max = Math.max(0, stock ?? 0);
  if (max === 0) return 0;
  return Math.min(Math.max(1, Number(requested) || 1), max);
}

/**
 * Client-side stock-status filter matching adminService.getInventory queries.
 */
export function matchesStockStatus(stock, stockStatus) {
  if (!stockStatus || stockStatus === 'all') return true;
  const s = stock ?? 0;
  if (stockStatus === 'out') return s <= 0;
  if (stockStatus === 'low') return s > 0 && s < LOW_STOCK_THRESHOLD;
  if (stockStatus === 'in') return s >= LOW_STOCK_THRESHOLD;
  return true;
}
