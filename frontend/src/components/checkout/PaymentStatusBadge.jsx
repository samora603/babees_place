import clsx from 'clsx';
import { PAYMENT_PROVIDER_STATUSES } from '@/models/payment';
import { PAYMENT_STATUSES } from '@/utils/constants';

/**
 * Badge for payment attempt status OR order payment_status.
 * @param {{ status: string, variant?: 'attempt'|'order' }} props
 */
export default function PaymentStatusBadge({ status, variant = 'attempt' }) {
  const map = variant === 'order' ? PAYMENT_STATUSES : PAYMENT_PROVIDER_STATUSES;
  const config = map[status] || {
    label: status || 'Unknown',
    color: 'text-slate-400 bg-slate-400/10',
  };

  return (
    <span className={clsx('badge text-xs font-medium', config.color)}>
      {config.label}
    </span>
  );
}
