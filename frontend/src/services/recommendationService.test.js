import { describe, it, expect, vi, beforeEach } from 'vitest';

const getProducts = vi.fn();
const getProductById = vi.fn();
const rpcMock = vi.fn();

vi.mock('@/lib/supabaseClient', () => ({
  supabase: {
    rpc: (...args) => rpcMock(...args),
  },
}));

vi.mock('@/services/productService', () => ({
  productService: {
    getProducts: (...args) => getProducts(...args),
    getProductById: (...args) => getProductById(...args),
  },
}));

describe('recommendationService', () => {
  beforeEach(() => {
    vi.resetModules();
    getProducts.mockReset();
    getProductById.mockReset();
    rpcMock.mockReset();
  });

  it('getRecommendations excludes seed and ranks same-category higher', async () => {
    rpcMock.mockResolvedValue({ data: [], error: null });
    getProducts.mockImplementation(async (params = {}) => {
      if (params.category === 'cat-1') {
        return {
          data: {
            data: [
              {
                id: 'seed',
                category_id: 'cat-1',
                price: 100,
                stock: 5,
                is_active: true,
              },
              {
                id: 'same-cat',
                category_id: 'cat-1',
                price: 110,
                stock: 5,
                is_active: true,
                created_at: '2026-07-10',
              },
            ],
          },
          error: null,
        };
      }
      return {
        data: {
          data: [
            {
              id: 'other',
              category_id: 'cat-2',
              price: 900,
              stock: 5,
              is_active: true,
              created_at: '2026-07-01',
            },
          ],
        },
        error: null,
      };
    });

    const { recommendationService, clearRecommendationCache } = await import(
      './recommendationService'
    );
    clearRecommendationCache();

    const seed = {
      id: 'seed',
      category_id: 'cat-1',
      price: 100,
      stock: 5,
      is_active: true,
    };
    const list = await recommendationService.getRecommendations({
      seed,
      limit: 5,
    });

    expect(list.every((p) => p.id !== 'seed')).toBe(true);
    expect(list[0].id).toBe('same-cat');
  });

  it('getCartCrossSell omits products already in cart', async () => {
    rpcMock.mockResolvedValue({ data: [], error: null });
    getProducts.mockResolvedValue({
      data: {
        data: [
          { id: 'in-cart', category_id: 'c1', price: 100, stock: 2, is_active: true },
          { id: 'cross', category_id: 'c1', price: 120, stock: 2, is_active: true },
        ],
      },
      error: null,
    });

    const { recommendationService, clearRecommendationCache } = await import(
      './recommendationService'
    );
    clearRecommendationCache();

    const list = await recommendationService.getCartCrossSell(
      [{ product: { id: 'in-cart', category_id: 'c1', price: 100, stock: 2 } }],
      8,
    );

    expect(list.every((p) => p.id !== 'in-cart')).toBe(true);
    expect(list.some((p) => p.id === 'cross')).toBe(true);
  });

  it('getBestSellerSignals falls back when RPC fails', async () => {
    rpcMock.mockResolvedValue({ data: null, error: { message: 'missing fn' } });
    getProducts.mockResolvedValue({
      data: {
        data: [
          { id: 'f1', featured: true, stock: 3, is_active: true, price: 50 },
        ],
      },
      error: null,
    });

    const { recommendationService, clearRecommendationCache } = await import(
      './recommendationService'
    );
    clearRecommendationCache();

    const { products } = await recommendationService.getBestSellerSignals(5);
    expect(products[0].id).toBe('f1');
  });
});
