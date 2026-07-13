/**
 * Mock M-Pesa STK provider for local development.
 * Simulates STK Push + delayed success without calling Safaricom.
 *
 * Replace usage via VITE_PAYMENT_PROVIDER=daraja when Edge Function is ready.
 */

const pending = new Map();

function randomId(prefix) {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

/**
 * @returns {import('./paymentProvider').PaymentProvider}
 */
export function createMockMpesaProvider() {
  return {
    id: 'mock_mpesa',

    async initiateStkPush(req) {
      if (!req?.phone || !req?.amount || !req?.paymentId) {
        return { ok: false, error: 'Missing STK push parameters' };
      }

      const checkoutRequestId = randomId('ws_chk');
      const merchantRequestId = randomId('ws_mer');
      const autoSucceedMs = Number(import.meta.env.VITE_MOCK_MPESA_AUTO_SUCCEED_MS || 2500);

      pending.set(checkoutRequestId, {
        paymentId: req.paymentId,
        orderId: req.orderId,
        amount: req.amount,
        phone: req.phone,
        createdAt: Date.now(),
        autoSucceedAt: Date.now() + autoSucceedMs,
        status: 'initiated',
        receiptNumber: null,
      });

      return {
        ok: true,
        checkoutRequestId,
        merchantRequestId,
        raw: {
          ResponseCode: '0',
          ResponseDescription: 'Success. Request accepted for processing',
          CustomerMessage: 'Success. Request accepted for processing',
          CheckoutRequestID: checkoutRequestId,
          MerchantRequestID: merchantRequestId,
          mock: true,
        },
      };
    },

    async queryTransaction(checkoutRequestId) {
      const entry = pending.get(checkoutRequestId);
      if (!entry) {
        return {
          status: 'failed',
          failureReason: 'Unknown CheckoutRequestID',
          raw: { mock: true },
        };
      }

      if (entry.status === 'paid') {
        return {
          status: 'paid',
          receiptNumber: entry.receiptNumber,
          raw: { mock: true, ResultCode: 0 },
        };
      }

      if (Date.now() >= entry.autoSucceedAt) {
        entry.status = 'paid';
        entry.receiptNumber = `MOCK${Date.now().toString().slice(-8)}`;
        pending.set(checkoutRequestId, entry);
        return {
          status: 'paid',
          receiptNumber: entry.receiptNumber,
          raw: {
            mock: true,
            ResultCode: 0,
            ResultDesc: 'The service request is processed successfully.',
            CheckoutRequestID: checkoutRequestId,
          },
        };
      }

      return {
        status: 'processing',
        raw: { mock: true, ResultCode: 1, ResultDesc: 'Pending customer PIN' },
      };
    },

    async parseCallback(payload = {}) {
      const checkoutRequestId =
        payload.CheckoutRequestID || payload.checkoutRequestId || payload.Body?.stkCallback?.CheckoutRequestID;
      const resultCode =
        payload.ResultCode ??
        payload.Body?.stkCallback?.ResultCode ??
        0;

      if (Number(resultCode) === 0) {
        const receipt =
          payload.receiptNumber ||
          payload.MpesaReceiptNumber ||
          payload.Body?.stkCallback?.CallbackMetadata?.Item?.find?.(
            (i) => i.Name === 'MpesaReceiptNumber',
          )?.Value ||
          `MOCK${Date.now().toString().slice(-8)}`;

        if (checkoutRequestId && pending.has(checkoutRequestId)) {
          const entry = pending.get(checkoutRequestId);
          entry.status = 'paid';
          entry.receiptNumber = receipt;
          pending.set(checkoutRequestId, entry);
        }

        return {
          status: 'paid',
          receiptNumber: String(receipt),
          paymentRef: checkoutRequestId,
          raw: { ...payload, mock: true },
        };
      }

      return {
        status: 'failed',
        failureReason: payload.ResultDesc || payload.Body?.stkCallback?.ResultDesc || 'STK failed',
        paymentRef: checkoutRequestId,
        raw: { ...payload, mock: true },
      };
    },

    /** Test helper — force success for a checkout request */
    __forceSuccess(checkoutRequestId) {
      const entry = pending.get(checkoutRequestId);
      if (!entry) return false;
      entry.autoSucceedAt = 0;
      return true;
    },
  };
}
