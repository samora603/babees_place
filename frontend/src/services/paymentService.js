import { supabase } from '@/lib/supabaseClient';
import {
  mapPayment,
  getLatestPayment,
  canRetryPayment,
  isPaymentExpired,
  ACTIVE_PAYMENT_STATUSES,
} from '@/models/payment';
import { validateCheckoutPayment } from '@/services/paymentValidation';
import { mpesaService } from '@/services/mpesaService';
import { getPaymentProvider } from '@/services/providers/paymentProvider';
import { notificationService } from '@/services/notificationService';
import { NOTIFICATION_EVENTS } from '@/models/notification';

function notifyPaymentOutcome(payment, orderId) {
  if (!payment) return;
  const base = {
    userId: payment.userId,
    orderId: orderId || payment.orderId,
    amount: payment.amount,
    currency: payment.currency || 'KES',
    phone: payment.phoneNumber,
    receiptNumber: payment.receiptNumber,
  };
  if (payment.status === 'paid') {
    notificationService.emitSafe(NOTIFICATION_EVENTS.PAYMENT_SUCCESSFUL, base);
    notificationService.emitSafe(NOTIFICATION_EVENTS.ADMIN_PAYMENT_RECEIVED, {
      ...base,
      notifyAdmins: true,
    });
    // Fire-and-forget loyalty earn + referral qualify
    import('@/services/loyaltyService')
      .then(({ loyaltyService }) => loyaltyService.awardPointsForOrder(base.orderId))
      .catch(() => {});
    import('@/services/referralService')
      .then(({ referralService }) => referralService.qualifyReferralForOrder({
        orderId: base.orderId,
        userId: payment.userId,
      }))
      .catch(() => {});
  } else if (['failed', 'cancelled', 'expired'].includes(payment.status)) {
    notificationService.emitSafe(NOTIFICATION_EVENTS.PAYMENT_FAILED, base);
  }
}

/**
 * Create a payment attempt for an order and (for M-Pesa) initiate STK.
 *
 * @param {{
 *   orderId: string,
 *   method: 'cod'|'mpesa',
 *   phone?: string,
 *   amount?: number,
 * }} input
 */
export async function createPaymentForOrder(input) {
  const method = input.method || 'cod';

  if (method === 'cod') {
    return {
      payment: null,
      orderId: input.orderId,
      method: 'cod',
      requiresAction: false,
    };
  }

  const validation = validateCheckoutPayment({
    method,
    phone: input.phone,
    amount: input.amount || 1,
  });
  if (!validation.valid) {
    const message = Object.values(validation.errors)[0] || 'Invalid payment';
    throw new Error(message);
  }

  const provider = getPaymentProvider();

  const { data: paymentRow, error } = await supabase.rpc('create_payment_for_order', {
    p_order_id: input.orderId,
    p_method: 'mpesa',
    p_provider: provider.id,
    p_phone_number: validation.normalizedPhone,
    p_amount: input.amount ?? null,
  });

  if (error) throw error;

  const payment = mapPayment(paymentRow);
  const stk = await mpesaService.initiateStkPush({
    paymentId: payment.id,
    orderId: input.orderId,
    amount: payment.amount,
    phone: validation.normalizedPhone,
  });

  if (!stk.ok) {
    await supabase.rpc('finalize_payment', {
      p_payment_id: payment.id,
      p_status: 'failed',
      p_failure_reason: stk.error || 'STK push failed',
      p_raw_callback: stk.raw || {},
    });
    throw new Error(stk.error || 'Failed to initiate M-Pesa payment');
  }

  const { data: initiated, error: initError } = await supabase.rpc('mark_payment_initiated', {
    p_payment_id: payment.id,
    p_checkout_request_id: stk.checkoutRequestId,
    p_merchant_request_id: stk.merchantRequestId || null,
    p_raw_response: stk.raw || {},
  });

  if (initError) throw initError;

  const initiatedPayment = mapPayment(initiated);
  notificationService.emitSafe(NOTIFICATION_EVENTS.PAYMENT_INITIATED, {
    userId: initiatedPayment.userId,
    orderId: input.orderId,
    amount: initiatedPayment.amount,
    currency: initiatedPayment.currency || 'KES',
    phone: validation.normalizedPhone,
  });

  return {
    payment: initiatedPayment,
    orderId: input.orderId,
    method: 'mpesa',
    requiresAction: true,
    providerId: stk.providerId,
  };
}

/**
 * Poll payment until terminal or timeout.
 * @param {string} paymentId
 * @param {{ intervalMs?: number, timeoutMs?: number }} [opts]
 */
export async function pollPaymentStatus(paymentId, opts = {}) {
  const intervalMs = opts.intervalMs ?? 1500;
  const timeoutMs = opts.timeoutMs ?? 90_000;
  const started = Date.now();

  while (Date.now() - started < timeoutMs) {
    const payment = await getPayment(paymentId);
    if (!payment) throw new Error('Payment not found');

    if (payment.status === 'paid') {
      notifyPaymentOutcome(payment);
      return payment;
    }

    if (['failed', 'cancelled', 'expired', 'refunded'].includes(payment.status)) {
      notifyPaymentOutcome(payment);
      return payment;
    }

    if (isPaymentExpired(payment)) {
      const { data } = await supabase.rpc('finalize_payment', {
        p_payment_id: paymentId,
        p_status: 'expired',
        p_failure_reason: 'Payment request expired',
      });
      const mapped = mapPayment(data);
      notifyPaymentOutcome(mapped);
      return mapped;
    }

    if (payment.checkoutRequestId && ACTIVE_PAYMENT_STATUSES.has(payment.status)) {
      const query = await mpesaService.queryStkStatus(payment.checkoutRequestId);
      if (query.status === 'paid') {
        const { data } = await supabase.rpc('finalize_payment', {
          p_payment_id: paymentId,
          p_status: 'paid',
          p_receipt_number: query.receiptNumber || null,
          p_transaction_reference: payment.checkoutRequestId,
          p_raw_callback: query.raw || {},
        });
        const mapped = mapPayment(data);
        notifyPaymentOutcome(mapped);
        return mapped;
      }
      if (query.status === 'failed' || query.status === 'cancelled') {
        const { data } = await supabase.rpc('finalize_payment', {
          p_payment_id: paymentId,
          p_status: query.status,
          p_failure_reason: query.failureReason || 'Payment failed',
          p_raw_callback: query.raw || {},
        });
        const mapped = mapPayment(data);
        notifyPaymentOutcome(mapped);
        return mapped;
      }
    }

    await new Promise((r) => setTimeout(r, intervalMs));
  }

  const { data } = await supabase.rpc('finalize_payment', {
    p_payment_id: paymentId,
    p_status: 'expired',
    p_failure_reason: 'Timed out waiting for M-Pesa confirmation',
  });
  const mapped = mapPayment(data);
  notifyPaymentOutcome(mapped);
  return mapped;
}

/**
 * Apply a provider callback payload (used by mock simulate + future webhook bridge).
 * @param {string} paymentId
 * @param {object} payload
 */
export async function handlePaymentCallback(paymentId, payload) {
  const parsed = await mpesaService.parseStkCallback(payload);
  const { data, error } = await supabase.rpc('finalize_payment', {
    p_payment_id: paymentId,
    p_status: parsed.status,
    p_receipt_number: parsed.receiptNumber || null,
    p_transaction_reference: parsed.paymentRef || null,
    p_failure_reason: parsed.failureReason || null,
    p_raw_callback: parsed.raw || payload || {},
  });
  if (error) throw error;
  const mapped = mapPayment(data);
  notifyPaymentOutcome(mapped);
  return mapped;
}

export async function getPayment(paymentId) {
  const { data, error } = await supabase
    .from('payments')
    .select('*')
    .eq('id', paymentId)
    .maybeSingle();
  if (error) throw error;
  return mapPayment(data);
}

export async function getPaymentsForOrder(orderId) {
  const { data, error } = await supabase
    .from('payments')
    .select('*')
    .eq('order_id', orderId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return (data || []).map(mapPayment);
}

export async function getLatestPaymentForOrder(orderId) {
  const payments = await getPaymentsForOrder(orderId);
  return getLatestPayment(payments);
}

/**
 * Retry M-Pesa for an unpaid order (creates a new payment attempt).
 */
export async function retryPayment({ orderId, phone, amount }) {
  const result = await createPaymentForOrder({
    orderId,
    method: 'mpesa',
    phone,
    amount,
  });
  if (result?.payment) {
    notificationService.emitSafe(NOTIFICATION_EVENTS.PAYMENT_RETRY, {
      userId: result.payment.userId,
      orderId,
      amount: result.payment.amount,
      currency: result.payment.currency || 'KES',
      phone,
    });
  }
  return result;
}

export { canRetryPayment, getLatestPayment };

export const paymentService = {
  createPaymentForOrder,
  pollPaymentStatus,
  handlePaymentCallback,
  getPayment,
  getPaymentsForOrder,
  getLatestPaymentForOrder,
  retryPayment,
  canRetryPayment,
};
