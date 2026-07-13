/**
 * Unit tests for profileLookup — ensures order enrichment does not rely on
 * a non-existent PostgREST relationship between orders and profiles.
 */
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { makeQuery } from '@/test/supabaseMock';

const fromMock = vi.fn();

vi.mock('@/lib/supabaseClient', () => ({
  supabase: {
    from: (...args) => fromMock(...args),
  },
}));

describe('profileLookup', () => {
  beforeEach(() => {
    fromMock.mockReset();
    vi.resetModules();
  });

  it('attachProfilesToOrders merges profiles by user_id', async () => {
    fromMock.mockReturnValue(
      makeQuery({
        data: [{ id: 'u1', full_name: 'Ada', email: 'a@b.c', phone: '1' }],
        error: null,
      }),
    );

    const { attachProfilesToOrders } = await import('./profileLookup');
    const result = await attachProfilesToOrders([
      { id: 'o1', user_id: 'u1', total: 10 },
      { id: 'o2', user_id: 'missing', total: 5 },
    ]);

    expect(result[0].profiles.full_name).toBe('Ada');
    expect(result[1].profiles).toBeNull();
    expect(fromMock).toHaveBeenCalledWith('profiles');
  });

  it('attachProfilesToOrders returns null/empty unchanged', async () => {
    const { attachProfilesToOrders } = await import('./profileLookup');
    expect(await attachProfilesToOrders(null)).toBeNull();
    expect(await attachProfilesToOrders([])).toEqual([]);
  });
});
