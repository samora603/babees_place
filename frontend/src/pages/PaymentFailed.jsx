import { useState } from 'react';
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom';
import { FiAlertCircle } from 'react-icons/fi';
import { paymentService } from '@/services/paymentService';
import { orderService } from '@/services/orderService';
import PaymentStatusBadge from '@/components/checkout/PaymentStatusBadge';
import MpesaPaymentPanel from '@/components/checkout/MpesaPaymentPanel';
import Button from '@/components/ui/Button';
import toast from 'react-hot-toast';

export default function PaymentFailed() {
  const { orderId } = useParams();
  const location = useLocation();
  const navigate = useNavigate();
  const payment = location.state?.payment;
  const reason = location.state?.reason || payment?.failureReason || 'Payment was not completed.';

  const [phone, setPhone] = useState(payment?.phoneNumber?.replace(/^254/, '0') || '');
  const [retrying, setRetrying] = useState(false);
  const [phoneError, setPhoneError] = useState('');

  const handleRetry = async () => {
    setRetrying(true);
    setPhoneError('');
    try {
      const { data: wrapped } = await orderService.getOrder(orderId);
      const order = wrapped?.data;
      if (!order) throw new Error('Order not found');

      const result = await paymentService.retryPayment({
        orderId,
        phone,
        amount: order.totalAmount,
      });

      toast.success('STK Push sent — check your phone');
      navigate(`/orders/${orderId}/pay/${result.payment.id}`, { replace: true });
    } catch (err) {
      console.error(err);
      const msg = err.message || 'Retry failed';
      if (/phone|Safaricom|M-Pesa/i.test(msg)) setPhoneError(msg);
      toast.error(msg);
    } finally {
      setRetrying(false);
    }
  };

  return (
    <div className="section-container py-16 max-w-lg space-y-6">
      <div className="text-center space-y-3">
        <FiAlertCircle size={56} className="text-red-400 mx-auto" />
        <h1 className="font-display font-bold text-3xl text-white">Payment Failed</h1>
        <p className="text-slate-400 text-sm">{reason}</p>
        {payment && (
          <div className="flex justify-center">
            <PaymentStatusBadge status={payment.status || 'failed'} />
          </div>
        )}
      </div>

      <div className="card p-5 space-y-4">
        <h2 className="font-semibold text-white">Retry M-Pesa</h2>
        <MpesaPaymentPanel
          phone={phone}
          onPhoneChange={setPhone}
          disabled={retrying}
          error={phoneError}
        />
        <Button onClick={handleRetry} loading={retrying} className="w-full">
          Send STK Push again
        </Button>
      </div>

      <div className="flex flex-wrap gap-3 justify-center">
        <Link to={`/orders/${orderId}`} className="btn-secondary">
          View order
        </Link>
        <Link to="/orders" className="btn-ghost text-sm">
          All orders
        </Link>
      </div>
    </div>
  );
}
