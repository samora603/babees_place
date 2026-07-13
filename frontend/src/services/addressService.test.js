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

const validPayload = {
  label: 'home',
  recipientName: 'Jane Doe',
  phone: '+254712345678',
  county: 'Nairobi',
  town: 'Westlands',
  streetAddress: '123 Main St',
  additionalDirections: '',
  isDefault: false,
};

const addressRow = {
  id: 'addr-1',
  user_id: 'user-1',
  label: 'home',
  recipient_name: 'Jane Doe',
  phone: '+254712345678',
  county: 'Nairobi',
  town: 'Westlands',
  street_address: '123 Main St',
  additional_directions: null,
  is_default: true,
  created_at: '2026-07-13T00:00:00Z',
  updated_at: '2026-07-13T00:00:00Z',
};

describe('addressService', () => {
  beforeEach(() => {
    getUserMock.mockReset();
    fromMock.mockReset();
    getUserMock.mockResolvedValue({ data: { user: { id: 'user-1' } }, error: null });
  });

  it('getAddresses returns mapped rows', async () => {
    const chain = makeQuery({ data: [addressRow], error: null });
    fromMock.mockReturnValue(chain);

    const { getAddresses } = await import('./addressService');
    const { data, error } = await getAddresses();
    expect(error).toBeNull();
    expect(data[0].recipientName).toBe('Jane Doe');
    expect(fromMock).toHaveBeenCalledWith('customer_addresses');
  });

  it('createAddress rejects invalid input', async () => {
    const { createAddress } = await import('./addressService');
    const { data, error } = await createAddress({ label: 'home' });
    expect(data).toBeNull();
    expect(error.details).toBeTruthy();
  });

  it('createAddress inserts first address as default', async () => {
    let call = 0;
    fromMock.mockImplementation(() => {
      call += 1;
      if (call === 1) {
        return makeQuery({ data: [], error: null });
      }
      return makeQuery({ data: addressRow, error: null });
    });

    const { createAddress } = await import('./addressService');
    const { data, error } = await createAddress(validPayload);
    expect(error).toBeNull();
    expect(data.isDefault).toBe(true);
  });

  it('setDefaultAddress updates row', async () => {
    fromMock.mockReturnValue(makeQuery({ data: addressRow, error: null }));
    const { setDefaultAddress } = await import('./addressService');
    const { data, error } = await setDefaultAddress('addr-1');
    expect(error).toBeNull();
    expect(data.id).toBe('addr-1');
  });

  it('deleteAddress returns not found when missing', async () => {
    fromMock.mockReturnValue(makeQuery({ data: null, error: null }));
    const { deleteAddress } = await import('./addressService');
    const { data, error } = await deleteAddress('missing');
    expect(data).toBe(false);
    expect(error.message).toBe('Address not found');
  });

  it('getAddresses handles auth errors', async () => {
    getUserMock.mockResolvedValue({ data: { user: null }, error: null });
    const { getAddresses } = await import('./addressService');
    const { data, error } = await getAddresses();
    expect(data).toEqual([]);
    expect(error).toBeTruthy();
  });
});
