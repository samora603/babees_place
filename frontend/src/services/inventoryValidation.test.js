import { describe, it, expect } from 'vitest';
import {
  validateLineForCheckout,
  validateCartForCheckout,
  validateProductForCart,
} from '@/services/inventoryValidation';

const product = (overrides = {}) => ({
  id: 'p1',
  name: 'Kalimba',
  stock: 10,
  is_active: true,
  ...overrides,
});

describe('inventoryValidation', () => {
  describe('validateLineForCheckout', () => {
    it('passes valid line', () => {
      expect(validateLineForCheckout(product(), 2).valid).toBe(true);
    });

    it('rejects inactive product', () => {
      const result = validateLineForCheckout(product({ is_active: false }), 1);
      expect(result.valid).toBe(false);
      expect(result.error).toMatch(/no longer available/);
    });

    it('rejects insufficient stock', () => {
      const result = validateLineForCheckout(product({ stock: 2 }), 5);
      expect(result.valid).toBe(false);
      expect(result.error).toMatch(/Insufficient stock/);
    });

    it('rejects missing product', () => {
      expect(validateLineForCheckout(null, 1).valid).toBe(false);
    });
  });

  describe('validateCartForCheckout', () => {
    it('passes when all lines valid', () => {
      const items = [{ id: 'c1', product_id: 'p1', quantity: 1, product: product() }];
      expect(validateCartForCheckout(items).valid).toBe(true);
    });

    it('collects issues for invalid lines', () => {
      const items = [
        { id: 'c1', product_id: 'p1', quantity: 99, product: product({ stock: 2 }) },
      ];
      const result = validateCartForCheckout(items);
      expect(result.valid).toBe(false);
      expect(result.issues).toHaveLength(1);
    });
  });

  describe('validateProductForCart', () => {
    it('allows add within stock', () => {
      expect(validateProductForCart(product(), 2, 3).valid).toBe(true);
    });

    it('rejects when total exceeds stock', () => {
      const result = validateProductForCart(product({ stock: 5 }), 2, 4);
      expect(result.valid).toBe(false);
    });

    it('rejects inactive product', () => {
      expect(validateProductForCart(product({ is_active: false }), 1).valid).toBe(false);
    });

    it('rejects out of stock', () => {
      expect(validateProductForCart(product({ stock: 0 }), 1).valid).toBe(false);
    });
  });
});
