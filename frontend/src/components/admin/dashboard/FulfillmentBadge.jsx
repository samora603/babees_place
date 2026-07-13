import clsx from 'clsx';
import { DELIVERY_TYPES } from '@/utils/constants';

/**
 * @param {{ fulfillmentType: string | null }} props
 */
export default function FulfillmentBadge({ fulfillmentType }) {
  if (!fulfillmentType) {
    return <span className="text-xs text-slate-500">—</span>;
  }

  const config = DELIVERY_TYPES[fulfillmentType] || {
    label: fulfillmentType.replace(/_/g, ' '),
    icon: '📦',
  };

  return (
    <span className={clsx('badge text-xs font-medium text-slate-300 bg-slate-400/10 capitalize')}>
      {config.icon} {config.label}
    </span>
  );
}
