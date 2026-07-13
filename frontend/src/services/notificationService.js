import { supabase } from '@/lib/supabaseClient';
import {
  mapNotification,
  mapDelivery,
  ADMIN_EVENTS,
  NOTIFICATION_EVENTS,
  isOrderEvent,
  isPaymentEvent,
} from '@/models/notification';
import { renderBuiltinTemplate } from '@/services/templateService';
import {
  getNotificationPreferences,
  shouldDeliverChannel,
} from '@/services/notificationPreferenceService';
import { getProviderForChannel } from '@/services/providers/notificationProviderFactory';
import { emailService } from '@/services/emailService';
import { smsService } from '@/services/smsService';

/** Simple in-memory list cache to avoid duplicate fetches. */
let listCache = {
  key: null,
  data: null,
  unreadCount: null,
  fetchedAt: 0,
};

const CACHE_TTL_MS = 15_000;

function invalidateCache() {
  listCache = { key: null, data: null, unreadCount: null, fetchedAt: 0 };
}

function cacheKey(opts = {}) {
  return JSON.stringify({
    status: opts.status || 'all',
    audience: opts.audience || null,
    eventType: opts.eventType || null,
    page: opts.page || 1,
    pageSize: opts.pageSize || 20,
  });
}

function shortOrderId(orderId) {
  if (!orderId) return '—';
  return String(orderId).slice(0, 8).toUpperCase();
}

/**
 * Build default template variables from event payload.
 */
export function buildTemplateVars(payload = {}) {
  const orderId = payload.orderId || payload.order_id;
  return {
    name: payload.name || payload.fullName || 'there',
    order_number: payload.orderNumber || shortOrderId(orderId),
    amount: payload.amount != null ? String(payload.amount) : '',
    currency: payload.currency || 'KES',
    receipt_number: payload.receiptNumber || payload.receipt_number || '—',
    payment_method: payload.paymentMethod || payload.payment_method || 'cod',
    location: payload.location || payload.pickupLocation || 'the boutique',
    product_name: payload.productName || payload.product_name || 'Product',
    stock: payload.stock != null ? String(payload.stock) : '',
    reset_link: payload.resetLink || '#',
    verify_link: payload.verifyLink || '#',
    ...payload.vars,
  };
}

function defaultLinkForEvent(eventType, payload = {}) {
  if (payload.link) return payload.link;
  if (payload.orderId) {
    if (isPaymentEvent(eventType)) {
      return `/orders/${payload.orderId}`;
    }
    return `/orders/${payload.orderId}`;
  }
  if (ADMIN_EVENTS.has(eventType)) {
    if (eventType === NOTIFICATION_EVENTS.ADMIN_LOW_INVENTORY) return '/admin/inventory';
    if (payload.orderId) return `/admin/orders/${payload.orderId}`;
    return '/admin/orders';
  }
  return '/notifications';
}

function titleForEvent(eventType, vars) {
  const titles = {
    [NOTIFICATION_EVENTS.ACCOUNT_REGISTRATION]: 'Welcome aboard',
    [NOTIFICATION_EVENTS.WELCOME]: 'Welcome to Babees Place',
    [NOTIFICATION_EVENTS.PASSWORD_RESET]: 'Password reset',
    [NOTIFICATION_EVENTS.EMAIL_VERIFICATION]: 'Verify your email',
    [NOTIFICATION_EVENTS.ORDER_CREATED]: `Order ${vars.order_number} placed`,
    [NOTIFICATION_EVENTS.ORDER_CONFIRMED]: `Order ${vars.order_number} confirmed`,
    [NOTIFICATION_EVENTS.ORDER_CANCELLED]: `Order ${vars.order_number} cancelled`,
    [NOTIFICATION_EVENTS.ORDER_READY_FOR_PICKUP]: `Order ${vars.order_number} ready`,
    [NOTIFICATION_EVENTS.OUT_FOR_DELIVERY]: `Order ${vars.order_number} out for delivery`,
    [NOTIFICATION_EVENTS.DELIVERED]: `Order ${vars.order_number} delivered`,
    [NOTIFICATION_EVENTS.PAYMENT_INITIATED]: 'Payment initiated',
    [NOTIFICATION_EVENTS.PAYMENT_SUCCESSFUL]: 'Payment successful',
    [NOTIFICATION_EVENTS.PAYMENT_FAILED]: 'Payment failed',
    [NOTIFICATION_EVENTS.PAYMENT_RETRY]: 'Payment retry started',
    [NOTIFICATION_EVENTS.ADMIN_NEW_ORDER]: `New order ${vars.order_number}`,
    [NOTIFICATION_EVENTS.ADMIN_LOW_INVENTORY]: `Low stock: ${vars.product_name}`,
    [NOTIFICATION_EVENTS.ADMIN_PAYMENT_RECEIVED]: `Payment received — ${vars.order_number}`,
  };
  return titles[eventType] || eventType;
}

async function insertDelivery(row) {
  const { data, error } = await supabase
    .from('notification_deliveries')
    .insert(row)
    .select()
    .single();
  if (error) {
    console.warn('notification delivery insert failed:', error.message);
    return null;
  }
  return mapDelivery(data);
}

async function updateDelivery(id, patch) {
  if (!id) return;
  await supabase.from('notification_deliveries').update(patch).eq('id', id);
}

/**
 * Retry a failed delivery (increments retry_count).
 */
export async function retryDelivery(deliveryId) {
  const { data: row, error } = await supabase
    .from('notification_deliveries')
    .select('*')
    .eq('id', deliveryId)
    .maybeSingle();

  if (error) throw error;
  if (!row) throw new Error('Delivery not found');

  const delivery = mapDelivery(row);
  if (delivery.retryCount >= delivery.maxRetries) {
    throw new Error('Max retries exceeded');
  }

  await updateDelivery(deliveryId, {
    status: 'sending',
    retry_count: delivery.retryCount + 1,
  });

  const provider = getProviderForChannel(delivery.channel);
  const result = await provider.send({
    eventType: delivery.eventType,
    userId: delivery.userId,
    to: delivery.payload?.to,
    subject: delivery.payload?.subject,
    body: delivery.payload?.body || '',
    metadata: delivery.payload?.metadata || {},
  });

  await updateDelivery(deliveryId, {
    status: result.ok ? 'sent' : 'failed',
    external_id: result.externalId || null,
    error_message: result.ok ? null : (result.error || 'Send failed'),
    response: result.raw || {},
    sent_at: result.ok ? new Date().toISOString() : null,
  });

  return result;
}

async function createInAppNotification({
  userId,
  eventType,
  title,
  body,
  link,
  metadata,
  audience = 'customer',
}) {
  const { data, error } = await supabase
    .from('notifications')
    .insert({
      user_id: userId,
      event_type: eventType,
      channel: 'in_app',
      title,
      body,
      link,
      metadata: metadata || {},
      audience,
      status: 'unread',
    })
    .select()
    .single();

  if (error) throw error;
  return mapNotification(data);
}

async function dispatchChannels({
  userId,
  eventType,
  vars,
  prefs,
  email,
  phone,
  metadata,
  notificationId,
}) {
  const results = [];
  const channels = ['email', 'sms'];

  for (const channel of channels) {
    if (!shouldDeliverChannel(prefs, channel, eventType)) {
      results.push({ channel, skipped: true, reason: 'preference' });
      continue;
    }

    const rendered = renderBuiltinTemplate(eventType, channel, vars);
    // Skip if no built-in template for this channel
    const hasTemplate = rendered.body && rendered.body !== eventType;
    if (!hasTemplate && channel !== 'in_app') {
      results.push({ channel, skipped: true, reason: 'no_template' });
      continue;
    }

    const to = channel === 'email' ? email : phone;
    if (!to) {
      results.push({ channel, skipped: true, reason: 'missing_recipient' });
      continue;
    }

    const delivery = await insertDelivery({
      notification_id: notificationId || null,
      user_id: userId,
      event_type: eventType,
      channel,
      provider: getProviderForChannel(channel).id,
      status: 'sending',
      payload: { to, subject: rendered.subject, body: rendered.body, metadata },
    });

    let result;
    if (channel === 'email') {
      result = await emailService.sendEmail({
        to,
        subject: rendered.subject,
        body: rendered.body,
        eventType,
        metadata: { ...metadata, notificationId },
      });
    } else {
      result = await smsService.sendSms({
        to,
        body: rendered.body,
        eventType,
        metadata: { ...metadata, notificationId },
      });
    }

    if (delivery?.id) {
      await updateDelivery(delivery.id, {
        status: result.ok ? 'sent' : (result.skipped ? 'skipped' : 'failed'),
        external_id: result.externalId || null,
        error_message: result.ok ? null : (result.error || null),
        response: result.raw || {},
        sent_at: result.ok ? new Date().toISOString() : null,
      });
    }

    results.push({ channel, ...result });
  }

  return results;
}

/**
 * Core emit — creates inbox row(s) + optional email/SMS via mock providers.
 *
 * @param {string} eventType
 * @param {{
 *   userId?: string,
 *   email?: string,
 *   phone?: string,
 *   name?: string,
 *   orderId?: string,
 *   amount?: number|string,
 *   currency?: string,
 *   receiptNumber?: string,
 *   paymentMethod?: string,
 *   location?: string,
 *   productName?: string,
 *   stock?: number,
 *   link?: string,
 *   metadata?: object,
 *   notifyAdmins?: boolean,
 * }} payload
 */
export async function emit(eventType, payload = {}) {
  const vars = buildTemplateVars(payload);
  const title = titleForEvent(eventType, vars);
  const renderedInApp = renderBuiltinTemplate(eventType, 'in_app', vars);
  const body = renderedInApp.body || title;
  const link = defaultLinkForEvent(eventType, payload);
  const metadata = {
    ...(payload.metadata || {}),
    orderId: payload.orderId || null,
    eventType,
  };

  const result = {
    eventType,
    notifications: [],
    deliveries: [],
    adminCount: 0,
  };

  try {
    await supabase.from('notification_events').insert({
      event_type: eventType,
      user_id: payload.userId || null,
      payload: { ...payload, vars },
    });
  } catch {
    // audit is best-effort
  }

  // Admin fan-out events
  if (ADMIN_EVENTS.has(eventType) || payload.notifyAdmins) {
    try {
      const { data: count, error } = await supabase.rpc('notify_admin_users', {
        p_event_type: eventType,
        p_title: title,
        p_body: body,
        p_link: link.startsWith('/admin') ? link : (payload.orderId ? `/admin/orders/${payload.orderId}` : '/admin/orders'),
        p_metadata: metadata,
      });
      if (!error) {
        result.adminCount = count || 0;
        invalidateCache();
      }
    } catch (err) {
      console.warn('notify_admin_users failed:', err?.message || err);
    }
  }

  // Customer / user inbox
  if (payload.userId && !ADMIN_EVENTS.has(eventType)) {
    const { data: prefs } = await getNotificationPreferences(payload.userId);

    if (shouldDeliverChannel(prefs, 'in_app', eventType)) {
      try {
        const notification = await createInAppNotification({
          userId: payload.userId,
          eventType,
          title,
          body,
          link,
          metadata,
          audience: 'customer',
        });
        result.notifications.push(notification);

        await insertDelivery({
          notification_id: notification.id,
          user_id: payload.userId,
          event_type: eventType,
          channel: 'in_app',
          provider: 'in_app',
          status: 'sent',
          sent_at: new Date().toISOString(),
          payload: { title, body, link },
        });

        const channelResults = await dispatchChannels({
          userId: payload.userId,
          eventType,
          vars,
          prefs,
          email: payload.email,
          phone: payload.phone,
          metadata,
          notificationId: notification.id,
        });
        result.deliveries = channelResults;
        invalidateCache();
      } catch (err) {
        console.warn('createInAppNotification failed:', err?.message || err);
        // Still attempt email/sms without inbox when DB unavailable
        const channelResults = await dispatchChannels({
          userId: payload.userId,
          eventType,
          vars,
          prefs: prefs || { emailEnabled: true, smsEnabled: false, inAppEnabled: true },
          email: payload.email,
          phone: payload.phone,
          metadata,
          notificationId: null,
        });
        result.deliveries = channelResults;
      }
    }
  }

  try {
    await supabase.from('notification_events').insert({
      event_type: `${eventType}.result`,
      user_id: payload.userId || null,
      payload: { ...payload },
      result,
    });
  } catch {
    // ignore
  }

  return result;
}

/**
 * Fire-and-forget emit — never throws into callers (checkout/auth stay resilient).
 */
export function emitSafe(eventType, payload = {}) {
  return emit(eventType, payload).catch((err) => {
    console.warn('[notificationService.emitSafe]', eventType, err?.message || err);
    return { eventType, error: err, notifications: [], deliveries: [] };
  });
}

/**
 * List notifications for the current user.
 */
export async function listNotifications(opts = {}) {
  const key = cacheKey(opts);
  const now = Date.now();
  if (
    listCache.key === key
    && listCache.data
    && now - listCache.fetchedAt < CACHE_TTL_MS
  ) {
    return { data: listCache.data, unreadCount: listCache.unreadCount, cached: true, error: null };
  }

  const page = opts.page || 1;
  const pageSize = opts.pageSize || 20;
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  let query = supabase
    .from('notifications')
    .select('*', { count: 'exact' })
    .order('created_at', { ascending: false })
    .range(from, to);

  if (opts.status === 'unread') query = query.eq('status', 'unread');
  else if (opts.status === 'read') query = query.eq('status', 'read');
  else if (opts.status === 'archived') query = query.eq('status', 'archived');
  else if (opts.status !== 'all') query = query.neq('status', 'archived');

  if (opts.audience) query = query.eq('audience', opts.audience);
  if (opts.eventType) query = query.eq('event_type', opts.eventType);
  if (opts.category === 'orders') {
    query = query.or(
      'event_type.like.order_%,event_type.eq.out_for_delivery,event_type.eq.delivered',
    );
  }
  if (opts.category === 'payments') {
    query = query.like('event_type', 'payment_%');
  }

  const { data, error, count } = await query;
  if (error) return { data: [], unreadCount: 0, error, total: 0 };

  const mapped = (data || []).map(mapNotification);
  const unread = await getUnreadCount({ audience: opts.audience });

  listCache = {
    key,
    data: mapped,
    unreadCount: unread,
    fetchedAt: now,
  };

  return {
    data: mapped,
    unreadCount: unread,
    total: count || mapped.length,
    cached: false,
    error: null,
  };
}

export async function getUnreadCount(opts = {}) {
  let query = supabase
    .from('notifications')
    .select('id', { count: 'exact', head: true })
    .eq('status', 'unread');

  if (opts.audience) query = query.eq('audience', opts.audience);

  const { count, error } = await query;
  if (error) return listCache.unreadCount || 0;
  listCache.unreadCount = count || 0;
  return count || 0;
}

export async function markAsRead(notificationId) {
  const { data, error } = await supabase.rpc('mark_notification_read', {
    p_notification_id: notificationId,
  });
  invalidateCache();
  if (error) {
    // fallback direct update
    const { data: row, error: upErr } = await supabase
      .from('notifications')
      .update({ status: 'read', read_at: new Date().toISOString() })
      .eq('id', notificationId)
      .select()
      .single();
    if (upErr) throw upErr;
    return mapNotification(row);
  }
  return mapNotification(data);
}

export async function markAllRead(audience = null) {
  const { data, error } = await supabase.rpc('mark_all_notifications_read', {
    p_audience: audience,
  });
  invalidateCache();
  if (error) {
    const { error: upErr } = await supabase
      .from('notifications')
      .update({ status: 'read', read_at: new Date().toISOString() })
      .eq('status', 'unread');
    if (upErr) throw upErr;
    return { count: 0 };
  }
  return { count: data || 0 };
}

export async function archiveNotification(notificationId) {
  const { data, error } = await supabase.rpc('archive_notification', {
    p_notification_id: notificationId,
  });
  invalidateCache();
  if (error) {
    const { data: row, error: upErr } = await supabase
      .from('notifications')
      .update({
        status: 'archived',
        archived_at: new Date().toISOString(),
        read_at: new Date().toISOString(),
      })
      .eq('id', notificationId)
      .select()
      .single();
    if (upErr) throw upErr;
    return mapNotification(row);
  }
  return mapNotification(data);
}

export function clearNotificationCache() {
  invalidateCache();
}

/** Auth lifecycle helpers (call from recovery / verify flows when wired). */
export function notifyPasswordReset({ userId, email, name, resetLink }) {
  return emitSafe(NOTIFICATION_EVENTS.PASSWORD_RESET, {
    userId,
    email,
    name,
    resetLink,
  });
}

export function notifyEmailVerification({ userId, email, name, verifyLink }) {
  return emitSafe(NOTIFICATION_EVENTS.EMAIL_VERIFICATION, {
    userId,
    email,
    name,
    verifyLink,
  });
}

export const notificationService = {
  emit,
  emitSafe,
  listNotifications,
  getUnreadCount,
  markAsRead,
  markAllRead,
  archiveNotification,
  retryDelivery,
  buildTemplateVars,
  clearNotificationCache,
  notifyPasswordReset,
  notifyEmailVerification,
  NOTIFICATION_EVENTS,
};
