import DashboardWidgetCard from './DashboardWidgetCard';
import DashboardWidgetSkeleton from './DashboardWidgetSkeleton';
import DashboardWidgetEmpty from './DashboardWidgetEmpty';
import DashboardWidgetError from './DashboardWidgetError';
import RelativeBar from './RelativeBar';
import { formatCurrency } from '@/utils/helpers';
import { topProductsToDisplayRows } from '@/models/chartPresentation';

/**
 * @param {{
 *   products: import('@/models/analytics').TopProductRow[],
 *   loading?: boolean,
 *   error?: Error | null,
 *   onRetry?: () => void,
 * }} props
 */
export default function TopProductsWidget({ products, loading = false, error = null, onRetry }) {
  const rows = topProductsToDisplayRows(products);

  return (
    <DashboardWidgetCard title="Top Products">
      {loading && <DashboardWidgetSkeleton rows={6} />}
      {!loading && error && (
        <DashboardWidgetError message={error.message || 'Failed to load top products.'} onRetry={onRetry} />
      )}
      {!loading && !error && products.length === 0 && (
        <DashboardWidgetEmpty message="No product sales data yet." />
      )}
      {!loading && !error && products.length > 0 && (
        <div className="overflow-x-auto -mx-5 px-5">
          <table className="w-full min-w-[560px] text-sm">
            <thead>
              <tr className="text-left text-[10px] uppercase tracking-widest text-slate-500 border-b border-brand-500/10">
                <th className="pb-3 pr-3 font-semibold">Product</th>
                <th className="pb-3 pr-3 font-semibold">Revenue Share</th>
                <th className="pb-3 pr-3 font-semibold text-right">Units Sold</th>
                <th className="pb-3 font-semibold text-right">Revenue</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((product) => (
                <tr key={product.productId || product.productName} className="border-b border-brand-500/5">
                  <td className="py-3 pr-3 text-slate-200 font-medium">{product.productName}</td>
                  <td className="py-3 pr-3 min-w-[140px]">
                    <RelativeBar
                      percent={product.revenueBarPercent}
                      label={`${product.productName} revenue share relative to top products`}
                    />
                  </td>
                  <td className="py-3 pr-3 text-slate-300 text-right">{product.unitsSold.toLocaleString('en-KE')}</td>
                  <td className="py-3 text-brand-400 font-medium text-right">{formatCurrency(product.revenueGenerated)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardWidgetCard>
  );
}
