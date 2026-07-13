import { useEffect, useState, useRef } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { paymentService } from '@/services/paymentService';
import PaymentStatusBadge from '@/components/checkout/PaymentStatusBadge';
import Spinner from '@/components/ui/Spinner';
import { formatCurrency } from '@/utils/helpers';
import toast from 'react-hot-toast';

/**
 * Polls an initiated M-Pesa payment until paid / failed / expired.
 */
export default function PaymentPending() {
  const { id: orderId, paymentId } = useParams();
  const navigate = useNavigate();
  const [payment, setPayment] = useState(null);
  const [error, setError] = useState(null);
  const started = useRef(false);

  useEffect(() => {
    if (!paymentId || started.current) return undefined;
    started.current = true;
    let cancelled = false;

    const run = async () => {
      try {
        const initial = await paymentService.getPayment(paymentId);
        if (!cancelled) setPayment(initial);

        const result = await paymentService.pollPaymentStatus(paymentId, {
          intervalMs: 1500,
          timeoutMs: 90_000,
        });
        if (cancelled) return;
        setPayment(result);

        if (result.status === 'paid') {
          toast.success('Payment confirmed');
          navigate(`/payment/success/${orderId}`, { replace: true, state: { payment: result } });
          return;
        }

        navigate(`/payment/failed/${orderId}`, {
          replace: true,
          state: { payment: result, reason: result.failureReason },
        });
      } catch (err) {
        console.error(err);
        if (!cancelled) {
          setError(err.message || 'Payment verification failed');
        }
      }
    };

    run();
    return () => {
      cancelled = true;
    };
  }, [paymentId, orderId, navigate]);

  return (
    <div className="section-container py-20 max-w-lg text-center space-y-6">
      <Spinner size="lg" />
      <h1 className="font-display font-bold text-2xl text-white">Waiting for M-Pesa</h1>
      <p className="text-slate-400 text-sm">
        Check your phone and enter your M-Pesa PIN to complete payment.
      </p>
      {payment && (
        <div className="card p-5 space-y-2 text-sm text-left">
          <div className="flex justify-between items-center">
            <span className="text-slate-400">Status</span>
            <PaymentStatusBadge status={payment.status} />
          </div>
          <div className="flex justify-between">
            <span className="text-slate-400">Amount</span>
            <span className="text-brand-400 font-semibold">{formatCurrency(payment.amount)}</span>
          </div>
          {payment.phoneNumber && (
            <div className="flex justify-between">
              <span className="text-slate-400">Phone</span>
              <code className="text-slate-300">{payment.phoneNumber}</code>
            </div>
          )}
        </div>
      )}
      {error && (
        <div className="space-y-3">
          <p className="text-red-400 text-sm">{error}</p>
          <Link to={`/payment/failed/${orderId}`} className="btn-secondary inline-block">
            View payment status
          </Link>
        </div>
      )}
      <p className="text-xs text-slate-500">
        Do not close this page until confirmation completes.
      </p>
    </div>
  );
}
