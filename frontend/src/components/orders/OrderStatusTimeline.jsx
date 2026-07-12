import clsx from 'clsx';
import { ORDER_STATUSES } from '@/utils/constants';
import { getTimelineSteps } from '@/utils/orderStatus';

export default function OrderStatusTimeline({ status, deliveryType }) {
  const steps = getTimelineSteps(deliveryType || 'delivery');
  const currentIndex = steps.indexOf(status);
  const isCancelled = status === 'cancelled';

  if (isCancelled) {
    return (
      <div className="card p-5">
        <h2 className="font-semibold mb-3">Order Status</h2>
        <p className="text-sm text-red-400">This order was cancelled.</p>
      </div>
    );
  }

  return (
    <div className="card p-5">
      <h2 className="font-semibold mb-4">Order Status</h2>
      <ol className="space-y-3">
        {steps.map((step, i) => {
          const config = ORDER_STATUSES[step] || { label: step };
          const done = currentIndex > i || status === 'delivered';
          const active = step === status;
          return (
            <li key={step} className="flex items-center gap-3">
              <span
                className={clsx(
                  'w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold shrink-0',
                  done && 'bg-green-500/20 text-green-400',
                  active && !done && 'bg-brand-500/20 text-brand-400 ring-2 ring-brand-500',
                  !done && !active && 'bg-surface-card text-slate-500',
                )}
              >
                {done ? '✓' : i + 1}
              </span>
              <span className={clsx('text-sm', active ? 'text-white font-medium' : 'text-slate-400')}>
                {config.label}
              </span>
            </li>
          );
        })}
      </ol>
    </div>
  );
}
