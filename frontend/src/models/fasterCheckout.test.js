import { describe, it, expect } from 'vitest';
import {
  evaluateExpressCheckout,
  buildExpressFulfillment,
  summarizeReorderResult,
} from './fasterCheckout';

const sampleAddress = {
  id: 'addr-1',
  label: 'home',
  recipientName: 'Jane',
  phone: '+254712345678',
  county: 'Nairobi',
  town: 'Westlands',
  streetAddress: '123 Main St',
  additionalDirections: '',
  isDefault: true,
};

describe('fasterCheckout model', () => {
  it('rejects express checkout when cart is invalid', () => {
    const result = evaluateExpressCheckout({
      preferences: { preferredFulfillment: 'pickup', preferredPickupLocationId: 'loc-1' },
      pickupLocations: [{ id: 'loc-1', name: 'Hub' }],
      cartValid: false,
    });
    expect(result.eligible).toBe(false);
    expect(result.reason).toBe('cart_invalid');
  });

  it('allows express pickup when preference and location are valid', () => {
    const result = evaluateExpressCheckout({
      preferences: { preferredFulfillment: 'pickup', preferredPickupLocationId: 'loc-1' },
      pickupLocations: [{ id: 'loc-1', name: 'Hub' }],
      cartValid: true,
    });
    expect(result.eligible).toBe(true);
    expect(result.deliveryType).toBe('pickup');
    expect(result.summary).toContain('Hub');
  });

  it('allows express delivery with default saved address', () => {
    const result = evaluateExpressCheckout({
      preferences: { preferredFulfillment: 'delivery' },
      addresses: [sampleAddress],
      pickupLocations: [],
      cartValid: true,
    });
    expect(result.eligible).toBe(true);
    expect(result.deliveryType).toBe('delivery');
    expect(result.summary).toContain('123 Main St');
  });

  it('buildExpressFulfillment returns pickup payload', () => {
    const evaluation = {
      eligible: true,
      deliveryType: 'pickup',
      pickupLocationId: 'loc-1',
    };
    expect(buildExpressFulfillment(evaluation)).toEqual({
      deliveryType: 'pickup',
      pickupLocationId: 'loc-1',
      deliveryAddress: null,
      customerNote: null,
    });
  });

  it('buildExpressFulfillment returns delivery payload', () => {
    const evaluation = {
      eligible: true,
      deliveryType: 'delivery',
      deliveryAddress: {
        line1: '123 Main St',
        line2: 'Nairobi',
        city: 'Westlands',
        phone: '+254712345678',
        notes: '',
      },
    };
    const payload = buildExpressFulfillment(evaluation, 'Leave at gate');
    expect(payload.deliveryType).toBe('delivery');
    expect(payload.customerNote).toBe('Leave at gate');
    expect(payload.deliveryAddress.line1).toBe('123 Main St');
  });

  it('summarizeReorderResult handles full, partial, and empty outcomes', () => {
    expect(summarizeReorderResult({ added: [], skipped: [] }).success).toBe(false);
    expect(summarizeReorderResult({ added: [{ id: 1 }], skipped: [] }).success).toBe(true);
    expect(summarizeReorderResult({ added: [{ id: 1 }], skipped: [{ item: {}, reason: 'x' }] }).partial).toBe(true);
  });
});
