# Operational Runbook

## Daily / weekly checks

| Check | Where |
|---|---|
| System health | `/admin/health` |
| Failed payments | Admin Orders + payment status filters |
| Low stock | Admin Inventory / dashboard widget |
| Audit trail | `/admin/health` audit section |
| CI status | GitHub Actions |

## Common incidents

### Checkout failing

1. Check `/admin/health` database probe
2. Confirm cart not empty / stock available
3. Inspect browser console logs (structured `[ORDER]` / `[ERROR]`)
4. Verify `place_order` exists on DB (migration 016/018)

### M-Pesa stuck pending

1. Confirm `VITE_PAYMENT_PROVIDER` (mock vs daraja)
2. Check payment row + `payment_events`
3. Use order retry payment from customer order detail
4. Live Daraja: verify Edge Function secrets + callback URL

### Admin cannot access

1. Confirm `profiles.role = 'admin'`
2. Confirm `is_admin()` function present
3. Clear session and re-login

### Notifications missing

1. Apply migration `017`
2. Confirm preferences allow channel
3. Mock providers log to console in DEV

## Exports

From `/admin/health` audit panel: CSV / JSON / Excel-friendly CSV / print-to-PDF.

## Logging

- Client ring buffer: last ~200 entries via `logger.getRecentLogs()`
- Levels: `VITE_LOG_LEVEL`
- Secrets are redacted from meta payloads

## Contacts

Maintain an on-call rotation outside this repo (Slack/email). Document escalation privately.
