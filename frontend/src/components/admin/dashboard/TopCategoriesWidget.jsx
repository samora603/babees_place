import DashboardWidgetCard from './DashboardWidgetCard';
import DashboardWidgetSkeleton from './DashboardWidgetSkeleton';
import DashboardWidgetEmpty from './DashboardWidgetEmpty';
import DashboardWidgetError from './DashboardWidgetError';
import RelativeBar from './RelativeBar';
import { formatCurrency } from '@/utils/helpers';
import { topCategoriesToDisplayRows } from '@/models/chartPresentation';

/**
 * @param {{
 *   categories: import('@/models/analytics').TopCategoryRow[],
 *   loading?: boolean,
 *   error?: Error | null,
 *   onRetry?: () => void,
 * }} props
 */
export default function TopCategoriesWidget({ categories, loading = false, error = null, onRetry }) {
  const rows = topCategoriesToDisplayRows(categories);

  return (
    <DashboardWidgetCard title="Top Categories">
      {loading && <DashboardWidgetSkeleton rows={6} />}
      {!loading && error && (
        <DashboardWidgetError message={error.message || 'Failed to load top categories.'} onRetry={onRetry} />
      )}
      {!loading && !error && categories.length === 0 && (
        <DashboardWidgetEmpty message="No category sales data yet." />
      )}
      {!loading && !error && categories.length > 0 && (
        <div className="overflow-x-auto -mx-5 px-5">
          <table className="w-full min-w-[480px] text-sm">
            <thead>
              <tr className="text-left text-[10px] uppercase tracking-widest text-slate-500 border-b border-brand-500/10">
                <th className="pb-3 pr-3 font-semibold">Category</th>
                <th className="pb-3 pr-3 font-semibold text-right">Units Sold</th>
                <th className="pb-3 font-semibold text-right">Revenue</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((category) => (
                <tr key={category.categoryName} className="border-b border-brand-500/5">
                  <td className="py-3 pr-3">
                    <div className="space-y-1.5">
                      <span className="text-slate-200 font-medium block">{category.categoryName}</span>
                      <div className="flex items-center gap-2 max-w-xs">
                        <RelativeBar
                          percent={category.revenuePercent}
                          label={`${category.categoryName} share of category revenue`}
                          className="flex-1"
                        />
                        <span className="text-xs text-slate-400 w-10 text-right shrink-0">
                          {category.revenuePercent.toFixed(0)}%
                        </span>
                      </div>
                    </div>
                  </td>
                  <td className="py-3 pr-3 text-slate-300 text-right align-top">{category.unitsSold.toLocaleString('en-KE')}</td>
                  <td className="py-3 text-brand-400 font-medium text-right align-top">{formatCurrency(category.revenue)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardWidgetCard>
  );
}
