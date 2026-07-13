import { describe, it, expect } from 'vitest';
import { validateCheckoutForm, buildDeliveryAddressPayload } from '@/utils/orderValidation';
import { getAllowedNextStatuses, canCustomerCancel, canAdminCancel } from '@/utils/orderStatus';
import {
  addressToCheckoutDelivery,
  validateAddressInput,
  getDefaultAddress,
} from '@/models/address';

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

  it('saved address maps to checkout delivery payload', () => {
    const saved = {
      streetAddress: '10 Lane',
      county: 'Nairobi',
      town: 'Karen',
      phone: '+254712345678',
      recipientName: 'Sam',
      additionalDirections: 'Blue gate',
    };
    const delivery = addressToCheckoutDelivery(saved);
    const validation = validateCheckoutForm({
      deliveryType: 'delivery',
      deliveryAddress: delivery,
    });
    expect(validation.valid).toBe(true);
    expect(buildDeliveryAddressPayload(delivery)).toEqual(delivery);
  });

  it('new address form validates before checkout', () => {
    const invalid = validateAddressInput({
      label: 'home',
      recipientName: '',
      phone: 'bad',
      county: '',
      town: '',
      streetAddress: '',
    });
    expect(invalid.valid).toBe(false);

    const valid = validateAddressInput({
      label: 'home',
      recipientName: 'Sam',
      phone: '+254712345678',
      county: 'Nairobi',
      town: 'Westlands',
      streetAddress: '1 St',
    });
    expect(valid.valid).toBe(true);
  });

  it('getDefaultAddress selects default for checkout bootstrap', () => {
    const addresses = [
      { id: 'a', isDefault: false, streetAddress: 'A' },
      { id: 'b', isDefault: true, streetAddress: 'B' },
    ];
    const selected = getDefaultAddress(addresses);
    expect(selected.id).toBe('b');
    expect(addressToCheckoutDelivery(selected).line1).toBe('B');
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
