import { describe, it, expect } from 'vitest';
import {
  SCORE_WEIGHTS,
  aggregateBuyAgainFrequency,
  dedupeProducts,
  filterRecommendable,
  getBrandSignal,
  getEffectivePrice,
  rankCrossSell,
  rankRecommendations,
  scoreCandidate,
} from '@/models/recommendations';

const honey = {
  id: 'p1',
  name: 'Wild Honey',
  category_id: 'cat-honey',
  categories: { id: 'cat-honey', name: 'Honey' },
  price: 1000,
  stock: 5,
  is_active: true,
  created_at: '2026-07-01T00:00:00Z',
};

const similarHoney = {
  id: 'p2',
  name: 'Acacia Honey',
  category_id: 'cat-honey',
  categories: { id: 'cat-honey', name: 'Honey' },
  price: 1100,
  stock: 3,
  is_active: true,
  created_at: '2026-07-02T00:00:00Z',
};

const tea = {
  id: 'p3',
  name: 'Green Tea',
  category_id: 'cat-tea',
  price: 5000,
  stock: 10,
  is_active: true,
  created_at: '2026-06-01T00:00:00Z',
};

describe('recommendations model', () => {
  it('getEffectivePrice prefers discount when lower', () => {
    expect(getEffectivePrice({ price: 100, discount_price: 80 })).toBe(80);
    expect(getEffectivePrice({ price: 100, discount_price: 120 })).toBe(100);
  });

  it('getBrandSignal returns null without brand column', () => {
    expect(getBrandSignal(honey)).toBeNull();
    expect(getBrandSignal({ brand: ' Babees ' })).toBe('babees');
  });

  it('dedupeProducts keeps first occurrence', () => {
    const result = dedupeProducts([honey, { ...honey, name: 'dup' }, tea]);
    expect(result).toHaveLength(2);
    expect(result[0].name).toBe('Wild Honey');
  });

  it('filterRecommendable hides inactive, OOS, and excluded', () => {
    const result = filterRecommendable(
      [
        honey,
        { ...tea, stock: 0 },
        { ...similarHoney, is_active: false },
        { id: 'p4', stock: 2, is_active: true },
      ],
      ['p4'],
    );
    expect(result.map((p) => p.id)).toEqual(['p1']);
  });

  it('scoreCandidate boosts same category and similar price', () => {
    const { score, reasons } = scoreCandidate(similarHoney, { seed: honey });
    expect(reasons).toContain('same_category');
    expect(reasons).toContain('similar_price');
    expect(score).toBeGreaterThanOrEqual(
      SCORE_WEIGHTS.sameCategory + SCORE_WEIGHTS.similarPrice,
    );
  });

  it('scoreCandidate applies brand when present', () => {
    const a = { ...honey, brand: 'Babees' };
    const b = { ...similarHoney, brand: 'Babees' };
    const { reasons } = scoreCandidate(b, { seed: a });
    expect(reasons).toContain('same_brand');
  });

  it('rankRecommendations excludes seed and sorts by score', () => {
    const ranked = rankRecommendations(
      [honey, similarHoney, tea],
      {
        seed: honey,
        bestSellerIds: new Set(['p3']),
        bestSellerRanks: new Map([['p3', 1]]),
      },
      10,
    );
    expect(ranked.every((p) => p.id !== 'p1')).toBe(true);
    expect(ranked[0].id).toBe('p2');
  });

  it('rankCrossSell excludes cart products', () => {
    const result = rankCrossSell(
      [honey, similarHoney, tea],
      [honey],
      {},
      8,
    );
    expect(result.every((p) => p.id !== 'p1')).toBe(true);
    expect(result[0].id).toBe('p2');
  });

  it('aggregateBuyAgainFrequency ranks by quantity then recency', () => {
    const rows = aggregateBuyAgainFrequency([
      { product_id: 'a', quantity: 1, created_at: '2026-01-01' },
      { product_id: 'b', quantity: 2, created_at: '2026-01-02' },
      { product_id: 'a', quantity: 2, created_at: '2026-02-01' },
      { product_id: null, quantity: 9 },
    ]);
    expect(rows[0].productId).toBe('a');
    expect(rows[0].quantity).toBe(3);
    expect(rows[1].productId).toBe('b');
  });
});
