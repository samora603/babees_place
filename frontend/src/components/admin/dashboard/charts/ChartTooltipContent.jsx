import { formatCurrency } from '@/utils/helpers';

/**
 * @param {{ active?: boolean, payload?: Array<{ payload?: { label?: string, value?: number } }>, valueFormatter?: (n: number) => string }} props
 */
export default function ChartTooltipContent({ active, payload, valueFormatter }) {
  if (!active || !payload?.length) return null;

  const point = payload[0]?.payload;
  const value = Number(point?.value ?? 0);
  const format = valueFormatter || ((n) => n.toLocaleString('en-KE'));

  return (
    <div className="rounded-lg border border-brand-500/20 bg-[#111] px-3 py-2 text-xs shadow-lg">
      <p className="text-slate-300 font-medium">{point?.label}</p>
      <p className="text-brand-400 font-semibold">{format(value)}</p>
    </div>
  );
}

export function currencyTooltipFormatter(value) {
  return formatCurrency(value);
}

export function countTooltipFormatter(value) {
  return `${Number(value).toLocaleString('en-KE')} orders`;
}
