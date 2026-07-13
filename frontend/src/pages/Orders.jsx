import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/context/AuthContext';
import { orderService } from '@/services/orderService';
import { formatCurrency, formatDate } from '@/utils/helpers';
import OrderStatusBadge from '@/components/orders/OrderStatusBadge';
import Spinner from '@/components/ui/Spinner';
import Button from '@/components/ui/Button';

export default function Orders() {
  const { user } = useAuth();
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const loadOrders = () => {
    if (!user?.id) return;
    setLoading(true);
    setError(null);
    orderService
      .getMyOrders(user.id)
      .then(({ data }) => setOrders(data?.data || []))
      .catch((err) => {
        console.error('Orders load error:', err);
        setError(err);
        setOrders([]);
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    loadOrders();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

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
        <p className="text-red-400">Could not load your orders.</p>
        <p className="text-sm text-slate-500">{error.message}</p>
        <Button variant="secondary" onClick={loadOrders}>Retry</Button>
      </div>
    );
  }

  return (
    <div className="section-container py-10 max-w-4xl">
      <h1 className="font-display font-bold text-3xl text-white mb-8">My Orders</h1>

      {orders.length === 0 ? (
        <div className="card p-10 text-center text-slate-400">
          <p className="mb-4">You have no orders yet.</p>
          <Link to="/shop" className="btn-primary inline-block">Start Shopping</Link>
        </div>
      ) : (
        <div className="space-y-4">
          {orders.map((order) => (
            <Link
              key={order.id}
              to={`/orders/${order.id}`}
              className="card p-5 block hover:border-brand-500/30 transition-colors"
            >
              <div className="flex flex-wrap items-center justify-between gap-4 mb-3">
                <h3 className="font-display font-semibold text-lg text-white">{order.orderNumber}</h3>
                <OrderStatusBadge status={order.status} />
              </div>
              <div className="flex flex-wrap justify-between text-sm text-slate-400 gap-2">
                <span>{formatDate(order.created_at)}</span>
                <span className="font-bold text-brand-400">{formatCurrency(order.total_amount)}</span>
              </div>
              <div className="mt-3 pt-3 border-t border-surface-border text-sm text-slate-400">
                {order.items?.map((item) => (
                  <span key={item.id} className="mr-3">
                    {item.name} × {item.quantity}
                  </span>
                ))}
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
