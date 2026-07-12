import { describe, it, expect } from 'vitest';
import { validateCheckoutForm } from '@/utils/orderValidation';
import { getAllowedNextStatuses, canCustomerCancel, canAdminCancel } from '@/utils/orderStatus';

describe('checkout fulfillment flow', () => {
  it('pickup flow requires location', () => {
    const invalid = validateCheckoutForm({ deliveryType: 'pickup', pickupLocationId: '' });
    expect(invalid.valid).toBe(false);
    const valid = validateCheckoutForm({ deliveryType: 'pickup', pickupLocationId: 'uuid' });
    expect(valid.valid).toBe(true);
  });

  it('delivery flow requires address', () => {
    const invalid = validateCheckoutForm({
      deliveryType: 'delivery',
      deliveryAddress: { line1: '', city: '', phone: '' },
    });
    expect(invalid.valid).toBe(false);
  });

  it('pickup order status path after confirmed', () => {
    expect(getAllowedNextStatuses('confirmed', 'pickup')).toEqual(['ready_for_pickup']);
    expect(getAllowedNextStatuses('ready_for_pickup', 'pickup')).toEqual(['delivered']);
  });

  it('delivery order status path after confirmed', () => {
    expect(getAllowedNextStatuses('confirmed', 'delivery')).toEqual(['processing']);
    expect(getAllowedNextStatuses('processing', 'delivery')).toEqual(['shipped']);
    expect(getAllowedNextStatuses('shipped', 'delivery')).toEqual(['delivered']);
  });
});

describe('cancellation business rules', () => {
  it('customer can only cancel early statuses', () => {
    expect(canCustomerCancel('pending')).toBe(true);
    expect(canCustomerCancel('processing')).toBe(false);
  });

  it('admin can cancel shipped but not delivered', () => {
    expect(canAdminCancel('shipped')).toBe(true);
    expect(canAdminCancel('delivered')).toBe(false);
  });
});
