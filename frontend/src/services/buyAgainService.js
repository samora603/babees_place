import { orderService } from '@/services/orderService';
import { productService } from '@/services/productService';
import {
  aggregateBuyAgainFrequency,
  filterRecommendable,
} from '@/models/recommendations';

/**
 * Build "Buy Again" list from the customer's order history.
 * Most frequently purchased first; unavailable products hidden.
 *
 * @param {string} userId
 * @param {{ limit?: number, excludeIds?: string[] }} [options]
 * @returns {Promise<{ data: object[], error: Error|null }>}
 */
export async function getBuyAgainProducts(userId, options = {}) {
  const limit = options.limit ?? 12;
  const excludeIds = options.excludeIds || [];

  if (!userId) {
    return { data: [], error: null };
  }

  try {
    const { data: wrapped } = await orderService.getMyOrders(userId);
    const orders = wrapped?.data || [];

    const lineItems = [];
    for (const order of orders) {
      if (order.status === 'cancelled') continue;
      const created = order.created_at || order.createdAt;
      for (const item of order.items || order.order_items || []) {
        lineItems.push({
          product_id: item.product_id,
          quantity: item.quantity,
          created_at: created,
          orderCreatedAt: created,
        });
      }
    }

    const frequency = aggregateBuyAgainFrequency(lineItems);
    if (frequency.length === 0) {
      return { data: [], error: null };
    }

    const products = [];
    for (const row of frequency) {
      if (products.length >= limit) break;
      if (excludeIds.includes(row.productId)) continue;

      const { data: res, error } = await productService.getProductById(row.productId);
      if (error || !res?.data) continue;

      const product = {
        ...res.data,
        buyAgainQuantity: row.quantity,
        lastPurchasedAt: row.lastPurchasedAt,
      };
      products.push(product);
    }

    const available = filterRecommendable(products, excludeIds, {
      requireInStock: true,
    });

    return { data: available.slice(0, limit), error: null };
  } catch (error) {
    console.error('buyAgainService.getBuyAgainProducts error:', error);
    return { data: [], error };
  }
}

export const buyAgainService = {
  getBuyAgainProducts,
};
