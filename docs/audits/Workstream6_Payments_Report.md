# Workstream 6 — Payments Foundation Report

**Date:** 2026-07-13  
**Status:** Complete (architecture + mock provider)  
**Live Daraja:** Not connected (by design)

---

## Objective

Transform Babees Place from COD-only checkout into a multi-payment platform while **preserving Cash on Delivery** as a fully working default path.

---

## Architecture summary

```
Checkout UI
  → orderService.placeOrder(..., paymentMethod)
  → paymentService.createPaymentForOrder (mpesa only)
       → create_payment_for_order RPC
       → mpesaService.initiateStkPush
            → getPaymentProvider()  // mock | daraja
       → mark_payment_initiated RPC
  → PaymentPending (poll)
       → mpesaService.queryStkStatus
       → finalize_payment RPC  (idempotent)
  → PaymentSuccess / PaymentFailed (+ retry)
```

### Design principles

1. **Services own business logic** — pages are presentation + wiring.
2. **Provider interface** — swap mock → Daraja with env + Edge Function only.
3. **Failed attempts retained** — each retry creates a new `payments` row.
4. **COD unchanged for express checkout** — still places order and goes to confirmation.
5. **No secrets in Vite** — Daraja credentials belong on Edge Function / server.

---

## Database changes (`016_payments.sql`)

| Object | Purpose |
|---|---|
| `orders.payment_method` | `cod` \| `mpesa` \| future methods (default `cod`) |
| `orders.mpesa_receipt_number` | Mirrored receipt on success |
| `payments` | Attempt ledger (provider, status, STK ids, receipt, phone, amount…) |
| `payment_events` | Audit trail / callbacks |
| RLS | Owner or admin read/write payments |
| `place_order(..., p_payment_method)` | Extended; default `cod` |
| `create_payment_for_order` | Create pending attempt |
| `mark_payment_initiated` | Store Checkout/Merchant request IDs |
| `finalize_payment` | Idempotent paid/failed/expired + order sync |

**Manual step:** apply `016_payments.sql` on the linked Supabase project before exercising M-Pesa flows against a real DB.

---

## Files added

### Database
- `supabase/migrations/016_payments.sql`

### Models / services
- `frontend/src/models/payment.js`
- `frontend/src/services/paymentValidation.js`
- `frontend/src/services/mpesaService.js`
- `frontend/src/services/paymentService.js` (replaces deferred stub)
- `frontend/src/services/providers/paymentProvider.js`
- `frontend/src/services/providers/mockMpesaProvider.js`
- `frontend/src/services/providers/darajaMpesaProvider.js`

### UI
- `frontend/src/components/checkout/PaymentMethodSelector.jsx`
- `frontend/src/components/checkout/MpesaPaymentPanel.jsx`
- `frontend/src/components/checkout/PaymentStatusBadge.jsx`
- `frontend/src/components/orders/PaymentDetailsCard.jsx`
- `frontend/src/pages/PaymentPending.jsx`
- `frontend/src/pages/PaymentSuccess.jsx`
- `frontend/src/pages/PaymentFailed.jsx`

### Tests
- `models/payment.test.js`
- `paymentValidation.test.js`
- `paymentService.test.js`
- `mockMpesaProvider.test.js`
- `test/migration-016.test.js`

### Docs
- `docs/audits/Workstream6_Payments_Report.md` (this file)

---

## Files modified

- `frontend/src/pages/Checkout.jsx` — method selector + M-Pesa flow
- `frontend/src/pages/OrderDetail.jsx` — payment card + retry
- `frontend/src/pages/admin/AdminOrders.jsx` — payment columns
- `frontend/src/pages/admin/AdminOrderDetail.jsx` — payment details
- `frontend/src/services/orderService.js` — `paymentMethod` on place + map
- `frontend/src/services/checkoutService.js` — express accepts payment method (COD)
- `frontend/src/services/adminService.js` — select payment fields
- `frontend/src/App.jsx` — payment routes
- `frontend/.env.example` — payment provider env docs
- `docs/technical/06_Frontend.md`
- `docs/database/Migration_History.md`
- `frontend/src/services/orderService.test.js`

---

## Live Daraja integration guide

When ready to connect Safaricom Daraja:

1. **Create Supabase Edge Functions** (recommended):
   - `mpesa/stk-push` — OAuth + STK Push
   - `mpesa/stk-query` — transaction query
   - `mpesa/callback` — receive Safaricom callbacks → call `finalize_payment`

2. **Set server secrets** (never in `VITE_*`):
   - `MPESA_CONSUMER_KEY`, `MPESA_CONSUMER_SECRET`, `MPESA_PASSKEY`
   - `MPESA_SHORTCODE`, `MPESA_CALLBACK_URL`, `MPESA_ENV`

3. **Frontend env:**
   - `VITE_PAYMENT_PROVIDER=daraja`
   - `VITE_MPESA_EDGE_URL=https://<ref>.supabase.co/functions/v1/mpesa`

4. **Code touchpoints (minimal):**
   - Fill in `services/providers/darajaMpesaProvider.js` (already stubs Edge calls)
   - Optionally harden `paymentService.handlePaymentCallback` for webhook bridge auth
   - Keep `getPaymentProvider()` as the only switch

5. **Do not change** checkout/order flow — provider swap is sufficient.

---

## Manual verification checklist

1. Apply migration `016`.
2. COD checkout → confirmation (unchanged).
3. Express checkout → COD confirmation.
4. M-Pesa checkout with `VITE_PAYMENT_PROVIDER=mock` → STK pending → auto success → Payment Success → order `payment_status=paid` + receipt.
5. Force fail / timeout → Payment Failed → Retry creates new payment row.
6. Customer Order Detail shows method, status, receipt, retry when eligible.
7. Admin Orders list shows payment method + status; detail shows PaymentDetailsCard.
8. Duplicate finalize of already-paid payment is ignored (event `duplicate_callback_ignored`).

---

## Known limitations

1. Mock provider only — no live Safaricom traffic.
2. Card / PayPal / bank are UI-disabled placeholders.
3. Express checkout intentionally stays COD.
4. Until `016` is applied, M-Pesa RPCs/tables are unavailable (COD still works if `place_order` old signature is what DB has — **apply 016 before testing M-Pesa**).
5. Polling is client-side; production should rely primarily on callback Edge Function.

---

## Stop line

Workstream 6 foundation complete. **Do not begin notifications or loyalty features.**
