import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { statusCountsToChartData, isChartDataEmpty } from '@/models/chartPresentation';
import { CHART_AXIS, chartColorForKey, STATUS_CHART_COLORS } from '@/constants/chartTheme';
import DashboardChartFrame from './DashboardChartFrame';
import ChartTooltipContent, { countTooltipFormatter } from './charts/ChartTooltipContent';

/**
 * @param {{
 *   statusCounts: import('@/models/analytics').StatusCount[],
 *   loading?: boolean,
 *   error?: Error | null,
 *   onRetry?: () => void,
 * }} props
 */
export default function OrdersStatusChart({ statusCounts, loading = false, error = null, onRetry }) {
  const data = statusCountsToChartData(statusCounts);
  const isEmpty = isChartDataEmpty(data);

  return (
    <DashboardChartFrame
      title="Orders by Status"
      ariaLabel="Horizontal bar chart of order counts by status"
      loading={loading}
      error={error}
      isEmpty={isEmpty}
      emptyMessage="No orders to chart yet."
      onRetry={onRetry}
      tableCaption="Orders grouped by status"
      tableRows={data}
    >
      <ResponsiveContainer width="100%" height="100%">
        <BarChart
          data={data}
          layout="vertical"
          margin={{ top: 4, right: 16, left: 4, bottom: 4 }}
        >
          <CartesianGrid strokeDasharray="3 3" stroke={CHART_AXIS.grid} horizontal={false} />
          <XAxis type="number" tick={{ fill: CHART_AXIS.tick, fontSize: 11 }} axisLine={false} tickLine={false} allowDecimals={false} />
          <YAxis
            type="category"
            dataKey="label"
            width={120}
            tick={{ fill: CHART_AXIS.tick, fontSize: 10 }}
            axisLine={false}
            tickLine={false}
          />
          <Tooltip
            cursor={{ fill: 'rgba(212, 175, 55, 0.08)' }}
            content={<ChartTooltipContent valueFormatter={countTooltipFormatter} />}
          />
          <Bar dataKey="value" radius={[0, 4, 4, 0]} barSize={14}>
            {data.map((entry, index) => (
              <Cell key={entry.key} fill={chartColorForKey(STATUS_CHART_COLORS, entry.key, index)} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </DashboardChartFrame>
  );
}
