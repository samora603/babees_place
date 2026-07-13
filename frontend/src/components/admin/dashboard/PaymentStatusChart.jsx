import {
  Cell,
  Legend,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
} from 'recharts';
import { statusCountsToChartData, isChartDataEmpty } from '@/models/chartPresentation';
import { chartColorForKey, PAYMENT_CHART_COLORS } from '@/constants/chartTheme';
import DashboardChartFrame from './DashboardChartFrame';
import ChartTooltipContent, { countTooltipFormatter } from './charts/ChartTooltipContent';

function renderPieLabel({ name, percent, value }) {
  return `${name}: ${value} (${(percent * 100).toFixed(0)}%)`;
}

/**
 * @param {{
 *   paymentCounts: import('@/models/analytics').StatusCount[],
 *   loading?: boolean,
 *   error?: Error | null,
 *   onRetry?: () => void,
 * }} props
 */
export default function PaymentStatusChart({ paymentCounts, loading = false, error = null, onRetry }) {
  const data = statusCountsToChartData(paymentCounts);
  const isEmpty = isChartDataEmpty(data);

  return (
    <DashboardChartFrame
      title="Payment Status"
      ariaLabel="Pie chart of orders by payment status"
      loading={loading}
      error={error}
      isEmpty={isEmpty}
      emptyMessage="No payment status data to chart yet."
      onRetry={onRetry}
      tableCaption="Orders grouped by payment status"
      tableRows={data}
    >
      <ResponsiveContainer width="100%" height="100%">
        <PieChart>
          <Pie
            data={data}
            dataKey="value"
            nameKey="label"
            cx="50%"
            cy="50%"
            outerRadius="78%"
            label={renderPieLabel}
            labelLine={{ stroke: '#64748b' }}
          >
            {data.map((entry, index) => (
              <Cell key={entry.key} fill={chartColorForKey(PAYMENT_CHART_COLORS, entry.key, index)} stroke="#0B0B0B" />
            ))}
          </Pie>
          <Tooltip content={<ChartTooltipContent valueFormatter={countTooltipFormatter} />} />
          <Legend
            verticalAlign="bottom"
            formatter={(value) => <span className="text-slate-300 text-xs">{value}</span>}
          />
        </PieChart>
      </ResponsiveContainer>
    </DashboardChartFrame>
  );
}
