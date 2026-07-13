/**
 * Payment input validation (pure).
 */

import { PAYMENT_METHODS } from '@/models/payment';

/**
 * Normalize Kenyan M-Pesa MSISDN to 2547XXXXXXXX.
 * Accepts 07..., 7..., +2547..., 2547...
 * @param {string} phone
 * @returns {{ ok: boolean, phone?: string, error?: string }}
 */
export function normalizeMpesaPhone(phone) {
  if (!phone || typeof phone !== 'string') {
    return { ok: false, error: 'Phone number is required' };
  }
  const digits = phone.replace(/[^\d+]/g, '');
  let normalized = digits;

  if (normalized.startsWith('+')) normalized = normalized.slice(1);
  if (normalized.startsWith('0') && normalized.length === 10) {
    normalized = `254${normalized.slice(1)}`;
  } else if (normalized.startsWith('7') && normalized.length === 9) {
    normalized = `254${normalized}`;
  } else if (normalized.startsWith('254') && normalized.length === 12) {
    // already ok
  } else {
    return { ok: false, error: 'Enter a valid Safaricom number (e.g. 07XXXXXXXX)' };
  }

  if (!/^2547\d{8}$/.test(normalized)) {
    return { ok: false, error: 'M-Pesa number must be a Safaricom line (07…)' };
  }

  return { ok: true, phone: normalized };
}

/**
 * @param {string} method
 * @returns {{ valid: boolean, error?: string }}
 */
export function validatePaymentMethod(method) {
  if (!method || !PAYMENT_METHODS[method]) {
    return { valid: false, error: 'Select a payment method' };
  }
  if (PAYMENT_METHODS[method].disabled) {
    return { valid: false, error: `${PAYMENT_METHODS[method].label} is not available yet` };
  }
  return { valid: true };
}

/**
 * @param {{ method: string, phone?: string, amount?: number }} input
 */
export function validateCheckoutPayment(input = {}) {
  const errors = {};
  const methodResult = validatePaymentMethod(input.method);
  if (!methodResult.valid) {
    errors.method = methodResult.error;
  }

  if (input.method === 'mpesa') {
    const phoneResult = normalizeMpesaPhone(input.phone || '');
    if (!phoneResult.ok) {
      errors.phone = phoneResult.error;
    }
  }

  const amount = Number(input.amount);
  if (!Number.isFinite(amount) || amount <= 0) {
    errors.amount = 'Invalid payment amount';
  }

  return {
    valid: Object.keys(errors).length === 0,
    errors,
    normalizedPhone:
      input.method === 'mpesa'
        ? normalizeMpesaPhone(input.phone || '').phone || null
        : null,
  };
}

export const paymentValidation = {
  normalizeMpesaPhone,
  validatePaymentMethod,
  validateCheckoutPayment,
};
