import { useNavigate } from 'react-router-dom';
import {
  FiCheckCircle,
  FiClock,
  FiPackage,
  FiShoppingBag,
  FiTruck,
  FiXCircle,
} from 'react-icons/fi';
import { formatRelativeTime } from '@/models/dashboard';
import DashboardWidgetCard from './DashboardWidgetCard';
import DashboardWidgetSkeleton from './DashboardWidgetSkeleton';
import DashboardWidgetEmpty from './DashboardWidgetEmpty';
import DashboardWidgetError from './DashboardWidgetError';

const ACTIVITY_ICONS = {
  placed: FiShoppingBag,
  cancelled: FiXCircle,
  payment: FiCheckCircle,
  pickup: FiPackage,
  delivered: FiCheckCircle,
  shipped: FiTruck,
  status: FiClock,
  default: FiClock,
};

/**
 * @param {{
 *   events: import('@/models/dashboard').ActivityEventRow[],
 *   loading?: boolean,
 *   error?: Error | null,
 *   onRetry?: () => void,
 * }} props
 */
export default function RecentActivityWidget({ events, loading = false, error = null, onRetry }) {
  const navigate = useNavigate();

  return (
    <DashboardWidgetCard title="Recent Activity">
      {loading && <DashboardWidgetSkeleton rows={8} />}
      {!loading && error && (
        <DashboardWidgetError message={error.message || 'Failed to load activity.'} onRetry={onRetry} />
      )}
      {!loading && !error && events.length === 0 && (
        <DashboardWidgetEmpty message="No order activity yet." />
      )}
      {!loading && !error && events.length > 0 && (
        <ul className="space-y-1">
          {events.map((event) => {
            const Icon = ACTIVITY_ICONS[event.iconKey] || ACTIVITY_ICONS.default;
            return (
              <li key={event.id}>
                <button
                  type="button"
                  onClick={() => navigate(`/admin/orders/${event.orderId}`)}
                  className="w-full flex items-start gap-3 rounded-xl px-3 py-3 text-left hover:bg-brand-500/5 transition-colors focus:outline-none focus:bg-brand-500/10"
                >
                  <span className="mt-0.5 w-8 h-8 rounded-lg bg-brand-500/10 border border-brand-500/20 flex items-center justify-center shrink-0">
                    <Icon size={16} className="text-brand-400" aria-hidden />
                  </span>
                  <span className="flex-1 min-w-0">
                    <span className="flex flex-wrap items-center gap-x-2 gap-y-0.5">
                      <span className="text-sm font-medium text-brand-400">{event.orderNumber}</span>
                      <span className="text-sm text-slate-200">{event.description}</span>
                    </span>
                    <span className="block text-xs text-slate-500 mt-0.5">
                      {event.userName ? `${event.userName} · ` : ''}
                      {formatRelativeTime(event.createdAt)}
                    </span>
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </DashboardWidgetCard>
  );
}
