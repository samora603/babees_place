import { describe, it, expect } from 'vitest';
import {
  mapPreferencesRow,
  mapPreferencesToDbPayload,
  validatePreferencesInput,
  EMPTY_PREFERENCES,
} from './preferences';

describe('preferences model', () => {
  it('mapPreferencesRow maps database row', () => {
    const mapped = mapPreferencesRow({
      user_id: 'user-1',
      preferred_fulfillment: 'pickup',
      preferred_pickup_location_id: 'loc-1',
      marketing_emails: true,
      sms_notifications: false,
      created_at: '2026-07-13T00:00:00Z',
      updated_at: '2026-07-13T00:00:00Z',
    });
    expect(mapped.preferredFulfillment).toBe('pickup');
    expect(mapped.marketingEmails).toBe(true);
  });

  it('mapPreferencesRow returns null for missing row', () => {
    expect(mapPreferencesRow(null)).toBeNull();
  });

  it('mapPreferencesToDbPayload builds upsert payload', () => {
    const payload = mapPreferencesToDbPayload('user-1', {
      preferredFulfillment: 'delivery',
      preferredPickupLocationId: null,
      marketingEmails: true,
      smsNotifications: true,
      emailNotifications: true,
      orderUpdates: true,
      paymentUpdates: false,
    });
    expect(payload).toEqual({
      user_id: 'user-1',
      preferred_fulfillment: 'delivery',
      preferred_pickup_location_id: null,
      marketing_emails: true,
      sms_notifications: true,
      email_notifications: true,
      order_updates: true,
      payment_updates: false,
    });
  });

  it('validatePreferencesInput rejects invalid fulfillment', () => {
    const result = validatePreferencesInput({ preferredFulfillment: 'drone' });
    expect(result.valid).toBe(false);
  });

  it('validatePreferencesInput accepts null fulfillment', () => {
    const result = validatePreferencesInput({ ...EMPTY_PREFERENCES });
    expect(result.valid).toBe(true);
  });
});
