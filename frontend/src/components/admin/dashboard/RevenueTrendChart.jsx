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
import { revenueSummaryToChartData, isChartDataEmpty } from '@/models/chartPresentation';
import { CHART_AXIS, REVENUE_TREND_COLORS } from '@/constants/chartTheme';
import DashboardChartFrame from './DashboardChartFrame';
import ChartTooltipContent, { currencyTooltipFormatter } from './charts/ChartTooltipContent';

/**
 * @param {{
 *   summary: import('@/models/analytics').RevenueSummary | null,
 *   loading?: boolean,
 *   error?: Error | null,
 *   onRetry?: () => void,
 * }} props
 */
export default function RevenueTrendChart({ summary, loading = false, error = null, onRetry }) {
  const data = summary ? revenueSummaryToChartData(summary) : [];
  const isEmpty = summary ? isChartDataEmpty(data) : true;

  return (
    <DashboardChartFrame
      title="Revenue Trend"
      ariaLabel="Vertical bar chart of recognized revenue by period"
      loading={loading}
      error={error}
      isEmpty={isEmpty}
      emptyMessage="No recognized revenue to chart yet."
      onRetry={onRetry}
      tableCaption="Revenue by period"
      tableRows={data}
    >
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke={CHART_AXIS.grid} vertical={false} />
          <XAxis
            dataKey="label"
            tick={{ fill: CHART_AXIS.tick, fontSize: 11 }}
            axisLine={{ stroke: CHART_AXIS.grid }}
            tickLine={false}
          />
          <YAxis
            tick={{ fill: CHART_AXIS.tick, fontSize: 11 }}
            axisLine={false}
            tickLine={false}
            tickFormatter={(v) => `${Math.round(v / 1000)}k`}
          />
          <Tooltip
            cursor={{ fill: 'rgba(212, 175, 55, 0.08)' }}
            content={<ChartTooltipContent valueFormatter={currencyTooltipFormatter} />}
          />
          <Bar dataKey="value" radius={[6, 6, 0, 0]} maxBarSize={56}>
            {data.map((entry, index) => (
              <Cell key={entry.key} fill={REVENUE_TREND_COLORS[index % REVENUE_TREND_COLORS.length]} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </DashboardChartFrame>
  );
}
