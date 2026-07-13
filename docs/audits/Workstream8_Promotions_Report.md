# Workstream 8 — Promotions, Loyalty & Customer Retention Report

**Date:** 2026-07-13  
**Status:** Complete (foundation)  
**Stop line:** Do not begin deployment / other workstreams in this pass.

---

## Objective

Increase retention with a generic promotion engine, coupons, loyalty points, referrals, and gift cards — integrated into checkout without breaking COD/M-Pesa flows.

---

## Architecture summary

```
Checkout UI (CheckoutRewardsPanel)
  → checkoutRewardsService.buildCheckoutRewardPreview
       → promotionService / couponService / loyaltyService / giftCardService
       → rewardEngine.previewCheckoutRewards (pure)
  → orderService.placeOrder(+ reward params)
       → place_order RPC (server validates coupon/points/gift card; clamps totals)
  → payment amount uses preview.total
  → on paid / COD: award_loyalty_for_order + referral qualify
```

### Design principles

1. **rewardEngine is pure** — no React, no Supabase; fully unit-tested.
2. **place_order defaults** — omitting reward params preserves prior COD behavior once migration is applied (new signature with defaults).
3. **Services own business logic** — admin/customer pages are CRUD + display.
4. **Stacking** — priority DESC; at most one non-stackable; stackables always eligible.
5. **Mock seeds** — `WELCOME15`, `FREESHIP`, `SAVE200`, `GIFT1000`, `STORE10`, default loyalty rules.

---

## Database (`018_promotions_loyalty.sql`)

| Object | Purpose |
|---|---|
| `promotions`, `promotion_rules` | Campaign engine |
| `coupons`, `coupon_redemptions` | Codes + usage |
| `loyalty_accounts`, `loyalty_transactions`, `loyalty_rules` | Points |
| `gift_cards`, `gift_card_transactions` | Balances + partial redeem |
| `referrals`, `reward_events` | Referral tracking + audit |
| `orders.*` reward columns | discount, coupon, points, gift card, free_delivery, promotions_applied |
| Extended `place_order` | Optional reward params |
| `ensure_loyalty_account`, `lookup_gift_card`, `award_loyalty_for_order` | Helpers |

**Manual step:** apply `018` after `017` before exercising rewards against a live DB.

---

## Files added (high level)

- Migration `018_promotions_loyalty.sql`
- `rewardEngine.js`, `checkoutRewardsService.js`
- `promotionService`, `couponService`, `loyaltyService`, `giftCardService`, `referralService`
- `models/rewards.js`
- `CheckoutRewardsPanel.jsx`, `Rewards.jsx`
- Admin: Promotions, Coupons, Gift Cards, Loyalty
- Tests: `rewardEngine.test.js`, `migration-018.test.js`
- `docs/audits/Workstream8_Promotions_Report.md`

## Files modified

- `Checkout.jsx`, `orderService.js`, `paymentService.js`, `AuthContext.jsx`
- `App.jsx`, `AdminLayout.jsx`, `Navbar.jsx`, `Profile.jsx`
- Docs: Migration_History, 06_Frontend, 01_ARCHITECTURE

---

## Manual verification

1. Apply `018_promotions_loyalty.sql`
2. Checkout without rewards → same totals as before
3. Apply `WELCOME15` / `FREESHIP` / `SAVE200` → summary updates
4. Redeem points (min 100) → discount + balance drop after order
5. `GIFT1000` partial redeem against total
6. `/rewards` shows balance, referral code, coupons
7. Admin CRUD for promotions/coupons/gift cards/loyalty rules
8. M-Pesa amount matches discounted total

---

## Stop line

Workstream 8 foundation is complete. Do not begin deployment or unrelated features in this workstream.
