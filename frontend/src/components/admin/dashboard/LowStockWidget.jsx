import { useNavigate } from 'react-router-dom';
import clsx from 'clsx';
import {
  getLowStockSeverityLabel,
  getLowStockSeverityStyles,
} from '@/models/dashboard';
import DashboardWidgetCard from './DashboardWidgetCard';
import DashboardWidgetSkeleton from './DashboardWidgetSkeleton';
import DashboardWidgetEmpty from './DashboardWidgetEmpty';
import DashboardWidgetError from './DashboardWidgetError';

/**
 * @param {{
 *   products: import('@/models/dashboard').LowStockProductRow[],
 *   loading?: boolean,
 *   error?: Error | null,
 *   onRetry?: () => void,
 * }} props
 */
export default function LowStockWidget({ products, loading = false, error = null, onRetry }) {
  const navigate = useNavigate();

  return (
    <DashboardWidgetCard title="Low Stock">
      {loading && <DashboardWidgetSkeleton rows={5} />}
      {!loading && error && (
        <DashboardWidgetError message={error.message || 'Failed to load low-stock products.'} onRetry={onRetry} />
      )}
      {!loading && !error && products.length === 0 && (
        <DashboardWidgetEmpty message="All products are above the low-stock threshold." />
      )}
      {!loading && !error && products.length > 0 && (
        <div className="overflow-x-auto -mx-5 px-5">
          <table className="w-full min-w-[480px] text-sm">
            <thead>
              <tr className="text-left text-[10px] uppercase tracking-widest text-slate-500 border-b border-brand-500/10">
                <th className="pb-3 pr-3 font-semibold">Product</th>
                <th className="pb-3 pr-3 font-semibold">Ref</th>
                <th className="pb-3 pr-3 font-semibold">Stock</th>
                <th className="pb-3 pr-3 font-semibold">Threshold</th>
                <th className="pb-3 font-semibold">Level</th>
              </tr>
            </thead>
            <tbody>
              {products.map((product) => (
                <tr
                  key={product.id}
                  onClick={() => navigate(`/admin/products/${product.id}/edit`)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' || e.key === ' ') {
                      e.preventDefault();
                      navigate(`/admin/products/${product.id}/edit`);
                    }
                  }}
                  tabIndex={0}
                  role="link"
                  aria-label={`Edit product ${product.name}`}
                  className="border-b border-brand-500/5 hover:bg-brand-500/5 cursor-pointer transition-colors focus:outline-none focus:bg-brand-500/10"
                >
                  <td className="py-3 pr-3 text-slate-200 font-medium">{product.name}</td>
                  <td className="py-3 pr-3 text-slate-400 font-mono text-xs">{product.sku}</td>
                  <td className="py-3 pr-3 text-slate-200">{product.stock}</td>
                  <td className="py-3 pr-3 text-slate-400">{product.threshold}</td>
                  <td className="py-3">
                    <span
                      className={clsx(
                        'inline-flex text-xs font-medium px-2 py-0.5 rounded border',
                        getLowStockSeverityStyles(product.severity),
                      )}
                    >
                      {getLowStockSeverityLabel(product.severity)}
                    </span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardWidgetCard>
  );
}
