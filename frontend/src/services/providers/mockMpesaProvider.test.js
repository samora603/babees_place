import { describe, it, expect } from 'vitest';
import { createMockMpesaProvider } from '@/services/providers/mockMpesaProvider';

describe('mockMpesaProvider', () => {
  it('initiates STK and eventually reports paid on query', async () => {
    const provider = createMockMpesaProvider();
    const stk = await provider.initiateStkPush({
      paymentId: 'p1',
      orderId: 'o1',
      amount: 100,
      phone: '254712345678',
    });
    expect(stk.ok).toBe(true);
    expect(stk.checkoutRequestId).toBeTruthy();

    provider.__forceSuccess(stk.checkoutRequestId);
    const query = await provider.queryTransaction(stk.checkoutRequestId);
    expect(query.status).toBe('paid');
    expect(query.receiptNumber).toMatch(/^MOCK/);
  });

  it('parseCallback handles success and failure', async () => {
    const provider = createMockMpesaProvider();
    const ok = await provider.parseCallback({ ResultCode: 0, MpesaReceiptNumber: 'XYZ' });
    expect(ok.status).toBe('paid');
    const fail = await provider.parseCallback({ ResultCode: 1032, ResultDesc: 'Cancelled' });
    expect(fail.status).toBe('failed');
  });
});
