import { describe, it, expect } from 'vitest';
import {
  validateCoupon,
  computePromotionDiscount,
  applyPromotions,
  calculateLoyaltyRedemption,
  calculateGiftCardRedemption,
  previewCheckoutRewards,
  calculateEarnPoints,
} from '@/services/rewardEngine';

const lines = [
  { id: '1', productId: 'p1', categoryId: 'c1', price: 500, quantity: 2 },
  { id: '2', productId: 'p2', categoryId: 'c2', price: 1000, quantity: 1 },
];

describe('rewardEngine', () => {
  it('validates percentage coupons', () => {
    const result = validateCoupon({
      id: 'c1',
      code: 'SAVE10',
      discountType: 'percentage',
      percentOff: 10,
      isActive: true,
      minOrderAmount: 100,
      usageCount: 0,
    }, { subtotal: 2000 });
    expect(result.valid).toBe(true);
    expect(result.discount).toBe(200);
  });

  it('rejects expired or overused coupons', () => {
    const expired = validateCoupon({
      id: 'c1',
      code: 'OLD',
      discountType: 'fixed',
      amountOff: 50,
      isActive: true,
      endsAt: '2020-01-01',
    }, { subtotal: 500, now: new Date('2026-01-01') });
    expect(expired.valid).toBe(false);

    const limited = validateCoupon({
      id: 'c1',
      code: 'ONCE',
      discountType: 'fixed',
      amountOff: 50,
      isActive: true,
      isOneTime: true,
    }, { subtotal: 500, userRedemptionCount: 1 });
    expect(limited.valid).toBe(false);
  });

  it('computes storewide and BXGY promotions', () => {
    const store = computePromotionDiscount({
      id: '1',
      promoType: 'storewide',
      percentOff: 10,
      status: 'active',
      minOrderAmount: 0,
    }, lines);
    expect(store.discount).toBe(200);

    const bxgy = computePromotionDiscount({
      id: '2',
      promoType: 'buy_x_get_y',
      buyQuantity: 1,
      getQuantity: 1,
      productId: 'p1',
      status: 'active',
    }, [{ id: '1', productId: 'p1', price: 100, quantity: 4 }]);
    expect(bxgy.discount).toBe(200);
  });

  it('applies priority and stacking rules', () => {
    const result = applyPromotions([
      {
        id: 'a', name: 'A', promoType: 'percentage', percentOff: 20,
        priority: 10, stackable: false, status: 'active',
      },
      {
        id: 'b', name: 'B', promoType: 'fixed', amountOff: 50,
        priority: 100, stackable: false, status: 'active',
      },
      {
        id: 'c', name: 'C', promoType: 'fixed', amountOff: 25,
        priority: 5, stackable: true, status: 'active',
      },
    ], lines);

    // Highest priority non-stackable (B) + stackable C
    expect(result.applied.map((x) => x.id)).toEqual(['b', 'c']);
    expect(result.merchandiseDiscount).toBe(75);
  });

  it('calculates loyalty redemption with caps', () => {
    const ok = calculateLoyaltyRedemption(200, {
      balance: 500,
      redeemPointsPerCurrency: 10,
      minRedeemPoints: 100,
      maxRedeemPercent: 50,
      subtotal: 1000,
    });
    expect(ok.discount).toBe(20);
    expect(ok.points).toBe(200);

    const insufficient = calculateLoyaltyRedemption(100, {
      balance: 50,
      minRedeemPoints: 100,
      subtotal: 1000,
    });
    expect(insufficient.errors.length).toBeGreaterThan(0);
  });

  it('supports partial gift card redemption', () => {
    const result = calculateGiftCardRedemption(1000, null, 350);
    expect(result.amount).toBe(350);
    const capped = calculateGiftCardRedemption(100, 500, 350);
    expect(capped.amount).toBe(100);
  });

  it('previews full checkout rewards stack', () => {
    const preview = previewCheckoutRewards({
      lines,
      promotions: [{
        id: 'p', name: '10%', promoType: 'storewide', percentOff: 10,
        priority: 50, status: 'active',
      }],
      coupon: {
        id: 'c', code: 'FREESHIP', discountType: 'free_delivery',
        freeDelivery: true, isActive: true,
      },
      loyaltyPointsToRedeem: 100,
      loyaltyBalance: 500,
      loyaltyRules: { redeemPointsPerCurrency: 10, minRedeemPoints: 100, maxRedeemPercent: 50 },
      giftCardBalance: 50,
      deliveryType: 'delivery',
      deliveryFee: 200,
    });

    expect(preview.freeDelivery).toBe(true);
    expect(preview.deliveryFee).toBe(0);
    expect(preview.merchandiseDiscount).toBeGreaterThan(0);
    expect(preview.giftCardAmount).toBe(50);
    expect(preview.total).toBeLessThan(2000);
  });

  it('calculates earn points', () => {
    expect(calculateEarnPoints(1999, 0.01)).toBe(19);
  });
});
