import { describe, it, expect, vi, beforeEach } from 'vitest';

const rpcMock = vi.fn();
const fromMock = vi.fn();

vi.mock('@/lib/supabaseClient', () => ({
  supabase: {
    rpc: (...args) => rpcMock(...args),
    from: (...args) => fromMock(...args),
  },
}));

vi.mock('@/services/providers/paymentProvider', () => ({
  getPaymentProvider: () => ({
    id: 'mock_mpesa',
    initiateStkPush: vi.fn(async () => ({
      ok: true,
      checkoutRequestId: 'chk_1',
      merchantRequestId: 'mer_1',
      raw: { mock: true },
    })),
    queryTransaction: vi.fn(async () => ({
      status: 'paid',
      receiptNumber: 'RCP1',
      raw: { mock: true },
    })),
    parseCallback: vi.fn(async (payload) => ({
      status: payload.forceFail ? 'failed' : 'paid',
      receiptNumber: 'RCP2',
      failureReason: payload.forceFail ? 'User cancelled' : undefined,
      paymentRef: 'chk_1',
      raw: payload,
    })),
  }),
}));

vi.mock('@/services/notificationService', () => ({
  notificationService: {
    emitSafe: vi.fn(() => Promise.resolve({})),
  },
}));

describe('paymentService', () => {
  beforeEach(() => {
    vi.resetModules();
    rpcMock.mockReset();
    fromMock.mockReset();
  });

  it('createPaymentForOrder COD returns no STK action', async () => {
    const { createPaymentForOrder } = await import('./paymentService');
    const result = await createPaymentForOrder({
      orderId: 'o1',
      method: 'cod',
    });
    expect(result.requiresAction).toBe(false);
    expect(rpcMock).not.toHaveBeenCalled();
  });

  it('createPaymentForOrder mpesa creates payment and marks initiated', async () => {
    rpcMock.mockImplementation(async (name) => {
      if (name === 'create_payment_for_order') {
        return {
          data: {
            id: 'pay-1',
            order_id: 'o1',
            user_id: 'u1',
            provider: 'mock_mpesa',
            method: 'mpesa',
            status: 'pending',
            amount: 500,
            phone_number: '254712345678',
          },
          error: null,
        };
      }
      if (name === 'mark_payment_initiated') {
        return {
          data: {
            id: 'pay-1',
            order_id: 'o1',
            user_id: 'u1',
            provider: 'mock_mpesa',
            method: 'mpesa',
            status: 'initiated',
            amount: 500,
            checkout_request_id: 'chk_1',
            merchant_request_id: 'mer_1',
            phone_number: '254712345678',
          },
          error: null,
        };
      }
      return { data: null, error: null };
    });

    const { createPaymentForOrder } = await import('./paymentService');
    const result = await createPaymentForOrder({
      orderId: 'o1',
      method: 'mpesa',
      phone: '0712345678',
      amount: 500,
    });

    expect(result.requiresAction).toBe(true);
    expect(result.payment.checkoutRequestId).toBe('chk_1');
    expect(rpcMock).toHaveBeenCalledWith(
      'create_payment_for_order',
      expect.objectContaining({ p_order_id: 'o1', p_method: 'mpesa' }),
    );
  });

  it('handlePaymentCallback finalizes via RPC (idempotent path supported)', async () => {
    rpcMock.mockResolvedValue({
      data: {
        id: 'pay-1',
        order_id: 'o1',
        status: 'paid',
        amount: 100,
        receipt_number: 'RCP2',
        method: 'mpesa',
        provider: 'mock_mpesa',
      },
      error: null,
    });

    const { handlePaymentCallback } = await import('./paymentService');
    const payment = await handlePaymentCallback('pay-1', { ResultCode: 0 });
    expect(payment.status).toBe('paid');
    expect(rpcMock).toHaveBeenCalledWith(
      'finalize_payment',
      expect.objectContaining({ p_payment_id: 'pay-1', p_status: 'paid' }),
    );
  });

  it('handlePaymentCallback maps failed callbacks', async () => {
    rpcMock.mockResolvedValue({
      data: {
        id: 'pay-1',
        order_id: 'o1',
        status: 'failed',
        amount: 100,
        method: 'mpesa',
        provider: 'mock_mpesa',
        failure_reason: 'User cancelled',
      },
      error: null,
    });

    const { handlePaymentCallback } = await import('./paymentService');
    const payment = await handlePaymentCallback('pay-1', { forceFail: true });
    expect(payment.status).toBe('failed');
  });
});
