import { normalizePhone } from '@/utils/helpers';

/** @typedef {'home' | 'work' | 'other'} AddressLabel */

/**
 * @typedef {Object} CustomerAddress
 * @property {string} id
 * @property {string} userId
 * @property {AddressLabel} label
 * @property {string} recipientName
 * @property {string} phone
 * @property {string} county
 * @property {string} town
 * @property {string} streetAddress
 * @property {string} additionalDirections
 * @property {boolean} isDefault
 * @property {string} createdAt
 * @property {string} updatedAt
 */

export const ADDRESS_LABELS = {
  home: 'Home',
  work: 'Work',
  other: 'Other',
};

export const EMPTY_ADDRESS_FORM = {
  label: 'home',
  recipientName: '',
  phone: '',
  county: '',
  town: '',
  streetAddress: '',
  additionalDirections: '',
  isDefault: false,
};

/**
 * @param {object} row Supabase row
 * @returns {CustomerAddress}
 */
export function mapAddressRow(row) {
  if (!row) return null;
  return {
    id: row.id,
    userId: row.user_id,
    label: row.label,
    recipientName: row.recipient_name,
    phone: row.phone,
    county: row.county,
    town: row.town,
    streetAddress: row.street_address,
    additionalDirections: row.additional_directions || '',
    isDefault: Boolean(row.is_default),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/**
 * @param {Partial<CustomerAddress>} input
 */
export function mapAddressToDbPayload(input) {
  return {
    label: input.label,
    recipient_name: input.recipientName?.trim(),
    phone: normalizePhone(String(input.phone || '').trim()),
    county: input.county?.trim(),
    town: input.town?.trim(),
    street_address: input.streetAddress?.trim(),
    additional_directions: input.additionalDirections?.trim() || null,
    is_default: Boolean(input.isDefault),
  };
}

/**
 * Map saved address to checkout delivery fields (existing JSONB shape).
 * @param {CustomerAddress} address
 */
export function addressToCheckoutDelivery(address) {
  const noteParts = [];
  if (address.recipientName) noteParts.push(`Recipient: ${address.recipientName}`);
  if (address.additionalDirections) noteParts.push(address.additionalDirections);

  return {
    line1: address.streetAddress,
    line2: address.county || '',
    city: address.town,
    phone: address.phone,
    notes: noteParts.join(' · '),
  };
}

/**
 * @param {Partial<CustomerAddress>} input
 */
export function validateAddressInput(input = {}) {
  const errors = {};

  if (!input.label || !ADDRESS_LABELS[input.label]) {
    errors.label = 'Select a valid label';
  }
  if (!input.recipientName?.trim()) errors.recipientName = 'Recipient name is required';
  if (!input.county?.trim()) errors.county = 'County is required';
  if (!input.town?.trim()) errors.town = 'Town / city is required';
  if (!input.streetAddress?.trim()) errors.streetAddress = 'Street address is required';

  if (!input.phone?.trim()) {
    errors.phone = 'Phone number is required';
  } else {
    const normalized = normalizePhone(input.phone.trim());
    if (!/^\+254\d{9}$/.test(normalized)) {
      errors.phone = 'Enter a valid Kenyan phone (+254...)';
    }
  }

  return { valid: Object.keys(errors).length === 0, errors };
}

/**
 * @param {CustomerAddress[]} addresses
 */
export function getDefaultAddress(addresses = []) {
  return addresses.find((a) => a.isDefault) || addresses[0] || null;
}
