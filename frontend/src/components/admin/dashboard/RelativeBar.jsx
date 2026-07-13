import clsx from 'clsx';

/**
 * Accessible relative progress bar for table row visualizations.
 */
export default function RelativeBar({
  percent,
  label,
  className = '',
  barClassName = 'bg-brand-500',
}) {
  const value = Math.max(0, Math.min(100, Number(percent) || 0));

  return (
    <div className={clsx('w-full min-w-[80px]', className)}>
      <div
        role="progressbar"
        aria-valuenow={Math.round(value)}
        aria-valuemin={0}
        aria-valuemax={100}
        aria-label={label}
        className="h-2 rounded-full bg-slate-800/80 overflow-hidden border border-brand-500/10"
      >
        <div
          className={clsx('h-full rounded-full transition-all duration-300', barClassName)}
          style={{ width: `${value}%` }}
        />
      </div>
    </div>
  );
}
