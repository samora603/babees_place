import { supabase } from '@/lib/supabaseClient';
import {
  mapNotificationPreferences,
  mapNotificationPreferencesToDb,
  EMPTY_NOTIFICATION_PREFERENCES,
} from '@/models/notification';

async function getCurrentUserId() {
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error) throw error;
  if (!user) throw new Error('Not authenticated');
  return user.id;
}

/**
 * Ensure preferences row exists (RPC) then return mapped prefs.
 */
export async function getNotificationPreferences(userId = null) {
  try {
    const uid = userId || await getCurrentUserId();
    const { data: ensured, error: ensureError } = await supabase.rpc(
      'ensure_notification_preferences',
      { p_user_id: uid },
    );
    if (!ensureError && ensured) {
      return { data: mapNotificationPreferences(ensured), error: null };
    }

    // Fallback when migration not applied yet
    const { data, error } = await supabase
      .from('notification_preferences')
      .select('*')
      .eq('user_id', uid)
      .maybeSingle();

    if (error) {
      return {
        data: { userId: uid, ...EMPTY_NOTIFICATION_PREFERENCES },
        error: null,
        degraded: true,
      };
    }

    return {
      data: mapNotificationPreferences(data) || { userId: uid, ...EMPTY_NOTIFICATION_PREFERENCES },
      error: null,
    };
  } catch (error) {
    console.error('notificationPreferenceService.getNotificationPreferences:', error);
    return { data: { ...EMPTY_NOTIFICATION_PREFERENCES }, error };
  }
}

/**
 * Upsert notification preferences and mirror legacy customer_preferences flags.
 */
export async function upsertNotificationPreferences(input = {}) {
  try {
    const userId = await getCurrentUserId();
    const dbPayload = mapNotificationPreferencesToDb(userId, input);

    const { data, error } = await supabase
      .from('notification_preferences')
      .upsert(dbPayload, { onConflict: 'user_id' })
      .select()
      .single();

    if (error) throw error;

    // Backwards-compatible mirror onto customer_preferences
    await supabase
      .from('customer_preferences')
      .upsert({
        user_id: userId,
        marketing_emails: dbPayload.marketing_emails,
        sms_notifications: dbPayload.sms_enabled,
        email_notifications: dbPayload.email_enabled,
        order_updates: dbPayload.order_updates,
        payment_updates: dbPayload.payment_updates,
      }, { onConflict: 'user_id' });

    return { data: mapNotificationPreferences(data), error: null };
  } catch (error) {
    console.error('notificationPreferenceService.upsertNotificationPreferences:', error);
    return { data: null, error };
  }
}

/**
 * Whether a channel should be used for this event given prefs.
 */
export function shouldDeliverChannel(prefs, channel, eventType) {
  if (!prefs) return channel === 'in_app';

  if (channel === 'in_app') return prefs.inAppEnabled !== false;
  if (channel === 'push') return Boolean(prefs.pushEnabled);

  const isPayment = String(eventType || '').startsWith('payment_');
  const isOrder = String(eventType || '').startsWith('order_')
    || eventType === 'out_for_delivery'
    || eventType === 'delivered';
  const isMarketing = eventType === 'welcome';

  if (isPayment && prefs.paymentUpdates === false) return false;
  if (isOrder && prefs.orderUpdates === false) return false;
  if (isMarketing && !prefs.marketingEmails) return false;

  if (channel === 'email') return prefs.emailEnabled !== false;
  if (channel === 'sms') return Boolean(prefs.smsEnabled);

  return false;
}

export const notificationPreferenceService = {
  getNotificationPreferences,
  upsertNotificationPreferences,
  shouldDeliverChannel,
};
