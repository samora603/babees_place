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

  it('validatePaymentMethod blocks disabled methods', () => {
    expect(validatePaymentMethod('cod').valid).toBe(true);
    expect(validatePaymentMethod('mpesa').valid).toBe(true);
    expect(validatePaymentMethod('card').valid).toBe(false);
  });

  it('validateCheckoutPayment requires phone for mpesa', () => {
    const bad = validateCheckoutPayment({ method: 'mpesa', phone: '', amount: 100 });
    expect(bad.valid).toBe(false);
    expect(bad.errors.phone).toBeTruthy();

    const good = validateCheckoutPayment({
      method: 'mpesa',
      phone: '0712345678',
      amount: 100,
    });
    expect(good.valid).toBe(true);
    expect(good.normalizedPhone).toBe('254712345678');
  });
});
