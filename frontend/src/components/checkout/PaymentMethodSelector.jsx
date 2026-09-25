import { PAYMENT_METHODS, CHECKOUT_PAYMENT_METHOD } from '@/models/payment';

/**
 * Checkout payment presentation — Payment on Delivery only.
 * Online methods remain in PAYMENT_METHODS for historical display but are not selectable.
 */
export default function PaymentMethodSelector({
  value = CHECKOUT_PAYMENT_METHOD,
  error,
}) {
  const method = PAYMENT_METHODS.cod;

  return (
    <div className="space-y-3">
      <h2 className="font-display font-semibold text-lg text-white uppercase tracking-widest">
        Payment
      </h2>
      <div
        className="w-full text-left p-4 rounded-xl border border-brand-500 bg-brand-500/10"
        role="status"
        aria-label="Payment method"
      >
        <div className="flex items-center justify-between gap-3">
          <div>
            <p className="font-medium text-brand-400">{method.label}</p>
            <p className="text-xs text-slate-500 mt-0.5">{method.description}</p>
          </div>
          <span
            className="w-4 h-4 rounded-full border border-brand-500 bg-brand-500"
            aria-hidden
          />
        </div>
        <p className="text-xs text-slate-400 mt-3">
          No online payment is required. Confirm your order and pay when it is delivered or picked up.
        </p>
        {value && value !== CHECKOUT_PAYMENT_METHOD ? (
          <p className="text-xs text-amber-400 mt-2">
            Checkout uses Payment on Delivery only.
          </p>
        ) : null}
      </div>
      {error ? <p className="text-xs text-red-400">{error}</p> : null}
    </div>
  );
}
