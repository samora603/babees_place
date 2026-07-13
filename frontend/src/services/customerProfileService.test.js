import { describe, it, expect, vi, beforeEach } from 'vitest';
import { makeQuery } from '@/test/supabaseMock';

const getUserMock = vi.fn();
const fromMock = vi.fn();

vi.mock('@/lib/supabaseClient', () => ({
  supabase: {
    auth: { getUser: (...args) => getUserMock(...args) },
    from: (...args) => fromMock(...args),
  },
}));

describe('customerProfileService', () => {
  beforeEach(() => {
    getUserMock.mockReset();
    fromMock.mockReset();
    getUserMock.mockResolvedValue({ data: { user: { id: 'user-1' } }, error: null });
  });

  it('getPreferences returns defaults when no row exists', async () => {
    fromMock.mockReturnValue(makeQuery({ data: null, error: null }));
    const { getPreferences } = await import('./customerProfileService');
    const { data, error } = await getPreferences();
    expect(error).toBeNull();
    expect(data.userId).toBe('user-1');
    expect(data.marketingEmails).toBe(false);
  });

  it('upsertPreferences validates fulfillment', async () => {
    const { upsertPreferences } = await import('./customerProfileService');
    const { data, error } = await upsertPreferences({ preferredFulfillment: 'invalid' });
    expect(data).toBeNull();
    expect(error.details.preferredFulfillment).toBeTruthy();
  });

  it('upsertPreferences persists preferences', async () => {
    const row = {
      user_id: 'user-1',
      preferred_fulfillment: 'pickup',
      preferred_pickup_location_id: 'loc-1',
      marketing_emails: true,
      sms_notifications: false,
      created_at: '2026-07-13T00:00:00Z',
      updated_at: '2026-07-13T00:00:00Z',
    };
    fromMock.mockReturnValue(makeQuery({ data: row, error: null }));

    const { upsertPreferences } = await import('./customerProfileService');
    const { data, error } = await upsertPreferences({
      preferredFulfillment: 'pickup',
      preferredPickupLocationId: 'loc-1',
      marketingEmails: true,
    });
    expect(error).toBeNull();
    expect(data.preferredFulfillment).toBe('pickup');
    expect(fromMock).toHaveBeenCalledWith('customer_preferences');
  });

  it('getProfileBundle fetches addresses and preferences in parallel', async () => {
    const addressRow = {
      id: 'addr-1',
      user_id: 'user-1',
      label: 'home',
      recipient_name: 'Jane',
      phone: '+254712345678',
      county: 'Nairobi',
      town: 'Westlands',
      street_address: '123 St',
      additional_directions: null,
      is_default: true,
      created_at: '2026-07-13T00:00:00Z',
      updated_at: '2026-07-13T00:00:00Z',
    };

    fromMock.mockImplementation((table) => {
      if (table === 'customer_addresses') {
        return makeQuery({ data: [addressRow], error: null });
      }
      return makeQuery({ data: null, error: null });
    });

    const { getProfileBundle } = await import('./customerProfileService');
    const { data, error } = await getProfileBundle();
    expect(error).toBeNull();
    expect(data.addresses).toHaveLength(1);
    expect(data.preferences.userId).toBe('user-1');
  });
});
