import {
  Cell,
  Legend,
  Pie,
  PieChart,
  ResponsiveContainer,
  Tooltip,
} from 'recharts';
import { statusCountsToChartData, isChartDataEmpty } from '@/models/chartPresentation';
import { chartColorForKey, FULFILLMENT_CHART_COLORS } from '@/constants/chartTheme';
import DashboardChartFrame from './DashboardChartFrame';
import ChartTooltipContent, { countTooltipFormatter } from './charts/ChartTooltipContent';

function renderPieLabel({ name, percent, value }) {
  return `${name}: ${value} (${(percent * 100).toFixed(0)}%)`;
}

/**
 * @param {{
 *   fulfillmentCounts: import('@/models/analytics').StatusCount[],
 *   loading?: boolean,
 *   error?: Error | null,
 *   onRetry?: () => void,
 * }} props
 */
export default function FulfillmentChart({ fulfillmentCounts, loading = false, error = null, onRetry }) {
  const data = statusCountsToChartData(fulfillmentCounts);
  const isEmpty = isChartDataEmpty(data);

  return (
    <DashboardChartFrame
      title="Fulfillment Distribution"
      ariaLabel="Donut chart of pickup versus delivery orders"
      loading={loading}
      error={error}
      isEmpty={isEmpty}
      emptyMessage="No fulfillment data to chart yet."
      onRetry={onRetry}
      tableCaption="Orders by fulfillment type"
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
            innerRadius="52%"
            outerRadius="78%"
            paddingAngle={2}
            label={renderPieLabel}
            labelLine={{ stroke: '#64748b' }}
          >
            {data.map((entry, index) => (
              <Cell key={entry.key} fill={chartColorForKey(FULFILLMENT_CHART_COLORS, entry.key, index)} stroke="#0B0B0B" />
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
