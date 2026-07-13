import { supabase } from '@/lib/supabaseClient';
import {
  mapAddressRow,
  mapAddressToDbPayload,
  validateAddressInput,
  getDefaultAddress,
} from '@/models/address';

async function getCurrentUserId() {
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error) throw error;
  if (!user) throw new Error('Not authenticated');
  return user.id;
}

/**
 * @returns {Promise<{ data: import('@/models/address').CustomerAddress[], error: Error | null }>}
 */
export async function getAddresses() {
  try {
    const userId = await getCurrentUserId();
    const { data, error } = await supabase
      .from('customer_addresses')
      .select('*')
      .eq('user_id', userId)
      .order('is_default', { ascending: false })
      .order('created_at', { ascending: false });

    if (error) throw error;
    return { data: (data || []).map(mapAddressRow), error: null };
  } catch (error) {
    console.error('addressService.getAddresses error:', error);
    return { data: [], error };
  }
}

/**
 * @param {string} id
 */
export async function getAddress(id) {
  try {
    const userId = await getCurrentUserId();
    const { data, error } = await supabase
      .from('customer_addresses')
      .select('*')
      .eq('id', id)
      .eq('user_id', userId)
      .maybeSingle();

    if (error) throw error;
    return { data: mapAddressRow(data), error: null };
  } catch (error) {
    console.error('addressService.getAddress error:', error);
    return { data: null, error };
  }
}

/**
 * @param {Partial<import('@/models/address').CustomerAddress>} payload
 */
export async function createAddress(payload) {
  const validation = validateAddressInput(payload);
  if (!validation.valid) {
    return { data: null, error: { message: 'Invalid address', details: validation.errors } };
  }

  try {
    const userId = await getCurrentUserId();
    const dbPayload = {
      ...mapAddressToDbPayload(payload),
      user_id: userId,
    };

    const { data: existing } = await supabase
      .from('customer_addresses')
      .select('id')
      .eq('user_id', userId)
      .limit(1);

    if (!existing?.length) {
      dbPayload.is_default = true;
    }

    const { data, error } = await supabase
      .from('customer_addresses')
      .insert(dbPayload)
      .select()
      .single();

    if (error) throw error;
    return { data: mapAddressRow(data), error: null };
  } catch (error) {
    console.error('addressService.createAddress error:', error);
    return { data: null, error };
  }
}

/**
 * @param {string} id
 * @param {Partial<import('@/models/address').CustomerAddress>} payload
 */
export async function updateAddress(id, payload) {
  const validation = validateAddressInput(payload);
  if (!validation.valid) {
    return { data: null, error: { message: 'Invalid address', details: validation.errors } };
  }

  try {
    const userId = await getCurrentUserId();
    const { data, error } = await supabase
      .from('customer_addresses')
      .update(mapAddressToDbPayload(payload))
      .eq('id', id)
      .eq('user_id', userId)
      .select()
      .single();

    if (error) throw error;
    return { data: mapAddressRow(data), error: null };
  } catch (error) {
    console.error('addressService.updateAddress error:', error);
    return { data: null, error };
  }
}

/**
 * @param {string} id
 */
export async function deleteAddress(id) {
  try {
    const userId = await getCurrentUserId();
    const { data: target, error: fetchErr } = await supabase
      .from('customer_addresses')
      .select('id, is_default')
      .eq('id', id)
      .eq('user_id', userId)
      .maybeSingle();

    if (fetchErr) throw fetchErr;
    if (!target) return { data: false, error: { message: 'Address not found' } };

    const { error } = await supabase
      .from('customer_addresses')
      .delete()
      .eq('id', id)
      .eq('user_id', userId);

    if (error) throw error;

    if (target.is_default) {
      const { data: remaining } = await supabase
        .from('customer_addresses')
        .select('id')
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(1);

      if (remaining?.[0]) {
        await supabase
          .from('customer_addresses')
          .update({ is_default: true })
          .eq('id', remaining[0].id)
          .eq('user_id', userId);
      }
    }

    return { data: true, error: null };
  } catch (error) {
    console.error('addressService.deleteAddress error:', error);
    return { data: false, error };
  }
}

/**
 * @param {string} id
 */
export async function setDefaultAddress(id) {
  try {
    const userId = await getCurrentUserId();
    const { data, error } = await supabase
      .from('customer_addresses')
      .update({ is_default: true })
      .eq('id', id)
      .eq('user_id', userId)
      .select()
      .single();

    if (error) throw error;
    return { data: mapAddressRow(data), error: null };
  } catch (error) {
    console.error('addressService.setDefaultAddress error:', error);
    return { data: null, error };
  }
}

export const addressService = {
  getAddresses,
  getAddress,
  createAddress,
  updateAddress,
  deleteAddress,
  setDefaultAddress,
  getDefaultAddress,
};
