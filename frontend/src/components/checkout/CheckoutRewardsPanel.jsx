import { useState } from 'react';
import { formatCurrency } from '@/utils/helpers';
import Button from '@/components/ui/Button';

/**
 * Checkout rewards panel — presentation only; parent owns preview state.
 */
export default function CheckoutRewardsPanel({
  couponCode,
  onCouponCodeChange,
  onApplyCoupon,
  couponMessage,
  couponError,
  loyaltyBalance = 0,
  loyaltyPoints,
  onLoyaltyPointsChange,
  giftCardCode,
  onGiftCardCodeChange,
  onApplyGiftCard,
  giftCardMessage,
  giftCardError,
  preview,
  disabled = false,
}) {
  return (
    <div className="card p-6 space-y-5" aria-label="Promotions and rewards">
      <h2 className="font-display font-semibold text-lg text-white uppercase tracking-widest">
        Rewards
      </h2>

      <div>
        <label htmlFor="checkout-coupon" className="text-sm text-slate-400 block mb-1.5">
          Coupon code
        </label>
        <div className="flex gap-2">
          <input
            id="checkout-coupon"
            className="input flex-1"
            value={couponCode}
            onChange={(e) => onCouponCodeChange(e.target.value.toUpperCase())}
            placeholder="e.g. WELCOME15"
            disabled={disabled}
            autoComplete="off"
          />
          <Button type="button" variant="secondary" disabled={disabled} onClick={onApplyCoupon}>
            Apply
          </Button>
        </div>
        {couponError && <p className="text-xs text-red-400 mt-1" role="alert">{couponError}</p>}
        {couponMessage && !couponError && (
          <p className="text-xs text-brand-400 mt-1">{couponMessage}</p>
        )}
      </div>

      <div>
        <label htmlFor="checkout-points" className="text-sm text-slate-400 block mb-1.5">
          Loyalty points (balance: {loyaltyBalance})
        </label>
        <input
          id="checkout-points"
          type="number"
          min={0}
          max={loyaltyBalance}
          className="input w-full"
          value={loyaltyPoints || ''}
          onChange={(e) => onLoyaltyPointsChange(Number(e.target.value) || 0)}
          disabled={disabled || loyaltyBalance <= 0}
          placeholder="Points to redeem"
        />
        {preview?.loyaltyErrors?.length > 0 && (
          <p className="text-xs text-amber-400 mt-1">{preview.loyaltyErrors[0]}</p>
        )}
      </div>

      <div>
        <label htmlFor="checkout-gift" className="text-sm text-slate-400 block mb-1.5">
          Gift card
        </label>
        <div className="flex gap-2">
          <input
            id="checkout-gift"
            className="input flex-1"
            value={giftCardCode}
            onChange={(e) => onGiftCardCodeChange(e.target.value.toUpperCase())}
            placeholder="e.g. GIFT1000"
            disabled={disabled}
            autoComplete="off"
          />
          <Button type="button" variant="secondary" disabled={disabled} onClick={onApplyGiftCard}>
            Apply
          </Button>
        </div>
        {giftCardError && <p className="text-xs text-red-400 mt-1" role="alert">{giftCardError}</p>}
        {giftCardMessage && !giftCardError && (
          <p className="text-xs text-brand-400 mt-1">{giftCardMessage}</p>
        )}
      </div>

      {preview?.applied?.length > 0 && (
        <div className="border-t border-brand-500/10 pt-4 space-y-2">
          <p className="text-xs uppercase tracking-wider text-slate-500">Applied</p>
          <ul className="space-y-1">
            {preview.applied.map((a) => (
              <li key={`${a.id}-${a.code}`} className="flex justify-between text-sm text-slate-300">
                <span>{a.name || a.code}</span>
                <span className="text-brand-400">
                  {a.freeDelivery && a.discount <= 0
                    ? 'Free delivery'
                    : `−${formatCurrency(a.discount)}`}
                </span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

/**
 * Debounced-friendly hook helper state for rewards inputs.
 */
export function useCheckoutRewardsState() {
  const [couponCode, setCouponCode] = useState('');
  const [appliedCouponCode, setAppliedCouponCode] = useState('');
  const [loyaltyPoints, setLoyaltyPoints] = useState(0);
  const [giftCardCode, setGiftCardCode] = useState('');
  const [appliedGiftCardCode, setAppliedGiftCardCode] = useState('');
  const [couponError, setCouponError] = useState('');
  const [couponMessage, setCouponMessage] = useState('');
  const [giftCardError, setGiftCardError] = useState('');
  const [giftCardMessage, setGiftCardMessage] = useState('');
  const [preview, setPreview] = useState(null);

  return {
    couponCode,
    setCouponCode,
    appliedCouponCode,
    setAppliedCouponCode,
    loyaltyPoints,
    setLoyaltyPoints,
    giftCardCode,
    setGiftCardCode,
    appliedGiftCardCode,
    setAppliedGiftCardCode,
    couponError,
    setCouponError,
    couponMessage,
    setCouponMessage,
    giftCardError,
    setGiftCardError,
    giftCardMessage,
    setGiftCardMessage,
    preview,
    setPreview,
  };
}
