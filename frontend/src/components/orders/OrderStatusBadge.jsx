import clsx from 'clsx';
import { ORDER_STATUSES, PAYMENT_STATUSES } from '@/utils/constants';

export default function OrderStatusBadge({ status, type = 'order' }) {
  const map = type === 'payment' ? PAYMENT_STATUSES : ORDER_STATUSES;
  const config = map[status] || { label: status, color: 'text-slate-400 bg-slate-400/10' };

  return (
    <span className={clsx('badge text-xs font-medium', config.color)}>
      {config.label}
    </span>
  );
}
