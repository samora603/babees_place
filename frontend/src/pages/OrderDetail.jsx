import { useEffect, useState, useCallback } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { orderService } from '@/services/orderService';
import { paymentService } from '@/services/paymentService';
import { formatCurrency, formatDateTime } from '@/utils/helpers';
import OrderStatusBadge from '@/components/orders/OrderStatusBadge';
import OrderStatusTimeline from '@/components/orders/OrderStatusTimeline';
import FulfillmentDetails from '@/components/orders/FulfillmentDetails';
import PaymentDetailsCard from '@/components/orders/PaymentDetailsCard';
import ReorderButton from '@/components/orders/ReorderButton';
import Modal from '@/components/ui/Modal';
import Button from '@/components/ui/Button';
import Spinner from '@/components/ui/Spinner';
import toast from 'react-hot-toast';
import { FiArrowLeft } from 'react-icons/fi';

export default function OrderDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [order, setOrder] = useState(null);
  const [payment, setPayment] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showCancel, setShowCancel] = useState(false);
  const [cancelling, setCancelling] = useState(false);
  const [retrying, setRetrying] = useState(false);

  const loadOrder = useCallback(() => {
    setLoading(true);
    setError(null);
    Promise.all([
      orderService.getOrder(id),
      paymentService.getLatestPaymentForOrder(id).catch(() => null),
    ])
      .then(([orderRes, latestPayment]) => {
        setOrder(orderRes?.data?.data || null);
        setPayment(latestPayment);
      })
      .catch((err) => {
        console.error('OrderDetail load error:', err);
        setError(err);
        setOrder(null);
      })
      .finally(() => setLoading(false));
  }, [id]);

  useEffect(() => {
    loadOrder();
  }, [loadOrder]);

  const handleCancel = async () => {
    setCancelling(true);
    try {
      await orderService.cancelOrder(id);
      toast.success('Order cancelled');
      setShowCancel(false);
      loadOrder();
    } catch (err) {
      toast.error(err.message || 'Cancellation failed');
    } finally {
      setCancelling(false);
    }
  };

  const handleRetryPayment = async () => {
    if (!order) return;
    setRetrying(true);
    try {
      const phone =
        payment?.phoneNumber ||
        order.customerPhone ||
        order.deliveryAddress?.phone ||
        '';
      const result = await paymentService.retryPayment({
        orderId: order.id,
        phone,
        amount: order.totalAmount,
      });
      toast.success('STK Push sent');
      navigate(`/orders/${order.id}/pay/${result.payment.id}`);
    } catch (err) {
      toast.error(err.message || 'Could not retry payment');
    } finally {
      setRetrying(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <Spinner size="lg" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="section-container py-20 text-center space-y-4">
        <p className="text-red-400">Could not load this order.</p>
        <p className="text-sm text-slate-500">{error.message}</p>
        <div className="flex gap-3 justify-center">
          <Button variant="secondary" onClick={loadOrder}>Retry</Button>
          <Link to="/orders" className="btn-secondary">Back to Orders</Link>
        </div>
      </div>
    );
  }

  if (!order) {
    return (
      <div className="section-container py-20 text-center space-y-4">
        <p className="text-slate-400">Order not found.</p>
        <Link to="/orders" className="btn-secondary inline-block">Back to Orders</Link>
      </div>
    );
  }

  const canCancel = orderService.canCancelOrder(order.status, false);
  const showRetry = paymentService.canRetryPayment(order, payment);

  return (
    <div className="section-container py-10 max-w-3xl">
      <Link
        to="/orders"
        className="flex items-center gap-2 text-sm text-slate-400 hover:text-slate-200 mb-6 transition-colors"
      >
        <FiArrowLeft /> Back to Orders
      </Link>
      <div className="flex items-center justify-between mb-6 flex-wrap gap-3">
        <h1 className="font-display font-bold text-2xl">{order.orderNumber}</h1>
        <div className="flex items-center gap-3 flex-wrap">
          <OrderStatusBadge status={order.orderStatus} />
          <ReorderButton orderId={order.id} />
          {canCancel && (
            <Button
              variant="secondary"
              onClick={() => setShowCancel(true)}
              className="text-sm text-red-400 border-red-400/40"
            >
              Cancel Order
            </Button>
          )}
        </div>
      </div>

      <div className="grid md:grid-cols-2 gap-6">
        <div className="space-y-6">
          <div className="card p-5 space-y-4">
            <h2 className="font-semibold">Items</h2>
            <div className="space-y-3">
              {order.items.map((item) => (
                <div key={item.id} className="flex gap-3">
                  <img
                    src={item.image || '/placeholder.png'}
                    alt={item.name}
                    className="w-14 h-14 object-cover rounded-lg"
                  />
                  <div className="flex-1">
                    <p className="text-sm font-medium">{item.name}</p>
                    <p className="text-xs text-slate-400">Qty: {item.quantity}</p>
                  </div>
                  <p className="text-sm font-bold text-brand-400">
                    {formatCurrency(item.price * item.quantity)}
                  </p>
                </div>
              ))}
            </div>
            <div className="border-t border-surface-border pt-3 space-y-1 text-sm">
              <div className="flex justify-between text-slate-400">
                <span>Subtotal</span>
                <span>{formatCurrency(order.subtotal)}</span>
              </div>
              <div className="flex justify-between text-slate-400">
                <span>Delivery</span>
                <span>{formatCurrency(order.deliveryFee)}</span>
              </div>
              <div className="flex justify-between font-bold pt-1 text-base">
                <span>Total</span>
                <span className="text-brand-400">{formatCurrency(order.totalAmount)}</span>
              </div>
            </div>
          </div>
          <FulfillmentDetails order={order} />
        </div>

        <div className="space-y-4">
          <OrderStatusTimeline status={order.status} deliveryType={order.deliveryType} />
          <PaymentDetailsCard
            order={order}
            payment={payment}
            onRetry={showRetry ? handleRetryPayment : undefined}
            retrying={retrying}
          />
          <p className="text-xs text-slate-500 px-1">Placed: {formatDateTime(order.createdAt)}</p>
        </div>
      </div>

      <Modal isOpen={showCancel} onClose={() => setShowCancel(false)} title="Cancel Order" size="sm">
        <p className="text-sm text-slate-300 mb-4">
          Cancel order <strong>{order.orderNumber}</strong>? Stock will be restored to inventory.
        </p>
        <div className="flex gap-3">
          <Button variant="secondary" onClick={() => setShowCancel(false)}>
            Keep Order
          </Button>
          <Button loading={cancelling} onClick={handleCancel} className="bg-red-600 hover:bg-red-500">
            Confirm Cancel
          </Button>
        </div>
      </Modal>
    </div>
  );
}
