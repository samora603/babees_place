/**
 * @typedef {Object} CustomerPreferences
 * @property {string} userId
 * @property {'pickup' | 'delivery' | null} preferredFulfillment
 * @property {string | null} preferredPickupLocationId
 * @property {boolean} marketingEmails
 * @property {boolean} smsNotifications
 * @property {string} createdAt
 * @property {string} updatedAt
 */

export const EMPTY_PREFERENCES = {
  preferredFulfillment: null,
  preferredPickupLocationId: null,
  marketingEmails: false,
  smsNotifications: false,
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
