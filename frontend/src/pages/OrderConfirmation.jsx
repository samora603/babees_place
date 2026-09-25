import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { orderService } from '@/services/orderService';
import { formatCurrency } from '@/utils/helpers';
import OrderStatusBadge from '@/components/orders/OrderStatusBadge';
import Spinner from '@/components/ui/Spinner';
import { FiCheckCircle } from 'react-icons/fi';

export default function OrderConfirmation() {
  const { id } = useParams();
  const [order, setOrder] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let mounted = true;
    setLoading(true);
    setError(null);

    orderService
      .getOrder(id)
      .then(({ data }) => {
        if (!mounted) return;
        setOrder(data?.data || null);
      })
      .catch((err) => {
        console.error('OrderConfirmation load error:', err);
        if (!mounted) return;
        setError(err);
        setOrder(null);
      })
      .finally(() => {
        if (mounted) setLoading(false);
      });

    return () => {
      mounted = false;
    };
  }, [id]);

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
        <p className="text-red-400">Could not load your order confirmation.</p>
        <p className="text-sm text-slate-500">{error.message || 'Please try again from My Orders.'}</p>
        <div className="flex gap-3 justify-center">
          <Link to="/orders" className="btn-secondary">My Orders</Link>
          <Link to="/shop" className="btn-primary">Continue Shopping</Link>
        </div>
      </div>
    );
  }

  if (!order) {
    return (
      <div className="section-container py-20 text-center space-y-4">
        <p className="text-slate-400">Order not found.</p>
        <Link to="/orders" className="btn-secondary inline-block">My Orders</Link>
      </div>
    );
  }

  return (
    <div className="section-container py-16 max-w-2xl">
      <div className="text-center mb-10">
        <FiCheckCircle size={56} className="text-green-400 mx-auto mb-4" />
        <h1 className="font-display font-bold text-3xl text-white">Order Confirmed!</h1>
        <p className="text-slate-400 mt-2">
          Order <strong className="text-slate-200">{order.orderNumber}</strong> has been placed.
        </p>
        <p className="text-sm text-slate-400 mt-2">
          Payment method: <span className="text-brand-400">Payment on Delivery</span>
          {order.paymentStatus ? (
            <> · Status: <span className="text-slate-300">{order.paymentStatus}</span></>
          ) : null}
        </p>
        {order.mpesaReceiptNumber && (
          <p className="text-xs text-slate-500 mt-1">Receipt: {order.mpesaReceiptNumber}</p>
        )}
      </div>

      <div className="card p-6 space-y-4">
        <div className="flex justify-between items-center">
          <h2 className="font-semibold">Order Details</h2>
          <OrderStatusBadge status={order.orderStatus} />
        </div>
        <div className="divide-y divide-surface-border">
          {order.items.map((item) => (
            <div key={item.id} className="py-3 flex gap-3">
              <img
                src={item.image || '/placeholder.png'}
                alt={item.name}
                className="w-12 h-12 object-cover rounded-lg"
              />
              <div className="flex-1">
                <p className="text-sm font-medium">{item.name}</p>
                <p className="text-xs text-slate-400">Qty: {item.quantity}</p>
              </div>
              <p className="text-sm font-semibold text-brand-400">
                {formatCurrency(item.price * item.quantity)}
              </p>
            </div>
          ))}
        </div>
        <div className="border-t border-surface-border pt-4 flex justify-between font-bold">
          <span>Total</span>
          <span className="text-brand-400">{formatCurrency(order.totalAmount)}</span>
        </div>
      </div>

      <div className="flex gap-4 mt-8 flex-wrap">
        <Link to={`/orders/${order.id}`} className="btn-secondary flex-1 text-center min-w-[8rem]">
          View Order Details
        </Link>
        <Link to="/orders" className="btn-secondary flex-1 text-center min-w-[8rem]">
          All Orders
        </Link>
        <Link to="/shop" className="btn-primary flex-1 text-center min-w-[8rem]">
          Continue Shopping
        </Link>
      </div>
    </div>
  );
}
