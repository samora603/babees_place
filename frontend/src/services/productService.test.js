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

  it('escapeIlikePattern strips filter-breaking characters', async () => {
    const { escapeIlikePattern } = await import('./productService');
    expect(escapeIlikePattern('phone%_test,x')).toBe('phone\\%\\_test x');
    expect(escapeIlikePattern('  Samsung  ')).toBe('Samsung');
  });

  it('buildProductSearchOrFilter covers name and description', async () => {
    const { buildProductSearchOrFilter } = await import('./productService');
    expect(buildProductSearchOrFilter('phone')).toBe(
      'name.ilike.%phone%,description.ilike.%phone%',
    );
    expect(buildProductSearchOrFilter('phone', ['cat-1'])).toContain('category_id.in.(cat-1)');
    expect(buildProductSearchOrFilter('   ')).toBeNull();
  });

  it('getProducts applies search via or() and keeps category filter', async () => {
    const orCalls = [];
    const eqCalls = [];
    const chain = makeQuery({ data: [], error: null, count: 0 });
    chain.or = (filter) => {
      orCalls.push(filter);
      return chain;
    };
    chain.eq = (col, val) => {
      eqCalls.push([col, val]);
      return chain;
    };
    chain.ilike = () => chain;
    fromMock.mockImplementation((table) => {
      if (table === 'categories') {
        return makeQuery({ data: [{ id: 'cat-electronics' }], error: null });
      }
      return chain;
    });

    const { productService } = await import('./productService');
    await productService.getProducts({
      search: 'phone',
      category: 'cat-electronics',
      sort: 'price',
    });

    expect(orCalls.length).toBe(1);
    expect(orCalls[0]).toContain('name.ilike.%phone%');
    expect(orCalls[0]).toContain('description.ilike.%phone%');
    expect(eqCalls.some(([col, val]) => col === 'category_id' && val === 'cat-electronics')).toBe(true);
  });

  it('getProducts returns Supabase errors instead of swallowing them', async () => {
    const chain = makeQuery({ data: null, error: { message: 'query failed' }, count: null });
    chain.eq = () => chain;
    fromMock.mockReturnValue(chain);

    const { productService } = await import('./productService');
    const result = await productService.getProducts({});

    expect(result.error).toEqual({ message: 'query failed' });
    expect(result.data.data).toEqual([]);
  });

  it('getProducts returns thrown exceptions as errors', async () => {
    fromMock.mockImplementation(() => {
      throw new Error('network down');
    });

    const { productService } = await import('./productService');
    const result = await productService.getProducts({ search: 'phone' });

    expect(result.error).toBeInstanceOf(Error);
    expect(result.error.message).toBe('network down');
    expect(result.data.data).toEqual([]);
  });

  it('getProductById returns product data on success', async () => {
    const product = { id: 'prod-1', name: 'Phone Case' };
    fromMock.mockReturnValue(makeQuery({ data: product, error: null }));

    const { productService } = await import('./productService');
    const result = await productService.getProductById('prod-1');

    expect(result.data.data).toEqual(product);
    expect(result.error).toBeNull();
  });

  it('getProductById returns null data when product is not found', async () => {
    fromMock.mockReturnValue(makeQuery({ data: null, error: null }));

    const { productService } = await import('./productService');
    const result = await productService.getProductById('missing-id');

    expect(result.data.data).toBeNull();
    expect(result.error).toBeNull();
  });

  it('getProductById propagates Supabase errors', async () => {
    fromMock.mockReturnValue(makeQuery({ data: null, error: { message: 'lookup failed' } }));

    const { productService } = await import('./productService');
    const result = await productService.getProductById('prod-1');

    expect(result.data.data).toBeNull();
    expect(result.error).toEqual({ message: 'lookup failed' });
  });

  it('getProduct propagates Supabase errors', async () => {
    fromMock.mockReturnValue(makeQuery({ data: null, error: { message: 'lookup failed' } }));

    const { productService } = await import('./productService');
    const result = await productService.getProduct('acoustic-guitar');

    expect(result.data.data).toBeNull();
    expect(result.error).toEqual({ message: 'lookup failed' });
  });
});
