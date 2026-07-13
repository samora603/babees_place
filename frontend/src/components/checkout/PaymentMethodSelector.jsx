import { PAYMENT_METHODS } from '@/models/payment';

/**
 * Checkout payment method selector (presentation only).
 */
export default function PaymentMethodSelector({
  value = 'cod',
  onChange,
  disabled = false,
  error,
}) {
  const options = Object.entries(PAYMENT_METHODS).filter(([, meta]) => !meta.disabled || meta.label);

  return (
    <div className="space-y-3">
      <h2 className="font-display font-semibold text-lg text-white uppercase tracking-widest">
        Payment
      </h2>
      <div className="space-y-2" role="radiogroup" aria-label="Payment method">
        {options.map(([key, meta]) => {
          const isDisabled = disabled || meta.disabled;
          const selected = value === key;
          return (
            <button
              key={key}
              type="button"
              role="radio"
              aria-checked={selected}
              disabled={isDisabled}
              onClick={() => !isDisabled && onChange?.(key)}
              className={`w-full text-left p-4 rounded-xl border transition-all ${
                selected
                  ? 'border-brand-500 bg-brand-500/10'
                  : 'border-surface-border hover:border-slate-500'
              } ${isDisabled ? 'opacity-40 cursor-not-allowed' : ''}`}
            >
              <div className="flex items-center justify-between gap-3">
                <div>
                  <p className={`font-medium ${selected ? 'text-brand-400' : 'text-white'}`}>
                    {meta.label}
                    {meta.disabled ? ' (soon)' : ''}
                  </p>
                  <p className="text-xs text-slate-500 mt-0.5">{meta.description}</p>
                </div>
                <span
                  className={`w-4 h-4 rounded-full border ${
                    selected ? 'border-brand-500 bg-brand-500' : 'border-slate-500'
                  }`}
                  aria-hidden
                />
              </div>
            </button>
          );
        })}
      </div>
      {error ? <p className="text-xs text-red-400">{error}</p> : null}
    </div>
  );
}
