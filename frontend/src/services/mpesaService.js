/**
 * M-Pesa orchestration — delegates STK / query / callback parsing to the
 * configured payment provider (mock or Daraja stub).
 */

import { getPaymentProvider } from '@/services/providers/paymentProvider';
import { normalizeMpesaPhone } from '@/services/paymentValidation';

/**
 * Initiate STK Push for an existing payment row.
 * @param {{ paymentId: string, orderId: string, amount: number, phone: string, accountReference?: string }} input
 */
export async function initiateStkPush(input) {
  const phoneResult = normalizeMpesaPhone(input.phone);
  if (!phoneResult.ok) {
    return { ok: false, error: phoneResult.error };
  }

  const provider = getPaymentProvider();
  const result = await provider.initiateStkPush({
    paymentId: input.paymentId,
    orderId: input.orderId,
    amount: Number(input.amount),
    phone: phoneResult.phone,
    accountReference: input.accountReference || String(input.orderId).slice(0, 8),
    description: input.description || 'Babees Place order',
  });

  return {
    ...result,
    providerId: provider.id,
    phone: phoneResult.phone,
  };
}

/**
 * Poll provider for STK result.
 * @param {string} checkoutRequestId
 */
export async function queryStkStatus(checkoutRequestId) {
  const provider = getPaymentProvider();
  return provider.queryTransaction(checkoutRequestId);
}

/**
 * Normalize inbound callback payload (Edge Function → app).
 * @param {object} payload
 */
export async function parseStkCallback(payload) {
  const provider = getPaymentProvider();
  return provider.parseCallback(payload);
}

export const mpesaService = {
  initiateStkPush,
  queryStkStatus,
  parseStkCallback,
};
