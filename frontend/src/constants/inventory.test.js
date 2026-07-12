import { describe, it, expect } from 'vitest';
import {
  LOW_STOCK_THRESHOLD,
  isOutOfStock,
  isLowStock,
  isInStock,
  hasAvailableStock,
  capQuantity,
  matchesStockStatus,
} from '@/constants/inventory';

describe('inventory constants', () => {
  it('defines LOW_STOCK_THRESHOLD as 5', () => {
    expect(LOW_STOCK_THRESHOLD).toBe(5);
  });

  it('isOutOfStock', () => {
    expect(isOutOfStock(0)).toBe(true);
    expect(isOutOfStock(-1)).toBe(true);
    expect(isOutOfStock(null)).toBe(true);
    expect(isOutOfStock(1)).toBe(false);
  });

  it('isLowStock', () => {
    expect(isLowStock(3)).toBe(true);
    expect(isLowStock(5)).toBe(false);
    expect(isLowStock(0)).toBe(false);
  });

  it('isInStock', () => {
    expect(isInStock(5)).toBe(true);
    expect(isInStock(10)).toBe(true);
    expect(isInStock(4)).toBe(false);
  });

  it('hasAvailableStock', () => {
    expect(hasAvailableStock(1)).toBe(true);
    expect(hasAvailableStock(0)).toBe(false);
  });

  it('capQuantity', () => {
    expect(capQuantity(10, 5)).toBe(5);
    expect(capQuantity(0, 5)).toBe(1);
    expect(capQuantity(3, 0)).toBe(0);
  });

  describe('matchesStockStatus (admin filters)', () => {
    it('all matches everything', () => {
      expect(matchesStockStatus(0, 'all')).toBe(true);
      expect(matchesStockStatus(3, undefined)).toBe(true);
    });

    it('out', () => {
      expect(matchesStockStatus(0, 'out')).toBe(true);
      expect(matchesStockStatus(1, 'out')).toBe(false);
    });

    it('low', () => {
      expect(matchesStockStatus(3, 'low')).toBe(true);
      expect(matchesStockStatus(5, 'low')).toBe(false);
      expect(matchesStockStatus(0, 'low')).toBe(false);
    });

    it('in', () => {
      expect(matchesStockStatus(5, 'in')).toBe(true);
      expect(matchesStockStatus(4, 'in')).toBe(false);
    });
  });
});
