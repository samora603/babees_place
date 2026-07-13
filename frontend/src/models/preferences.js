/**
 * @typedef {Object} CustomerPreferences
 * @property {string} userId
 * @property {'pickup' | 'delivery' | null} preferredFulfillment
 * @property {string | null} preferredPickupLocationId
 * @property {boolean} marketingEmails
 * @property {boolean} smsNotifications
 * @property {boolean} emailNotifications
 * @property {boolean} orderUpdates
 * @property {boolean} paymentUpdates
 * @property {string} createdAt
 * @property {string} updatedAt
 */

export const EMPTY_PREFERENCES = {
  preferredFulfillment: null,
  preferredPickupLocationId: null,
  marketingEmails: false,
  smsNotifications: false,
  emailNotifications: true,
  orderUpdates: true,
  paymentUpdates: true,
};

/**
 * @param {object | null} row
 * @returns {CustomerPreferences | null}
 */
export function mapPreferencesRow(row) {
  if (!row) return null;
  return {
    userId: row.user_id,
    preferredFulfillment: row.preferred_fulfillment || null,
    preferredPickupLocationId: row.preferred_pickup_location_id || null,
    marketingEmails: Boolean(row.marketing_emails),
    smsNotifications: Boolean(row.sms_notifications),
    emailNotifications: row.email_notifications == null ? true : Boolean(row.email_notifications),
    orderUpdates: row.order_updates == null ? true : Boolean(row.order_updates),
    paymentUpdates: row.payment_updates == null ? true : Boolean(row.payment_updates),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/**
 * @param {string} userId
 * @param {Partial<CustomerPreferences>} input
 */
export function mapPreferencesToDbPayload(userId, input = {}) {
  return {
    user_id: userId,
    preferred_fulfillment: input.preferredFulfillment || null,
    preferred_pickup_location_id: input.preferredPickupLocationId || null,
    marketing_emails: Boolean(input.marketingEmails),
    sms_notifications: Boolean(input.smsNotifications),
    email_notifications: input.emailNotifications !== false,
    order_updates: input.orderUpdates !== false,
    payment_updates: input.paymentUpdates !== false,
  };
}

/**
 * @param {Partial<CustomerPreferences>} input
 */
export function validatePreferencesInput(input = {}) {
  const errors = {};
  if (
    input.preferredFulfillment
    && !['pickup', 'delivery'].includes(input.preferredFulfillment)
  ) {
    errors.preferredFulfillment = 'Invalid fulfillment preference';
  }
  return { valid: Object.keys(errors).length === 0, errors };
}
