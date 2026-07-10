import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { orderService } from '@/services/orderService';
import { formatCurrency, formatDateTime } from '@/utils/helpers';
import OrderStatusBadge from '@/components/orders/OrderStatusBadge';
import Spinner from '@/components/ui/Spinner';
import { FiArrowLeft } from 'react-icons/fi';

export default function OrderDetail() {
  const { id } = useParams();
  const [order, setOrder] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    orderService.getOrder(id)
      .then(({ data }) => setOrder(data.data))
      .finally(() => setLoading(false));
  }, [id]);

  if (loading) return <div className="min-h-screen flex items-center justify-center"><Spinner size="lg" /></div>;
  if (!order) return <div className="section-container py-20 text-center text-slate-400">Order not found.</div>;

  return (
    <div className="section-container py-10 max-w-3xl">
      <Link to="/orders" className="flex items-center gap-2 text-sm text-slate-400 hover:text-slate-200 mb-6 transition-colors">
        <FiArrowLeft /> Back to Orders
      </Link>
      <div className="flex items-center justify-between mb-6">
        <h1 className="font-display font-bold text-2xl">{order.orderNumber}</h1>
        <OrderStatusBadge status={order.orderStatus} />
      </div>

      <div className="grid md:grid-cols-2 gap-6">
        <div className="card p-5 space-y-4">
          <h2 className="font-semibold">Items</h2>
          <div className="space-y-3">
            {order.items.map((item) => (
              <div key={item.id} className="flex gap-3">
                <img src={item.image || '/placeholder.png'} alt={item.name} className="w-14 h-14 object-cover rounded-lg" />
                <div className="flex-1">
                  <p className="text-sm font-medium">{item.name}</p>
                  <p className="text-xs text-slate-400">Qty: {item.quantity}</p>
                </div>
                <p className="text-sm font-bold text-brand-400">{formatCurrency(item.price * item.quantity)}</p>
              </div>
            ))}
          </div>
          <div className="border-t border-surface-border pt-3 space-y-1 text-sm">
            <div className="flex justify-between text-slate-400"><span>Subtotal</span><span>{formatCurrency(order.subtotal)}</span></div>
            <div className="flex justify-between text-slate-400"><span>Delivery</span><span>{formatCurrency(order.deliveryFee)}</span></div>
            <div className="flex justify-between font-bold pt-1 text-base"><span>Total</span><span className="text-brand-400">{formatCurrency(order.totalAmount)}</span></div>
          </div>
        </div>

        <div className="space-y-4">
          <div className="card p-5 space-y-2 text-sm">
            <h2 className="font-semibold mb-3">Order Info</h2>
            <p className="text-slate-400">Status: <strong className="text-slate-200 capitalize">{order.status}</strong></p>
            {order.customerPhone && (
              <p className="text-slate-400">Phone: <strong className="text-slate-200">{order.customerPhone}</strong></p>
            )}
          </div>
          <div className="card p-5 space-y-2 text-sm">
            <h2 className="font-semibold mb-3">Payment</h2>
            <div className="flex items-center gap-2"><OrderStatusBadge status={order.paymentStatus} type="payment" /></div>
            {order.mpesaReceiptNumber && <p className="text-slate-400">Receipt: <code className="text-slate-300">{order.mpesaReceiptNumber}</code></p>}
            <p className="text-slate-400">Placed: {formatDateTime(order.createdAt)}</p>
          </div>
        </div>
      </div>
    </div>
  );
}
