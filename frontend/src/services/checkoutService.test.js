import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('@/services/customerProfileService', () => ({
  customerProfileService: {
    getProfileBundle: vi.fn(),
  },
}));

vi.mock('@/services/orderService', () => ({
  orderService: {
    getActivePickupLocations: vi.fn(),
    placeOrder: vi.fn(),
  },
}));

describe('checkoutService', () => {
  beforeEach(() => {
    vi.resetModules();
  });

  it('getCheckoutBootstrap merges locations and profile bundle', async () => {
    const { customerProfileService } = await import('@/services/customerProfileService');
    const { orderService } = await import('@/services/orderService');

    orderService.getActivePickupLocations.mockResolvedValue({
      data: [{ id: 'loc-1', name: 'Hub' }],
    });
    customerProfileService.getProfileBundle.mockResolvedValue({
      data: {
        addresses: [{ id: 'a1', isDefault: true, streetAddress: 'St', town: 'Town', county: 'C', phone: '+254712345678', recipientName: 'Jane', label: 'home' }],
        preferences: { preferredFulfillment: 'pickup', preferredPickupLocationId: 'loc-1' },
      },
      error: null,
    });

    const { getCheckoutBootstrap } = await import('./checkoutService');
    const result = await getCheckoutBootstrap();
    expect(result.pickupLocations).toHaveLength(1);
    expect(result.addresses).toHaveLength(1);
    expect(result.preferences.preferredFulfillment).toBe('pickup');
  });

  it('placeExpressOrder delegates to orderService.placeOrder', async () => {
    const { orderService } = await import('@/services/orderService');
    orderService.placeOrder.mockResolvedValue({ order: { id: 'order-1' } });

    const { placeExpressOrder } = await import('./checkoutService');
    const evaluation = {
      eligible: true,
      deliveryType: 'pickup',
      pickupLocationId: 'loc-1',
    };
    const result = await placeExpressOrder('user-1', evaluation);
    expect(orderService.placeOrder).toHaveBeenCalledWith('user-1', {
      deliveryType: 'pickup',
      pickupLocationId: 'loc-1',
      deliveryAddress: null,
      customerNote: null,
      paymentMethod: 'cod',
    });
    expect(result.order.id).toBe('order-1');
  });
});
