import { supabase } from '@/lib/supabaseClient';
import { addressService } from '@/services/addressService';
import {
  mapPreferencesRow,
  mapPreferencesToDbPayload,
  validatePreferencesInput,
  EMPTY_PREFERENCES,
} from '@/models/preferences';

async function getCurrentUserId() {
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error) throw error;
  if (!user) throw new Error('Not authenticated');
  return user.id;
}

/**
 * @returns {Promise<{ data: import('@/models/preferences').CustomerPreferences | null, error: Error | null }>}
 */
export async function getPreferences() {
  try {
    const userId = await getCurrentUserId();
    const { data, error } = await supabase
      .from('customer_preferences')
      .select('*')
      .eq('user_id', userId)
      .maybeSingle();

    if (error) throw error;
    return { data: mapPreferencesRow(data) || { userId, ...EMPTY_PREFERENCES }, error: null };
  } catch (error) {
    console.error('customerProfileService.getPreferences error:', error);
    return { data: null, error };
  }
}

/**
 * @param {Partial<import('@/models/preferences').CustomerPreferences>} payload
 */
export async function upsertPreferences(payload) {
  const validation = validatePreferencesInput(payload);
  if (!validation.valid) {
    return { data: null, error: { message: 'Invalid preferences', details: validation.errors } };
  }

  try {
    const userId = await getCurrentUserId();
    const dbPayload = mapPreferencesToDbPayload(userId, payload);

    const { data, error } = await supabase
      .from('customer_preferences')
      .upsert(dbPayload, { onConflict: 'user_id' })
      .select()
      .single();

    if (error) throw error;
    return { data: mapPreferencesRow(data), error: null };
  } catch (error) {
    console.error('customerProfileService.upsertPreferences error:', error);
    return { data: null, error };
  }
}

/**
 * Parallel fetch for profile page / checkout bootstrap.
 * @returns {Promise<{ data: { addresses: import('@/models/address').CustomerAddress[], preferences: import('@/models/preferences').CustomerPreferences | null }, error: Error | null }>}
 */
export async function getProfileBundle() {
  try {
    const [addressesResult, preferencesResult] = await Promise.all([
      addressService.getAddresses(),
      getPreferences(),
    ]);

    const error = addressesResult.error || preferencesResult.error;
    if (error) throw error;

    return {
      data: {
        addresses: addressesResult.data,
        preferences: preferencesResult.data,
      },
      error: null,
    };
  } catch (error) {
    console.error('customerProfileService.getProfileBundle error:', error);
    return {
      data: { addresses: [], preferences: null },
      error,
    };
  }
}

export const customerProfileService = {
  getPreferences,
  upsertPreferences,
  getProfileBundle,
};
