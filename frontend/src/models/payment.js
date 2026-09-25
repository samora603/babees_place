/**
 * Payment domain models — statuses, mapping, transition rules (pure).
 */

export const PAYMENT_METHODS = {
  cod: {
    label: 'Payment on Delivery',
    description: 'Pay when you receive your order (delivery or pickup)',
  },
  // Preserved for historical orders / DB compatibility — not offered at checkout.
  mpesa: {
    label: 'M-Pesa',
    description: 'Online M-Pesa is not available — Payment on Delivery only',
    disabled: true,
  },
  card: { label: 'Card', description: 'Not available — Payment on Delivery only', disabled: true },
  paypal: { label: 'PayPal', description: 'Not available — Payment on Delivery only', disabled: true },
  bank_transfer: {
    label: 'Bank Transfer',
    description: 'Not available — Payment on Delivery only',
    disabled: true,
  },
};

/** Sole customer-facing payment method. */
export const CHECKOUT_PAYMENT_METHOD = 'cod';


export const PAYMENT_PROVIDER_STATUSES = {
  pending: { label: 'Pending', color: 'text-yellow-400 bg-yellow-400/10' },
  initiated: { label: 'Awaiting PIN', color: 'text-amber-400 bg-amber-400/10' },
  processing: { label: 'Processing', color: 'text-blue-400 bg-blue-400/10' },
  paid: { label: 'Paid', color: 'text-green-400 bg-green-400/10' },
  failed: { label: 'Failed', color: 'text-red-400 bg-red-400/10' },
  cancelled: { label: 'Cancelled', color: 'text-slate-400 bg-slate-400/10' },
  expired: { label: 'Expired', color: 'text-orange-400 bg-orange-400/10' },
  refunded: { label: 'Refunded', color: 'text-blue-400 bg-blue-400/10' },
};

/** Terminal payment attempt statuses */
export const TERMINAL_PAYMENT_STATUSES = new Set([
  'paid',
  'failed',
  'cancelled',
  'expired',
  'refunded',
]);

export const ACTIVE_PAYMENT_STATUSES = new Set([
  'pending',
  'initiated',
  'processing',
]);

/**
 * @param {string} from
 * @param {string} to
 * @returns {boolean}
 */
export function canTransitionPaymentStatus(from, to) {
  if (!from || !to) return false;
  if (from === to) return true;
  if (from === 'paid') return to === 'refunded'; // only refund regresses paid
  if (TERMINAL_PAYMENT_STATUSES.has(from) && to !== 'paid') {
    // Allow retry path: failed/expired/cancelled → pending/initiated via new attempt,
    // not by mutating the old row into pending here.
    return false;
  }
  const graph = {
    pending: ['initiated', 'processing', 'paid', 'failed', 'cancelled', 'expired'],
    initiated: ['processing', 'paid', 'failed', 'cancelled', 'expired'],
    processing: ['paid', 'failed', 'cancelled', 'expired'],
  };
  return (graph[from] || []).includes(to);
}

/**
 * Map DB payment row → UI shape.
 * @param {object|null} row
 */
export function mapPayment(row) {
  if (!row) return null;
  return {
    id: row.id,
    orderId: row.order_id,
    userId: row.user_id,
    provider: row.provider,
    method: row.method,
    status: row.status,
    amount: Number(row.amount || 0),
    currency: row.currency || 'KES',
    phoneNumber: row.phone_number || null,
    transactionReference: row.transaction_reference || null,
    checkoutRequestId: row.checkout_request_id || null,
    merchantRequestId: row.merchant_request_id || null,
    receiptNumber: row.receipt_number || null,
    failureReason: row.failure_reason || null,
    expiresAt: row.expires_at || null,
    paidAt: row.paid_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    rawRequest: row.raw_request || {},
    rawResponse: row.raw_response || {},
    rawCallback: row.raw_callback || {},
  };
}

/**
 * Whether the customer may retry an online payment for an order.
 * Babees Place is Payment on Delivery only — customer online retries are disabled.
 * Historical M-Pesa rows remain visible; admins collect payment via fulfillment status.
 */
export function canRetryPayment() {
  return false;
}

/**
 * Pick the newest payment from a list.
 * @param {object[]} payments
 */
export function getLatestPayment(payments = []) {
  if (!payments.length) return null;
  return [...payments].sort((a, b) =>
    String(b.createdAt || b.created_at || '').localeCompare(
      String(a.createdAt || a.created_at || ''),
    ),
  )[0];
}

export function isPaymentExpired(payment, now = Date.now()) {
  if (!payment?.expiresAt && !payment?.expires_at) return false;
  const expires = new Date(payment.expiresAt || payment.expires_at).getTime();
  return Number.isFinite(expires) && expires < now;
}
