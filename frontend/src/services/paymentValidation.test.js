import { describe, it, expect } from 'vitest';
import {
  normalizeMpesaPhone,
  validatePaymentMethod,
  validateCheckoutPayment,
} from '@/services/paymentValidation';

describe('paymentValidation', () => {
  it('normalizes common Kenyan phone formats', () => {
    expect(normalizeMpesaPhone('0712345678').phone).toBe('254712345678');
    expect(normalizeMpesaPhone('+254712345678').phone).toBe('254712345678');
    expect(normalizeMpesaPhone('712345678').phone).toBe('254712345678');
  });

  it('rejects invalid phones', () => {
    expect(normalizeMpesaPhone('').ok).toBe(false);
    expect(normalizeMpesaPhone('0812345678').ok).toBe(false);
  });

  it('validatePaymentMethod allows Payment on Delivery and blocks online methods', () => {
    expect(validatePaymentMethod('cod').valid).toBe(true);
    expect(validatePaymentMethod('mpesa').valid).toBe(false);
    expect(validatePaymentMethod('card').valid).toBe(false);
  });

  it('validateCheckoutPayment accepts Payment on Delivery without phone', () => {
    const good = validateCheckoutPayment({ method: 'cod', amount: 100 });
    expect(good.valid).toBe(true);

    const blocked = validateCheckoutPayment({
      method: 'mpesa',
      phone: '0712345678',
      amount: 100,
    });
    expect(blocked.valid).toBe(false);
    expect(blocked.errors.method).toBeTruthy();
  });
});
