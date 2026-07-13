/**
 * LIVE DARAJA PROVIDER STUB
 * =========================================================================
 * When connecting Safaricom Daraja:
 *
 * 1. Prefer a Supabase Edge Function (or backend) that holds:
 *    MPESA_CONSUMER_KEY, MPESA_CONSUMER_SECRET, MPESA_PASSKEY,
 *    MPESA_SHORTCODE, MPESA_CALLBACK_URL, MPESA_ENV (sandbox|production)
 *
 * 2. Implement initiateStkPush by POSTing to that Edge Function, e.g.:
 *    POST ${VITE_MPESA_EDGE_URL}/stk-push
 *    body: { paymentId, orderId, amount, phone, accountReference }
 *
 * 3. Implement queryTransaction via Edge Function that calls Daraja
 *    /mpesa/stkpushquery/v1/query
 *
 * 4. parseCallback should normalize Safaricom STK callback JSON to
 *    { status, receiptNumber, failureReason, raw }.
 *
 * 5. Set VITE_PAYMENT_PROVIDER=daraja in frontend/.env
 *
 * DO NOT put consumer secret / passkey in Vite env (browser-exposed).
 * =========================================================================
 */

/**
 * @returns {import('./paymentProvider').PaymentProvider}
 */
export function createDarajaMpesaProvider() {
  const edgeUrl = import.meta.env.VITE_MPESA_EDGE_URL || '';

  return {
    id: 'mpesa',

    async initiateStkPush(req) {
      if (!edgeUrl) {
        return {
          ok: false,
          error:
            'Daraja provider selected but VITE_MPESA_EDGE_URL is not configured. Use VITE_PAYMENT_PROVIDER=mock for local development.',
        };
      }

      try {
        const res = await fetch(`${edgeUrl.replace(/\/$/, '')}/stk-push`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(req),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok) {
          return { ok: false, error: data.error || data.message || 'STK push failed', raw: data };
        }
        return {
          ok: true,
          checkoutRequestId: data.checkoutRequestId || data.CheckoutRequestID,
          merchantRequestId: data.merchantRequestId || data.MerchantRequestID,
          raw: data,
        };
      } catch (err) {
        return { ok: false, error: err.message || 'Network error initiating STK push' };
      }
    },

    async queryTransaction(checkoutRequestId) {
      if (!edgeUrl) {
        return { status: 'failed', failureReason: 'Daraja edge URL not configured' };
      }
      const res = await fetch(`${edgeUrl.replace(/\/$/, '')}/stk-query`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ checkoutRequestId }),
      });
      const data = await res.json().catch(() => ({}));
      return {
        status: data.status || 'processing',
        receiptNumber: data.receiptNumber,
        failureReason: data.failureReason,
        raw: data,
      };
    },

    async parseCallback(payload) {
      const callback = payload?.Body?.stkCallback || payload;
      const resultCode = Number(callback?.ResultCode ?? 1);
      const items = callback?.CallbackMetadata?.Item || [];
      const find = (name) => items.find((i) => i.Name === name)?.Value;

      if (resultCode === 0) {
        return {
          status: 'paid',
          receiptNumber: String(find('MpesaReceiptNumber') || ''),
          paymentRef: callback?.CheckoutRequestID,
          raw: payload,
        };
      }

      return {
        status: 'failed',
        failureReason: callback?.ResultDesc || 'Payment failed',
        paymentRef: callback?.CheckoutRequestID,
        raw: payload,
      };
    },
  };
}
