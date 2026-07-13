import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import {
  RECENTLY_VIEWED_LIMIT,
  clearRecentlyViewed,
  getRecentlyViewed,
  trackView,
  toViewedSnapshot,
} from '@/services/recentlyViewedService';

describe('recentlyViewedService', () => {
  beforeEach(() => {
    clearRecentlyViewed();
    localStorage.clear();
  });

  afterEach(() => {
    clearRecentlyViewed();
    localStorage.clear();
  });

  it('toViewedSnapshot requires an id', () => {
    expect(toViewedSnapshot({})).toBeNull();
    expect(toViewedSnapshot({ id: 'p1', name: 'Honey' }).id).toBe('p1');
  });

  it('tracks newest first and dedupes', () => {
    trackView({ id: 'a', name: 'A' });
    trackView({ id: 'b', name: 'B' });
    trackView({ id: 'a', name: 'A again' });

    const list = getRecentlyViewed();
    expect(list.map((p) => p.id)).toEqual(['a', 'b']);
    expect(list[0].name).toBe('A again');
  });

  it('caps at RECENTLY_VIEWED_LIMIT', () => {
    for (let i = 0; i < RECENTLY_VIEWED_LIMIT + 5; i += 1) {
      trackView({ id: `p${i}`, name: `P${i}` });
    }
    expect(getRecentlyViewed()).toHaveLength(RECENTLY_VIEWED_LIMIT);
    expect(getRecentlyViewed()[0].id).toBe(`p${RECENTLY_VIEWED_LIMIT + 4}`);
  });

  it('persists to localStorage', () => {
    trackView({ id: 'x', name: 'X' });
    const raw = JSON.parse(localStorage.getItem('babees_recently_viewed_v1'));
    expect(raw[0].id).toBe('x');
  });
});
