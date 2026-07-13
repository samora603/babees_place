import { describe, it, expect, vi, beforeEach } from 'vitest';

const getMyOrders = vi.fn();
const getProductById = vi.fn();

vi.mock('@/services/orderService', () => ({
  orderService: {
    getMyOrders: (...args) => getMyOrders(...args),
  },
}));

vi.mock('@/services/productService', () => ({
  productService: {
    getProductById: (...args) => getProductById(...args),
  },
}));

describe('buyAgainService', () => {
  beforeEach(() => {
    vi.resetModules();
    getMyOrders.mockReset();
    getProductById.mockReset();
  });

  it('returns empty when userId missing', async () => {
    const { getBuyAgainProducts } = await import('./buyAgainService');
    const { data } = await getBuyAgainProducts(null);
    expect(data).toEqual([]);
  });

  it('ranks by purchase frequency and hides unavailable', async () => {
    getMyOrders.mockResolvedValue({
      data: {
        data: [
          {
            status: 'delivered',
            created_at: '2026-07-01',
            items: [
              { product_id: 'p1', quantity: 2 },
              { product_id: 'p2', quantity: 1 },
            ],
          },
          {
            status: 'confirmed',
            created_at: '2026-07-10',
            items: [{ product_id: 'p1', quantity: 1 }],
          },
          {
            status: 'cancelled',
            items: [{ product_id: 'p3', quantity: 9 }],
          },
        ],
      },
    });

    getProductById.mockImplementation(async (id) => {
      if (id === 'p1') {
        return {
          data: { data: { id: 'p1', name: 'Honey', stock: 5, is_active: true } },
          error: null,
        };
      }
      if (id === 'p2') {
        return {
          data: { data: { id: 'p2', name: 'Tea', stock: 0, is_active: true } },
          error: null,
        };
      }
      return { data: { data: null }, error: null };
    });

    const { getBuyAgainProducts } = await import('./buyAgainService');
    const { data } = await getBuyAgainProducts('user-1', { limit: 10 });

    expect(data.map((p) => p.id)).toEqual(['p1']);
    expect(data[0].buyAgainQuantity).toBe(3);
  });
});
