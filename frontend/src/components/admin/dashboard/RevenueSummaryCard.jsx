import clsx from 'clsx';
import { formatCurrency } from '@/utils/helpers';
import { revenueSummaryToDisplayItems } from '@/models/analytics';
import DashboardWidgetCard from './DashboardWidgetCard';
import DashboardWidgetSkeleton from './DashboardWidgetSkeleton';
import DashboardWidgetEmpty from './DashboardWidgetEmpty';
import DashboardWidgetError from './DashboardWidgetError';

/**
 * @param {{
 *   summary: import('@/models/analytics').RevenueSummary | null,
 *   loading?: boolean,
 *   error?: Error | null,
 *   onRetry?: () => void,
 * }} props
 */
export default function RevenueSummaryCard({ summary, loading = false, error = null, onRetry }) {
  const items = summary ? revenueSummaryToDisplayItems(summary) : [];
  const isEmpty = summary && items.every((item) => item.value === 0);

  return (
    <DashboardWidgetCard title="Revenue Summary">
      {loading && <DashboardWidgetSkeleton rows={4} />}
      {!loading && error && (
        <DashboardWidgetError message={error.message || 'Failed to load revenue summary.'} onRetry={onRetry} />
      )}
      {!loading && !error && isEmpty && (
        <DashboardWidgetEmpty message="No recognized revenue yet (paid, non-cancelled orders)." />
      )}
      {!loading && !error && !isEmpty && summary && (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          {items.map((item) => (
            <div
              key={item.key}
              className={clsx(
                'rounded-xl border border-brand-500/10 bg-[#0B0B0B]/60 p-4',
                item.key === 'allTime' && 'lg:col-span-1 ring-1 ring-brand-500/20',
              )}
            >
              <p className="text-[10px] font-semibold uppercase tracking-widest text-slate-500 mb-1">{item.label}</p>
              <p className="font-display font-bold text-xl text-brand-400">{formatCurrency(item.value)}</p>
            </div>
          ))}
        </div>
      )}
    </DashboardWidgetCard>
  );
}
