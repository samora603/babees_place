import { formatCurrency } from '@/utils/helpers';
import { salesSummaryToDisplayItems } from '@/models/analytics';
import DashboardWidgetCard from './DashboardWidgetCard';
import DashboardWidgetSkeleton from './DashboardWidgetSkeleton';
import DashboardWidgetEmpty from './DashboardWidgetEmpty';
import DashboardWidgetError from './DashboardWidgetError';

function formatMetricValue(value, format) {
  if (format === 'currency') return formatCurrency(value);
  return Number(value ?? 0).toLocaleString('en-KE');
}

/**
 * @param {{
 *   summary: import('@/models/analytics').SalesSummary | null,
 *   loading?: boolean,
 *   error?: Error | null,
 *   onRetry?: () => void,
 * }} props
 */
export default function SalesSummaryCard({ summary, loading = false, error = null, onRetry }) {
  const items = summary ? salesSummaryToDisplayItems(summary) : [];
  const isEmpty = summary && summary.totalOrders === 0;

  return (
    <DashboardWidgetCard title="Sales Summary">
      {loading && <DashboardWidgetSkeleton rows={6} />}
      {!loading && error && (
        <DashboardWidgetError message={error.message || 'Failed to load sales summary.'} onRetry={onRetry} />
      )}
      {!loading && !error && isEmpty && (
        <DashboardWidgetEmpty message="No orders recorded yet." />
      )}
      {!loading && !error && !isEmpty && summary && (
        <dl className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-x-6 gap-y-4">
          {items.map((item) => (
            <div key={item.key} className="flex flex-col">
              <dt className="text-[10px] font-semibold uppercase tracking-widest text-slate-500 mb-1">{item.label}</dt>
              <dd className="font-display font-semibold text-lg text-slate-100">
                {formatMetricValue(item.value, item.format)}
              </dd>
            </div>
          ))}
        </dl>
      )}
    </DashboardWidgetCard>
  );
}
