import { describe, it, expect, vi, beforeEach } from 'vitest';
import { makeQuery } from '@/test/supabaseMock';

const fromMock = vi.fn();

vi.mock('@/lib/supabaseClient', () => ({
  supabase: {
    from: (...args) => fromMock(...args),
  },
}));

describe('productService', () => {
  beforeEach(() => {
    fromMock.mockReset();
  });

  it('getProducts applies featured filter', async () => {
    const eqCalls = [];
    const chain = makeQuery({ data: [{ id: '1', featured: true }], error: null, count: 1 });
    chain.eq = (col, val) => {
      eqCalls.push([col, val]);
      return chain;
    };
    fromMock.mockReturnValue(chain);

    const { productService } = await import('./productService');
    await productService.getProducts({ featured: true, limit: 8 });

    expect(eqCalls.some(([col, val]) => col === 'featured' && val === true)).toBe(true);
  });

  it('getProduct resolves by UUID', async () => {
    const product = { id: '550e8400-e29b-41d4-a716-446655440000', slug: 'guitar' };
    fromMock.mockReturnValue(makeQuery({ data: product, error: null }));

    const { productService } = await import('./productService');
    const { data } = await productService.getProduct('550e8400-e29b-41d4-a716-446655440000');

    expect(data.data).toEqual(product);
  });

  it('getProduct resolves by slug', async () => {
    const product = { id: '1', slug: 'acoustic-guitar' };
    fromMock.mockReturnValue(makeQuery({ data: product, error: null }));

    const { productService } = await import('./productService');
    const { data } = await productService.getProduct('acoustic-guitar');

    expect(data.data).toEqual(product);
  });

  it('getProduct returns null for empty param', async () => {
    const { productService } = await import('./productService');
    const { data } = await productService.getProduct('');
    expect(data.data).toBeNull();
    expect(fromMock).not.toHaveBeenCalled();
  });

  it('getProducts filters inactive by default', async () => {
    const eqCalls = [];
    const chain = makeQuery({ data: [], error: null, count: 0 });
    chain.eq = (col, val) => {
      eqCalls.push([col, val]);
      return chain;
    };
    fromMock.mockReturnValue(chain);

    const { productService } = await import('./productService');
    await productService.getProducts({});

    expect(eqCalls.some(([col, val]) => col === 'is_active' && val === true)).toBe(true);
  });
});
