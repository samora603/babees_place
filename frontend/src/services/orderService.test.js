import { describe, it, expect, vi, beforeEach } from 'vitest';
import { makeQuery } from '@/test/supabaseMock';

const rpcMock = vi.fn();
const fromMock = vi.fn();

vi.mock('@/lib/supabaseClient', () => ({
  supabase: {
    rpc: (...args) => rpcMock(...args),
    from: (...args) => fromMock(...args),
  },
}));

vi.mock('@/services/cartService', () => ({
  cartService: {
    validateCartStock: vi.fn().mockResolvedValue({ valid: true, issues: [], error: null }),
  },
}));

describe('orderService', () => {
  beforeEach(() => {
    rpcMock.mockReset();
    fromMock.mockReset();
  });

  it('cancelOrder calls cancel_order RPC', async () => {
    rpcMock.mockResolvedValue({ error: null });
    const { cancelOrder } = await import('./orderService');
    await cancelOrder('order-1');
    expect(rpcMock).toHaveBeenCalledWith('cancel_order', { p_order_id: 'order-1' });
  });

  it('cancelOrder propagates RPC errors', async () => {
    rpcMock.mockResolvedValue({ error: { message: 'Unauthorized' } });
    const { cancelOrder } = await import('./orderService');
    await expect(cancelOrder('order-1')).rejects.toMatchObject({ message: 'Unauthorized' });
  });

  it('placeOrder passes fulfillment params to RPC', async () => {
    rpcMock.mockResolvedValue({ data: 'new-order-id', error: null });
    const { placeOrder } = await import('./orderService');
    const result = await placeOrder('user-1', {
      deliveryType: 'pickup',
      pickupLocationId: 'loc-1',
    });
    expect(rpcMock).toHaveBeenCalledWith('place_order', {
      p_user_id: 'user-1',
      p_delivery_type: 'pickup',
      p_pickup_location_id: 'loc-1',
      p_delivery_address: null,
      p_customer_note: null,
    });
    expect(result.order.id).toBe('new-order-id');
  });

  it('mapOrder includes fulfillment fields', async () => {
    const { mapOrder } = await import('./orderService');
    const mapped = mapOrder({
      id: 'o1',
      status: 'pending',
      payment_status: 'pending',
      total: 1200,
      delivery_fee: 200,
      delivery_type: 'delivery',
      delivery_address: { line1: 'St', city: 'Nairobi' },
      pickup_locations: null,
      order_items: [],
    });
    expect(mapped.deliveryType).toBe('delivery');
    expect(mapped.deliveryFee).toBe(200);
    expect(mapped.subtotal).toBe(1000);
  });

  it('canCancelOrder respects customer rules', async () => {
    const { canCancelOrder } = await import('./orderService');
    expect(canCancelOrder('pending', false)).toBe(true);
    expect(canCancelOrder('shipped', false)).toBe(false);
    expect(canCancelOrder('shipped', true)).toBe(true);
  });

  it('getActivePickupLocations queries active locations', async () => {
    const chain = makeQuery({ data: [], error: null });
    chain.eq = () => chain;
    chain.order = () => chain;
    chain.then = (resolve) => resolve({
      data: [{ id: '1', name: 'Hub', building: 'A', operating_hours: {} }],
      error: null,
    });
    fromMock.mockReturnValue(chain);

    const { getActivePickupLocations } = await import('./orderService');
    const { data } = await getActivePickupLocations();
    expect(data[0].name).toBe('Hub');
    expect(fromMock).toHaveBeenCalledWith('pickup_locations');
  });
});
