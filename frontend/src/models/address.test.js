import { describe, it, expect } from 'vitest';
import {
  mapAddressRow,
  mapAddressToDbPayload,
  validateAddressInput,
  addressToCheckoutDelivery,
  getDefaultAddress,
  ADDRESS_LABELS,
} from './address';

const sampleRow = {
  id: 'addr-1',
  user_id: 'user-1',
  label: 'home',
  recipient_name: 'Jane Doe',
  phone: '+254712345678',
  county: 'Nairobi',
  town: 'Westlands',
  street_address: '123 Main St',
  additional_directions: 'Gate B',
  is_default: true,
  created_at: '2026-07-13T00:00:00Z',
  updated_at: '2026-07-13T00:00:00Z',
};

describe('address model', () => {
  it('mapAddressRow maps snake_case to camelCase', () => {
    const mapped = mapAddressRow(sampleRow);
    expect(mapped.recipientName).toBe('Jane Doe');
    expect(mapped.streetAddress).toBe('123 Main St');
    expect(mapped.isDefault).toBe(true);
  });

  it('mapAddressToDbPayload normalizes phone and trims fields', () => {
    const payload = mapAddressToDbPayload({
      label: 'work',
      recipientName: ' John ',
      phone: '0712345678',
      county: 'Kiambu',
      town: 'Ruiru',
      streetAddress: '456 Road',
      additionalDirections: '',
      isDefault: false,
    });
    expect(payload.recipient_name).toBe('John');
    expect(payload.phone).toBe('+254712345678');
    expect(payload.additional_directions).toBeNull();
  });

  it('validateAddressInput rejects incomplete data', () => {
    const result = validateAddressInput({});
    expect(result.valid).toBe(false);
    expect(result.errors.recipientName).toBeTruthy();
    expect(result.errors.phone).toBeTruthy();
  });

  it('validateAddressInput accepts valid Kenyan phone', () => {
    const result = validateAddressInput({
      label: 'home',
      recipientName: 'Jane',
      phone: '+254712345678',
      county: 'Nairobi',
      town: 'Nairobi',
      streetAddress: '1 Ave',
    });
    expect(result.valid).toBe(true);
  });

  it('addressToCheckoutDelivery maps to existing order JSONB shape', () => {
    const delivery = addressToCheckoutDelivery(mapAddressRow(sampleRow));
    expect(delivery).toEqual({
      line1: '123 Main St',
      line2: 'Nairobi',
      city: 'Westlands',
      phone: '+254712345678',
      notes: 'Recipient: Jane Doe · Gate B',
    });
  });

  it('getDefaultAddress prefers isDefault then first address', () => {
    const addresses = [
      { id: 'a', isDefault: false },
      { id: 'b', isDefault: true },
    ];
    expect(getDefaultAddress(addresses).id).toBe('b');
    expect(getDefaultAddress([{ id: 'c', isDefault: false }]).id).toBe('c');
    expect(getDefaultAddress([])).toBeNull();
  });

  it('ADDRESS_LABELS covers all labels', () => {
    expect(Object.keys(ADDRESS_LABELS)).toEqual(['home', 'work', 'other']);
  });
});
