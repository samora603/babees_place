# Workstream 7 — Notifications & Customer Communications Report

**Date:** 2026-07-13  
**Status:** Complete (architecture + mock email/SMS providers)  
**Live Resend / Africa's Talking / Twilio:** Not connected (by design)

---

## Objective

Add a modular, event-driven notification system for customers and admins — in-app inbox, email/SMS abstractions, preferences, and templates — without coupling business logic to any vendor.

---

## Architecture summary

```
Domain event (order / payment / auth / inventory)
  → notificationService.emitSafe(eventType, payload)
       → ensure preferences + template render
       → create in-app notification (RLS)
       → notification_deliveries rows
       → getProviderForChannel(email|sms|push|in_app)
            → mock_* (default) | resend / AT / Twilio stubs
       → notify_admin_users RPC (admin fan-out)
```

### Design principles

1. **Services own business logic** — pages are presentation only.
2. **Provider interface** — swap mock → live via env + Edge Functions.
3. **emitSafe** — never breaks checkout/auth if notification DB is unavailable.
4. **Preferences gate channels** — email/SMS/order/payment/marketing toggles.
5. **No secrets in Vite** — API keys belong on Edge Functions / server.

### Supported events

| Event | Audience |
|---|---|
| account_registration, welcome | Customer |
| password_reset, email_verification | Customer (helpers ready) |
| order_created / confirmed / cancelled / ready_for_pickup / out_for_delivery / delivered | Customer |
| payment_initiated / successful / failed / retry | Customer |
| admin_new_order / admin_payment_received / admin_low_inventory | Admin |

---

## Database changes (`017_notifications.sql`)

| Object | Purpose |
|---|---|
| `notifications` | In-app inbox (read/unread/archived) |
| `notification_templates` | Seeded `{{var}}` templates per channel |
| `notification_deliveries` | Per-channel send attempts + retry_count |
| `notification_preferences` | Channel + category toggles |
| `notification_events` | Emit audit trail |
| `customer_preferences` columns | `email_notifications`, `order_updates`, `payment_updates` |
| RPCs | `ensure_notification_preferences`, `notify_admin_users`, `mark_notification_read`, `mark_all_notifications_read`, `archive_notification` |

**Manual step:** apply `017_notifications.sql` (after `016`) before exercising inbox against a live DB.

---

## Files added

### Database
- `supabase/migrations/017_notifications.sql`

### Models / services / providers
- `frontend/src/models/notification.js`
- `frontend/src/services/templateService.js`
- `frontend/src/services/notificationService.js`
- `frontend/src/services/notificationPreferenceService.js`
- `frontend/src/services/emailService.js`
- `frontend/src/services/smsService.js`
- `frontend/src/services/providers/notificationProviderFactory.js`
- `frontend/src/services/providers/mockEmailProvider.js`
- `frontend/src/services/providers/mockSmsProvider.js`
- `frontend/src/services/providers/resendEmailProvider.js`
- `frontend/src/services/providers/africasTalkingSmsProvider.js`
- `frontend/src/services/providers/twilioSmsProvider.js`
- `frontend/src/services/providers/stubPushProvider.js`
- `frontend/src/services/providers/inAppProvider.js`

### UI
- `frontend/src/hooks/useNotifications.js`
- `frontend/src/components/notifications/NotificationBell.jsx`
- `frontend/src/components/notifications/NotificationItem.jsx`
- `frontend/src/components/notifications/NotificationList.jsx`
- `frontend/src/components/notifications/NotificationStatusBadge.jsx`
- `frontend/src/pages/Notifications.jsx`
- `frontend/src/pages/admin/AdminNotifications.jsx`

### Tests
- `models/notification.test.js`
- `templateService.test.js`
- `notificationService.test.js`
- `providers/notificationProviders.test.js`
- `test/migration-017.test.js`

### Docs
- `docs/audits/Workstream7_Notifications_Report.md` (this file)

---

## Files modified

- `Navbar.jsx` — notification bell + links
- `AdminLayout.jsx` — Alerts nav + header badge
- `App.jsx` — `/notifications`, `/admin/notifications`
- `AccountPreferencesForm.jsx` — full notification toggles
- `models/preferences.js` — email/order/payment flags
- `orderService.js` — order created/cancelled emits
- `paymentService.js` — payment lifecycle emits
- `adminService.js` — status + low-stock emits
- `AuthContext.jsx` — registration / welcome emits
- `.env.example`, `06_Frontend.md`, `Migration_History.md`

---

## Future integration guide

### Resend (email)

1. Create Edge Function `email/send` holding `RESEND_API_KEY`.
2. Set `VITE_EMAIL_PROVIDER=resend` and `VITE_EMAIL_EDGE_URL=…/functions/v1/email`.
3. Implement `resendEmailProvider.js` fetch (already stubbed) against that Edge URL.
4. No UI changes required.

### Africa's Talking (SMS)

1. Edge Function `sms/send` with `AT_API_KEY` + `AT_USERNAME`.
2. `VITE_SMS_PROVIDER=africastalking` + `VITE_SMS_EDGE_URL`.
3. Stub provider already routes through the Edge URL.

### Twilio (SMS)

1. Same Edge Function pattern with Twilio Account SID + Auth Token.
2. `VITE_SMS_PROVIDER=twilio`.

### Web Push

Interface only (`stubPushProvider`). Implement browser push later behind `VITE_PUSH_PROVIDER` without changing emit callers.

---

## Manual verification checklist

1. Apply migration `017_notifications.sql`.
2. Register a user → welcome / registration in-app (when DB available).
3. Place COD order → customer order notification + admin alert.
4. Mock M-Pesa success → payment successful + admin payment received.
5. Navbar bell shows unread; `/notifications` filters / mark read / archive.
6. Admin `/admin/notifications` shows new orders / low stock after stock edit below threshold.
7. Profile preferences toggle email/SMS/order/payment/marketing and save.
8. Confirm checkout still succeeds if notification tables are missing (`emitSafe`).

---

## Stop line

Workstream 7 foundation is complete. **Do not begin loyalty, coupons, or deployment** in this workstream.
