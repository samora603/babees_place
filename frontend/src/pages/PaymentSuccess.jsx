import { Link, useLocation, useParams } from 'react-router-dom';
import { FiCheckCircle } from 'react-icons/fi';
import PaymentStatusBadge from '@/components/checkout/PaymentStatusBadge';
import { formatCurrency } from '@/utils/helpers';

export default function PaymentSuccess() {
  const { orderId } = useParams();
  const payment = useLocation().state?.payment;

  return (
    <div className="section-container py-16 max-w-lg text-center space-y-6">
      <FiCheckCircle size={56} className="text-green-400 mx-auto" />
      <h1 className="font-display font-bold text-3xl text-white">Payment Successful</h1>
      <p className="text-slate-400">
        Your M-Pesa payment was confirmed. Your order is paid.
      </p>
      {payment && (
        <div className="card p-5 text-left space-y-2 text-sm">
          <div className="flex justify-between items-center">
            <span className="text-slate-400">Status</span>
            <PaymentStatusBadge status={payment.status || 'paid'} />
          </div>
          <div className="flex justify-between">
            <span className="text-slate-400">Amount</span>
            <span className="text-brand-400 font-semibold">
              {formatCurrency(payment.amount)}
            </span>
          </div>
          {payment.receiptNumber && (
            <div className="flex justify-between">
              <span className="text-slate-400">Receipt</span>
              <code className="text-slate-300">{payment.receiptNumber}</code>
            </div>
          )}
        </div>
      )}
      <div className="flex flex-wrap gap-3 justify-center">
        <Link to={`/orders/${orderId}/confirmation`} className="btn-primary">
          Order confirmation
        </Link>
        <Link to={`/orders/${orderId}`} className="btn-secondary">
          View order
        </Link>
      </div>
    </div>
  );
}
