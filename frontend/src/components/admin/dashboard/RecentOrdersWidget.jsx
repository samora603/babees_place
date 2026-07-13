import { useNavigate } from 'react-router-dom';
import { formatCurrency, formatDateTime } from '@/utils/helpers';
import OrderStatusBadge from '@/components/orders/OrderStatusBadge';
import DashboardWidgetCard from './DashboardWidgetCard';
import DashboardWidgetSkeleton from './DashboardWidgetSkeleton';
import DashboardWidgetEmpty from './DashboardWidgetEmpty';
import DashboardWidgetError from './DashboardWidgetError';
import FulfillmentBadge from './FulfillmentBadge';

/**
 * @param {{
 *   orders: import('@/models/dashboard').RecentOrderRow[],
 *   loading?: boolean,
 *   error?: Error | null,
 *   onRetry?: () => void,
 * }} props
 */
export default function RecentOrdersWidget({ orders, loading = false, error = null, onRetry }) {
  const navigate = useNavigate();

  return (
    <DashboardWidgetCard title="Recent Orders">
      {loading && <DashboardWidgetSkeleton rows={6} />}
      {!loading && error && (
        <DashboardWidgetError message={error.message || 'Failed to load recent orders.'} onRetry={onRetry} />
      )}
      {!loading && !error && orders.length === 0 && (
        <DashboardWidgetEmpty message="No orders yet. New orders will appear here." />
      )}
      {!loading && !error && orders.length > 0 && (
        <div className="overflow-x-auto -mx-5 px-5">
          <table className="w-full min-w-[640px] text-sm">
            <thead>
              <tr className="text-left text-[10px] uppercase tracking-widest text-slate-500 border-b border-brand-500/10">
                <th className="pb-3 pr-3 font-semibold">Order</th>
                <th className="pb-3 pr-3 font-semibold">Customer</th>
                <th className="pb-3 pr-3 font-semibold">Status</th>
                <th className="pb-3 pr-3 font-semibold">Payment</th>
                <th className="pb-3 pr-3 font-semibold">Fulfillment</th>
                <th className="pb-3 pr-3 font-semibold">Total</th>
                <th className="pb-3 font-semibold">Created</th>
              </tr>
            </thead>
            <tbody>
              {orders.map((order) => (
                <tr
                  key={order.id}
                  onClick={() => navigate(`/admin/orders/${order.id}`)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      navigate(`/admin/orders/${order.id}`);
                    }
                  }}
                  tabIndex={0}
                  role="link"
                  aria-label={`View order ${order.orderNumber}`}
                  className="border-b border-brand-500/5 hover:bg-brand-500/5 cursor-pointer transition-colors focus:outline-none focus:bg-brand-500/10"
                >
                  <td className="py-3 pr-3 font-medium text-brand-400">{order.orderNumber}</td>
                  <td className="py-3 pr-3 text-slate-300">{order.customerName}</td>
                  <td className="py-3 pr-3"><OrderStatusBadge status={order.status} /></td>
                  <td className="py-3 pr-3"><OrderStatusBadge status={order.paymentStatus} type="payment" /></td>
                  <td className="py-3 pr-3"><FulfillmentBadge fulfillmentType={order.fulfillmentType} /></td>
                  <td className="py-3 pr-3 font-medium text-slate-200">{formatCurrency(order.total)}</td>
                  <td className="py-3 text-slate-400 text-xs whitespace-nowrap">{formatDateTime(order.createdAt)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardWidgetCard>
  );
}
