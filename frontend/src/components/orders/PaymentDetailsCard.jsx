import { PAYMENT_METHODS } from '@/models/payment';
import PaymentStatusBadge from '@/components/checkout/PaymentStatusBadge';
import { formatCurrency, formatDateTime } from '@/utils/helpers';

/**
 * Shared payment summary for customer/admin order views.
 */
export default function PaymentDetailsCard({
  order,
  payment = null,
  onRetry,
  retrying = false,
}) {
  const methodKey = order?.paymentMethod || payment?.method || 'cod';
  const methodLabel = PAYMENT_METHODS[methodKey]?.label || methodKey;
  const receipt =
    payment?.receiptNumber || order?.mpesaReceiptNumber || null;
  const paidAt = payment?.paidAt || null;

  return (
    <div className="card p-5 space-y-3 text-sm">
      <div className="flex items-center justify-between gap-3">
        <h2 className="font-semibold">Payment</h2>
        <PaymentStatusBadge
          status={payment?.status || order?.paymentStatus || 'pending'}
          variant={payment ? 'attempt' : 'order'}
        />
      </div>

      <div className="space-y-1 text-slate-400">
        <p>
          Method:{' '}
          <span className="text-slate-200">{methodLabel}</span>
        </p>
        {payment?.amount != null && (
          <p>
            Amount:{' '}
            <span className="text-brand-400 font-semibold">
              {formatCurrency(payment.amount)}
            </span>
          </p>
        )}
        {payment?.phoneNumber && (
          <p>
            Phone: <code className="text-slate-300">{payment.phoneNumber}</code>
          </p>
        )}
        {receipt && (
          <p>
            Receipt:{' '}
            <code className="text-slate-300">{receipt}</code>
          </p>
        )}
        {payment?.transactionReference && (
          <p>
            Reference:{' '}
            <code className="text-slate-300 text-xs">{payment.transactionReference}</code>
          </p>
        )}
        {paidAt && <p>Paid: {formatDateTime(paidAt)}</p>}
        {payment?.failureReason && (
          <p className="text-red-400">{payment.failureReason}</p>
        )}
        {methodKey === 'cod' && !payment && (
          <p className="text-xs text-slate-500 pt-1">
            Cash on delivery / pickup — pay when you receive your order.
          </p>
        )}
      </div>

      {onRetry && (
        <button
          type="button"
          onClick={onRetry}
          disabled={retrying}
          className="btn-secondary w-full text-sm mt-2 disabled:opacity-50"
        >
          {retrying ? 'Starting payment…' : 'Retry M-Pesa Payment'}
        </button>
      )}
    </div>
  );
}
