import { normalizePhone } from '@/utils/helpers';

export function validateDeliveryAddress(address = {}) {
  const errors = {};
  if (!address.line1?.trim()) errors.line1 = 'Address line is required';
  if (!address.city?.trim()) errors.city = 'City is required';
  if (!address.phone?.trim()) {
    errors.phone = 'Phone number is required';
  } else {
    const normalized = normalizePhone(address.phone.trim());
    if (!/^\+254\d{9}$/.test(normalized)) {
      errors.phone = 'Enter a valid Kenyan phone (+254...)';
    }
  }
  return { valid: Object.keys(errors).length === 0, errors };
}

export function validateCheckoutForm(form) {
  const errors = {};

  if (!form.deliveryType || !['pickup', 'delivery'].includes(form.deliveryType)) {
    errors.deliveryType = 'Select pickup or delivery';
  }

  if (form.deliveryType === 'pickup') {
    if (!form.pickupLocationId) errors.pickupLocationId = 'Select a pickup location';
  }

  if (form.deliveryType === 'delivery') {
    const addrResult = validateDeliveryAddress(form.deliveryAddress || {});
    if (!addrResult.valid) Object.assign(errors, addrResult.errors);
  }

  return { valid: Object.keys(errors).length === 0, errors };
}

export function buildDeliveryAddressPayload(address) {
  return {
    line1: address.line1?.trim() || '',
    line2: address.line2?.trim() || '',
    city: address.city?.trim() || '',
    phone: normalizePhone(address.phone?.trim() || ''),
    notes: address.notes?.trim() || '',
  };
}

export function validatePickupLocationForm(form) {
  const errors = {};
  if (!form.name?.trim()) errors.name = 'Name is required';
  if (!form.building?.trim()) errors.building = 'Building/location is required';
  return { valid: Object.keys(errors).length === 0, errors };
}
