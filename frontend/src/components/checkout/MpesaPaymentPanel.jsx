/**
 * M-Pesa phone + STK guidance panel.
 */
export default function MpesaPaymentPanel({
  phone,
  onPhoneChange,
  disabled = false,
  error,
  statusMessage,
}) {
  return (
    <div className="rounded-xl border border-brand-500/20 bg-brand-500/5 p-4 space-y-3">
      <div>
        <label htmlFor="mpesa-phone" className="text-sm text-slate-300 block mb-1.5">
          M-Pesa phone number *
        </label>
        <input
          id="mpesa-phone"
          type="tel"
          inputMode="tel"
          autoComplete="tel"
          placeholder="07XXXXXXXX"
          value={phone}
          disabled={disabled}
          onChange={(e) => onPhoneChange?.(e.target.value)}
          className="input w-full"
          aria-invalid={Boolean(error)}
          aria-describedby={error ? 'mpesa-phone-error' : undefined}
        />
        {error ? (
          <p id="mpesa-phone-error" className="text-xs text-red-400 mt-1">
            {error}
          </p>
        ) : (
          <p className="text-xs text-slate-500 mt-1">
            You will receive an STK Push prompt to enter your M-Pesa PIN.
          </p>
        )}
      </div>
      {statusMessage ? (
        <p className="text-sm text-amber-300" role="status">
          {statusMessage}
        </p>
      ) : null}
    </div>
  );
}
