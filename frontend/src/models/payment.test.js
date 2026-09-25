import { describe, it, expect } from 'vitest';
import {
  canRetryPayment,
  canTransitionPaymentStatus,
  getLatestPayment,
  mapPayment,
  isPaymentExpired,
} from '@/models/payment';

describe('payment model', () => {
  it('mapPayment normalizes DB row', () => {
    const mapped = mapPayment({
      id: 'pay-1',
      order_id: 'ord-1',
      user_id: 'u1',
      provider: 'mock_mpesa',
      method: 'mpesa',
      status: 'paid',
      amount: '500.00',
      phone_number: '254712345678',
      receipt_number: 'ABC',
      created_at: '2026-07-13T10:00:00Z',
    });
    expect(mapped.orderId).toBe('ord-1');
    expect(mapped.amount).toBe(500);
    expect(mapped.receiptNumber).toBe('ABC');
  });

  it('canTransitionPaymentStatus blocks regressing paid except refund', () => {
    expect(canTransitionPaymentStatus('paid', 'failed')).toBe(false);
    expect(canTransitionPaymentStatus('paid', 'refunded')).toBe(true);
    expect(canTransitionPaymentStatus('initiated', 'paid')).toBe(true);
  });

  it('getLatestPayment sorts by createdAt desc', () => {
    const latest = getLatestPayment([
      { id: 'a', createdAt: '2026-01-01' },
      { id: 'b', createdAt: '2026-07-01' },
    ]);
    expect(latest.id).toBe('b');
  });

  it('canRetryPayment is disabled — Payment on Delivery only', () => {
    expect(canRetryPayment({ status: 'pending', paymentStatus: 'paid', paymentMethod: 'mpesa' })).toBe(false);
    expect(
      canRetryPayment(
        { status: 'pending', paymentStatus: 'failed', paymentMethod: 'mpesa' },
        { status: 'failed', method: 'mpesa' },
      ),
    ).toBe(false);
    expect(canRetryPayment({ status: 'pending', paymentStatus: 'pending', paymentMethod: 'cod' })).toBe(false);
  });

  it('isPaymentExpired respects expiresAt', () => {
    expect(isPaymentExpired({ expiresAt: '2000-01-01T00:00:00Z' })).toBe(true);
    expect(isPaymentExpired({ expiresAt: '2999-01-01T00:00:00Z' })).toBe(false);
  });
});
