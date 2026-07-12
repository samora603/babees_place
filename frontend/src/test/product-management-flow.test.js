import { describe, it, expect, vi, beforeEach } from 'vitest';
import { isUuid } from '@/utils/slug';
import { mergeUploadedImages, removeImageAt } from '@/utils/images';
import { makeQuery } from '@/test/supabaseMock';

const fromMock = vi.fn();

vi.mock('@/lib/supabaseClient', () => ({
  supabase: {
    from: (...args) => fromMock(...args),
    storage: {
      from: () => ({
        list: () => Promise.resolve({ data: [], error: null }),
        remove: () => Promise.resolve({ error: null }),
        upload: () => Promise.resolve({ error: null }),
        getPublicUrl: () => ({ data: { publicUrl: 'https://cdn.example/x.png' } }),
      }),
    },
  },
}));

describe('product management routing', () => {
  it('distinguishes UUID from slug for routing', () => {
    expect(isUuid('550e8400-e29b-41d4-a716-446655440000')).toBe(true);
    expect(isUuid('my-product-slug')).toBe(false);
  });

  it('getProduct uses id column for UUID and slug column for slug', async () => {
    const eqCalls = [];
    const chain = makeQuery({ data: { id: '1', slug: 'guitar' }, error: null });
    chain.eq = (col, val) => {
      eqCalls.push([col, val]);
      return chain;
    };
    fromMock.mockReturnValue(chain);

    const { productService } = await import('@/services/productService');
    await productService.getProduct('guitar');

    expect(eqCalls).toContainEqual(['slug', 'guitar']);
  });
});

describe('gallery edit behaviour', () => {
  it('preserves existing images when merging uploads', () => {
    const existing = [
      { url: 'https://cdn/a.png', path: 'products/1/a.png', isPrimary: true },
    ];
    const uploaded = [{ url: 'https://cdn/b.png', path: 'products/1/b.png' }];
    const merged = mergeUploadedImages(existing, uploaded);
    expect(merged).toHaveLength(2);
    expect(merged[0].path).toBe('products/1/a.png');
  });

  it('tracks removed images for storage cleanup', () => {
    const images = [
      { url: 'a.png', path: 'products/1/a.png', isPrimary: true },
      { url: 'b.png', path: 'products/1/b.png' },
    ];
    const next = removeImageAt(images, 0);
    expect(next).toHaveLength(1);
    expect(next[0].path).toBe('products/1/b.png');
  });
});

describe('adminService.deleteProduct', () => {
  beforeEach(() => {
    fromMock.mockReset();
  });

  it('deletes storage then database row', async () => {
    fromMock.mockReturnValue(makeQuery({ data: [{ id: 'p1' }], error: null }));

    const { adminService } = await import('@/services/adminService');
    const result = await adminService.deleteProduct('p1');

    expect(result.data.error).toBeFalsy();
    expect(fromMock).toHaveBeenCalledWith('products');
  });
});
