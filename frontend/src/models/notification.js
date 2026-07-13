/**
 * Notification domain model + event catalog (Workstream 7).
 */

/** @typedef {'unread'|'read'|'archived'} NotificationStatus */
/** @typedef {'in_app'|'email'|'sms'|'push'} NotificationChannel */
/** @typedef {'customer'|'admin'|'system'} NotificationAudience */

export const NOTIFICATION_EVENTS = {
  ACCOUNT_REGISTRATION: 'account_registration',
  WELCOME: 'welcome',
  PASSWORD_RESET: 'password_reset',
  EMAIL_VERIFICATION: 'email_verification',
  ORDER_CREATED: 'order_created',
  ORDER_CONFIRMED: 'order_confirmed',
  ORDER_CANCELLED: 'order_cancelled',
  ORDER_READY_FOR_PICKUP: 'order_ready_for_pickup',
  OUT_FOR_DELIVERY: 'out_for_delivery',
  DELIVERED: 'delivered',
  PAYMENT_INITIATED: 'payment_initiated',
  PAYMENT_SUCCESSFUL: 'payment_successful',
  PAYMENT_FAILED: 'payment_failed',
  PAYMENT_RETRY: 'payment_retry',
  ADMIN_NEW_ORDER: 'admin_new_order',
  ADMIN_LOW_INVENTORY: 'admin_low_inventory',
  ADMIN_PAYMENT_RECEIVED: 'admin_payment_received',
};

export const ADMIN_EVENTS = new Set([
  NOTIFICATION_EVENTS.ADMIN_NEW_ORDER,
  NOTIFICATION_EVENTS.ADMIN_LOW_INVENTORY,
  NOTIFICATION_EVENTS.ADMIN_PAYMENT_RECEIVED,
]);

export const ORDER_STATUS_EVENT_MAP = {
  confirmed: NOTIFICATION_EVENTS.ORDER_CONFIRMED,
  ready_for_pickup: NOTIFICATION_EVENTS.ORDER_READY_FOR_PICKUP,
  out_for_delivery: NOTIFICATION_EVENTS.OUT_FOR_DELIVERY,
  delivered: NOTIFICATION_EVENTS.DELIVERED,
  cancelled: NOTIFICATION_EVENTS.ORDER_CANCELLED,
};

export const EMPTY_NOTIFICATION_PREFERENCES = {
  emailEnabled: true,
  smsEnabled: false,
  inAppEnabled: true,
  pushEnabled: false,
  marketingEmails: false,
  orderUpdates: true,
  paymentUpdates: true,
};

/**
 * @param {object | null} row
 */
export function mapNotification(row) {
  if (!row) return null;
  return {
    id: row.id,
    userId: row.user_id,
    eventType: row.event_type,
    channel: row.channel,
    title: row.title,
    body: row.body,
    link: row.link || null,
    metadata: row.metadata || {},
    status: row.status,
    audience: row.audience || 'customer',
    readAt: row.read_at || null,
    archivedAt: row.archived_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    isUnread: row.status === 'unread',
  };
}

/**
 * @param {object | null} row
 */
export function mapNotificationPreferences(row) {
  if (!row) return null;
  return {
    userId: row.user_id,
    emailEnabled: Boolean(row.email_enabled),
    smsEnabled: Boolean(row.sms_enabled),
    inAppEnabled: Boolean(row.in_app_enabled),
    pushEnabled: Boolean(row.push_enabled),
    marketingEmails: Boolean(row.marketing_emails),
    orderUpdates: Boolean(row.order_updates),
    paymentUpdates: Boolean(row.payment_updates),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/**
 * @param {string} userId
 * @param {Partial<ReturnType<typeof mapNotificationPreferences>>} input
 */
export function mapNotificationPreferencesToDb(userId, input = {}) {
  return {
    user_id: userId,
    email_enabled: input.emailEnabled ?? true,
    sms_enabled: input.smsEnabled ?? false,
    in_app_enabled: input.inAppEnabled ?? true,
    push_enabled: input.pushEnabled ?? false,
    marketing_emails: input.marketingEmails ?? false,
    order_updates: input.orderUpdates ?? true,
    payment_updates: input.paymentUpdates ?? true,
  };
}

/**
 * @param {object | null} row
 */
export function mapDelivery(row) {
  if (!row) return null;
  return {
    id: row.id,
    notificationId: row.notification_id,
    userId: row.user_id,
    eventType: row.event_type,
    channel: row.channel,
    provider: row.provider,
    status: row.status,
    retryCount: row.retry_count ?? 0,
    maxRetries: row.max_retries ?? 3,
    externalId: row.external_id || null,
    errorMessage: row.error_message || null,
    payload: row.payload || {},
    response: row.response || {},
    sentAt: row.sent_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function isPaymentEvent(eventType) {
  return String(eventType || '').startsWith('payment_');
}

export function isOrderEvent(eventType) {
  return String(eventType || '').startsWith('order_')
    || eventType === NOTIFICATION_EVENTS.OUT_FOR_DELIVERY
    || eventType === NOTIFICATION_EVENTS.DELIVERED;
}

export function isMarketingEvent(eventType) {
  return eventType === NOTIFICATION_EVENTS.WELCOME;
}
