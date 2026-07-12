import { describe, it, expect } from 'vitest';
import {
  validateDeliveryAddress,
  validateCheckoutForm,
  buildDeliveryAddressPayload,
  validatePickupLocationForm,
} from './orderValidation';

describe('validateDeliveryAddress', () => {
  it('requires line1, city, and valid phone', () => {
    const result = validateDeliveryAddress({ line1: '123 Main', city: 'Nairobi', phone: '0712345678' });
    expect(result.valid).toBe(true);
  });

  it('rejects missing fields', () => {
    const result = validateDeliveryAddress({});
    expect(result.valid).toBe(false);
    expect(result.errors.line1).toBeTruthy();
  });

  it('rejects invalid phone', () => {
    const result = validateDeliveryAddress({ line1: 'A', city: 'B', phone: 'bad' });
    expect(result.valid).toBe(false);
    expect(result.errors.phone).toBeTruthy();
  });
});

describe('validateCheckoutForm', () => {
  it('validates pickup checkout', () => {
    const result = validateCheckoutForm({
      deliveryType: 'pickup',
      pickupLocationId: 'loc-1',
    });
    expect(result.valid).toBe(true);
  });

  it('requires pickup location for pickup', () => {
    const result = validateCheckoutForm({ deliveryType: 'pickup', pickupLocationId: '' });
    expect(result.valid).toBe(false);
    expect(result.errors.pickupLocationId).toBeTruthy();
  });

  it('validates delivery checkout', () => {
    const result = validateCheckoutForm({
      deliveryType: 'delivery',
      deliveryAddress: { line1: 'St', city: 'Nairobi', phone: '+254712345678' },
    });
    expect(result.valid).toBe(true);
  });
});

describe('buildDeliveryAddressPayload', () => {
  it('normalizes phone to +254', () => {
    const payload = buildDeliveryAddressPayload({
      line1: 'Street',
      city: 'Nairobi',
      phone: '0712345678',
    });
    expect(payload.phone).toBe('+254712345678');
  });
});

describe('validatePickupLocationForm', () => {
  it('requires name and building', () => {
    expect(validatePickupLocationForm({ name: '', building: '' }).valid).toBe(false);
    expect(validatePickupLocationForm({ name: 'Hub', building: 'Block A' }).valid).toBe(true);
  });
});
