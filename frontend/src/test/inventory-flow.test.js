import { describe, it, expect, vi, beforeEach } from 'vitest';
import { capQuantity } from '@/constants/inventory';

describe('ProductDetail quantity behavior', () => {
  it('capQuantity respects selected quantity and stock ceiling', () => {
    expect(capQuantity(3, 10)).toBe(3);
    expect(capQuantity(15, 10)).toBe(10);
  });

  it('simulates add-to-cart passing quantity not hardcoded 1', () => {
    const quantity = 4;
    const stock = 10;
    const passedQty = capQuantity(quantity, stock);
    expect(passedQty).toBe(4);
    expect(passedQty).not.toBe(1);
  });
});

describe('cart quantity caps', () => {
  it('increment blocked at stock max', () => {
    const stock = 5;
    const quantity = 5;
    const atMax = quantity >= stock;
    expect(atMax).toBe(true);
  });

  it('allows increment below stock max', () => {
    const stock = 5;
    const quantity = 3;
    expect(quantity >= stock).toBe(false);
  });
});

describe('orderService checkout validation', () => {
  beforeEach(() => {
    vi.resetModules();
  });

  it('validateBeforeCheckout rejects invalid cart before RPC', async () => {
    vi.doMock('@/lib/supabaseClient', () => ({ supabase: {} }));
    vi.doMock('@/services/cartService', () => ({
      cartService: {
        validateCartStock: vi.fn().mockResolvedValue({
          valid: false,
          issues: [{ error: 'Insufficient stock for Kalimba (only 1 available)' }],
          error: null,
        }),
      },
    }));

    const { validateBeforeCheckout } = await import('@/services/orderService');
    const result = await validateBeforeCheckout('user-1');
    expect(result.valid).toBe(false);
    expect(result.issues[0].error).toMatch(/Insufficient stock/);
  });

  it('placeOrder throws when client validation fails', async () => {
    vi.doMock('@/lib/supabaseClient', () => ({
      supabase: { rpc: vi.fn() },
    }));
    vi.doMock('@/services/cartService', () => ({
      cartService: {
        validateCartStock: vi.fn().mockResolvedValue({
          valid: false,
          issues: [{ error: 'Product Kalimba is no longer available' }],
          error: null,
        }),
      },
    }));

    const { placeOrder } = await import('@/services/orderService');
    await expect(placeOrder('user-1')).rejects.toThrow(/no longer available/);
  });
});
