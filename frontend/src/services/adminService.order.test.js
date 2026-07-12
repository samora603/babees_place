import { describe, it, expect, vi, beforeEach } from 'vitest';

const rpcMock = vi.fn();

vi.mock('@/lib/supabaseClient', () => ({
  supabase: {
    rpc: (...args) => rpcMock(...args),
    from: () => ({
      select: () => ({ eq: () => ({ single: () => Promise.resolve({ data: {}, error: null }) }) }),
      update: () => ({ eq: () => ({ select: () => ({ single: () => Promise.resolve({ data: {}, error: null }) }) }) }),
    }),
  },
}));

describe('adminService order RPCs', () => {
  beforeEach(() => {
    rpcMock.mockReset();
  });

  it('updateOrderStatus uses cancel_order for cancelled status', async () => {
    rpcMock.mockResolvedValue({ error: null });
    const { adminService } = await import('./adminService');
    await adminService.updateOrderStatus('order-1', { status: 'cancelled', note: 'test' });
    expect(rpcMock).toHaveBeenCalledWith('cancel_order', { p_order_id: 'order-1' });
  });

  it('updateOrderStatus uses update_order_status for other statuses', async () => {
    rpcMock.mockResolvedValue({ error: null });
    const { adminService } = await import('./adminService');
    await adminService.updateOrderStatus('order-1', { status: 'confirmed', note: 'ok' });
    expect(rpcMock).toHaveBeenCalledWith('update_order_status', {
      p_order_id: 'order-1',
      p_status: 'confirmed',
      p_note: 'ok',
    });
  });

  it('updateOrderPaymentStatus calls update_order_payment_status RPC', async () => {
    rpcMock.mockResolvedValue({ error: null });
    const { adminService } = await import('./adminService');
    await adminService.updateOrderPaymentStatus('order-1', { paymentStatus: 'paid' });
    expect(rpcMock).toHaveBeenCalledWith('update_order_payment_status', {
      p_order_id: 'order-1',
      p_payment_status: 'paid',
      p_note: null,
    });
  });
});
