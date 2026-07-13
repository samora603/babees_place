import DashboardWidgetCard from './DashboardWidgetCard';
import DashboardWidgetSkeleton from './DashboardWidgetSkeleton';
import DashboardWidgetEmpty from './DashboardWidgetEmpty';
import DashboardWidgetError from './DashboardWidgetError';
import ChartAccessibleTable from './ChartAccessibleTable';

/**
 * Shared loading / empty / error shell for chart widgets.
 */
export default function DashboardChartFrame({
  title,
  ariaLabel,
  loading = false,
  error = null,
  isEmpty = false,
  emptyMessage = 'No data to display.',
  onRetry,
  tableCaption,
  tableRows = [],
  children,
  chartHeightClass = 'h-72',
}) {
  return (
    <DashboardWidgetCard title={title}>
      {loading && <DashboardWidgetSkeleton rows={6} />}
      {!loading && error && (
        <DashboardWidgetError message={error.message || 'Failed to load chart data.'} onRetry={onRetry} />
      )}
      {!loading && !error && isEmpty && <DashboardWidgetEmpty message={emptyMessage} />}
      {!loading && !error && !isEmpty && (
        <div className="space-y-3">
          <ChartAccessibleTable caption={tableCaption || title} rows={tableRows} />
          <div
            role="img"
            aria-label={ariaLabel || title}
            tabIndex={0}
            className={`w-full ${chartHeightClass} focus:outline-none focus-visible:ring-2 focus-visible:ring-brand-500/40 rounded-lg`}
          >
            {children}
          </div>
        </div>
      )}
    </DashboardWidgetCard>
  );
}
