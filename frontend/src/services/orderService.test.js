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
    addToCart: vi.fn(),
  },
}));

vi.mock('@/services/notificationService', () => ({
  notificationService: {
    emitSafe: vi.fn(() => Promise.resolve({})),
  },
}));

describe('orderService', () => {
  beforeEach(() => {
    rpcMock.mockReset();
    fromMock.mockReset();
    vi.clearAllMocks();
  });

  it('cancelOrder calls cancel_order RPC', async () => {
    const chain = makeQuery({ data: { id: 'order-1', user_id: 'user-1' }, error: null });
    fromMock.mockReturnValue(chain);
    rpcMock.mockResolvedValue({ error: null });
    const { cancelOrder } = await import('./orderService');
    await cancelOrder('order-1');
    expect(rpcMock).toHaveBeenCalledWith('cancel_order', { p_order_id: 'order-1' });
  });

  it('cancelOrder propagates RPC errors', async () => {
    const chain = makeQuery({ data: { id: 'order-1', user_id: 'user-1' }, error: null });
    fromMock.mockReturnValue(chain);
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
      p_payment_method: 'cod',
      p_coupon_code: null,
      p_loyalty_points: 0,
      p_gift_card_code: null,
      p_gift_card_amount: 0,
      p_discount_amount: 0,
      p_free_delivery: false,
      p_promotions_applied: [],
      p_referral_code: null,
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

  it('reorder adds available items and reports skipped ones', async () => {
    const { cartService } = await import('@/services/cartService');
    cartService.addToCart.mockResolvedValue({ error: null });

    const orderRow = {
      id: 'order-1',
      status: 'delivered',
      total: 500,
      user_id: 'user-1',
      order_items: [
        { id: 'oi-1', product_id: 'p1', name: 'Honey', price: 500, quantity: 2 },
        { id: 'oi-2', product_id: null, name: 'Old item', price: 100, quantity: 1 },
      ],
      pickup_locations: null,
    };

    fromMock.mockImplementation((table) => {
      if (table === 'profiles') {
        const chain = makeQuery({
          data: [{ id: 'user-1', full_name: 'Sam', email: 's@x.com', phone: null }],
          error: null,
        });
        chain.in = () => chain;
        return chain;
      }
      const orderChain = makeQuery({ data: orderRow, error: null });
      orderChain.eq = () => orderChain;
      orderChain.maybeSingle = () => orderChain;
      return orderChain;
    });

    const { reorder } = await import('./orderService');
    const result = await reorder('order-1', 'user-1');

    expect(result.added).toHaveLength(1);
    expect(result.skipped).toHaveLength(1);
    expect(cartService.addToCart).toHaveBeenCalledWith('user-1', 'p1', 2);
  });
});
