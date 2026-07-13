import { useState } from 'react';
import { FiZap } from 'react-icons/fi';
import Button from '@/components/ui/Button';

/**
 * One-click express checkout panel for returning customers with saved preferences.
 */
export default function ExpressCheckoutPanel({
  summary,
  totalLabel,
  onExpressCheckout,
  disabled = false,
}) {
  const [loading, setLoading] = useState(false);

  const handleClick = async () => {
    setLoading(true);
    try {
      await onExpressCheckout();
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="card p-6 border-brand-500/30 bg-brand-500/5 space-y-4">
      <div className="flex items-start gap-3">
        <div className="w-10 h-10 rounded-full bg-brand-500/15 flex items-center justify-center text-brand-400 shrink-0">
          <FiZap size={20} />
        </div>
        <div>
          <h2 className="font-display font-semibold text-lg text-white uppercase tracking-widest">
            Express Checkout
          </h2>
          <p className="text-sm text-slate-400 mt-1">
            Use your saved preferences and place this order in one step.
          </p>
          {summary && (
            <p className="text-sm text-brand-300 mt-2">{summary}</p>
          )}
        </div>
      </div>
      <Button
        onClick={handleClick}
        loading={loading}
        disabled={disabled || loading}
        className="w-full py-4 uppercase tracking-widest"
      >
        Express Checkout {totalLabel ? `— ${totalLabel}` : ''}
      </Button>
      <p className="text-xs text-slate-500 text-center">
        Or customize fulfillment below
      </p>
    </div>
  );
}
