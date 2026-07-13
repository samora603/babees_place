/**
 * Payment provider interface + factory.
 *
 * LIVE DARAJA INTEGRATION POINT:
 * - Implement `services/providers/darajaMpesaProvider.js` using Safaricom Daraja
 *   (or call a Supabase Edge Function that holds secrets).
 * - Set `VITE_PAYMENT_PROVIDER=daraja` (and server env for secrets).
 * - Keep this factory as the single switch.
 */

import { createMockMpesaProvider } from '@/services/providers/mockMpesaProvider';
import { createDarajaMpesaProvider } from '@/services/providers/darajaMpesaProvider';

/**
 * @typedef {Object} StkPushRequest
 * @property {string} paymentId
 * @property {string} orderId
 * @property {number} amount
 * @property {string} phone 2547…
 * @property {string} [accountReference]
 * @property {string} [description]
 */

/**
 * @typedef {Object} StkPushResult
 * @property {boolean} ok
 * @property {string} [checkoutRequestId]
 * @property {string} [merchantRequestId]
 * @property {object} [raw]
 * @property {string} [error]
 */

/**
 * @typedef {Object} PaymentProvider
 * @property {string} id
 * @property {(req: StkPushRequest) => Promise<StkPushResult>} initiateStkPush
 * @property {(checkoutRequestId: string) => Promise<{ status: string, receiptNumber?: string, raw?: object, failureReason?: string }>} queryTransaction
 * @property {(payload: object) => Promise<{ paymentRef?: string, status: string, receiptNumber?: string, failureReason?: string, raw: object }>} parseCallback
 */

/**
 * @returns {PaymentProvider}
 */
export function getPaymentProvider() {
  const mode = (import.meta.env.VITE_PAYMENT_PROVIDER || 'mock').toLowerCase();

  if (mode === 'daraja' || mode === 'live' || mode === 'mpesa') {
    return createDarajaMpesaProvider();
  }

  return createMockMpesaProvider();
}

export const PAYMENT_PROVIDER_IDS = {
  mock: 'mock_mpesa',
  daraja: 'mpesa',
};
