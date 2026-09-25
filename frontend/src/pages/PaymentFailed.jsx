import { Link, useLocation, useParams } from 'react-router-dom';
import { FiAlertCircle } from 'react-icons/fi';
import PaymentStatusBadge from '@/components/checkout/PaymentStatusBadge';

/**
 * Legacy online-payment failure route.
 * Babees Place is Payment on Delivery only — no customer STK retry from this page.
 */
export default function PaymentFailed() {
  const { orderId } = useParams();
  const location = useLocation();
  const payment = location.state?.payment;
  const reason =
    location.state?.reason ||
    payment?.failureReason ||
    'Online payment is not used for Babees Place orders.';

  return (
    <div className="section-container py-16 max-w-lg space-y-6">
      <div className="text-center space-y-3">
        <FiAlertCircle size={56} className="text-red-400 mx-auto" />
        <h1 className="font-display font-bold text-3xl text-white">Payment unavailable</h1>
        <p className="text-slate-400 text-sm">{reason}</p>
        {payment && (
          <div className="flex justify-center">
            <PaymentStatusBadge status={payment.status || 'failed'} />
          </div>
        )}
      </div>

      <div className="card p-5 space-y-3 text-sm text-slate-400">
        <p className="text-slate-200 font-medium">Payment on Delivery only</p>
        <p>
          Babees Place collects payment when your order is delivered or picked up.
          No online card or M-Pesa checkout is required.
        </p>
      </div>

      <div className="flex flex-wrap gap-3 justify-center">
        <Link to={`/orders/${orderId}`} className="btn-secondary">
          View order
        </Link>
        <Link to="/orders" className="btn-ghost text-sm">
          All orders
        </Link>
        <Link to="/shop" className="btn-ghost text-sm">
          Continue shopping
        </Link>
      </div>
    </div>
  );
}
