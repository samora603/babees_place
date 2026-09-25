# M-Pesa Edge Function — OAuth smoke test

Proves:

```text
Babees Place (Edge Function)
  → Daraja Sandbox OAuth
  → Access token received (server-side only)
```

Does **not** change checkout, mock M-Pesa, or STK Push.

## Secrets (server-side only)

| Variable | Required for OAuth | Notes |
|----------|--------------------|-------|
| `MPESA_CONSUMER_KEY` | Yes | Daraja app Consumer Key |
| `MPESA_CONSUMER_SECRET` | Yes | Daraja app Consumer Secret |
| `MPESA_ENV` | No (default `sandbox`) | `sandbox` \| `production` |

Do **not** set these as `VITE_*` or in `frontend/.env`.

## Local setup

**Correct file (required):** `supabase/functions/.env`  
**Wrong places:** `frontend/.env`, `VITE_*` vars, Daraja portal alone, or `.env.example` files.

1. Ensure the env file exists:

```bash
cp supabase/functions/mpesa/.env.example supabase/functions/.env
```

2. Edit **`supabase/functions/.env`** so the values are non-empty (no spaces around `=`):

```env
MPESA_ENV=sandbox
MPESA_CONSUMER_KEY=paste_key_here
MPESA_CONSUMER_SECRET=paste_secret_here
```

Quick check that values are present (does not print secrets):

```bash
python3 - <<'PY'
from pathlib import Path
p = Path('supabase/functions/.env')
keys = {}
for line in p.read_text().splitlines():
    s = line.strip()
    if not s or s.startswith('#') or '=' not in s: continue
    k, v = s.split('=', 1)
    keys[k.strip()] = bool(v.strip().strip('"').strip("'"))
print('KEY_SET=', keys.get('MPESA_CONSUMER_KEY'))
print('SECRET_SET=', keys.get('MPESA_CONSUMER_SECRET'))
PY
```

Both must print `True` before OAuth can succeed.

3. **Restart** the function after editing `.env` (env is loaded at start):

```bash
# stop the old serve (Ctrl+C), then:
supabase functions serve mpesa --env-file supabase/functions/.env --no-verify-jwt
```

4. Call OAuth:

```bash
curl -sS http://127.0.0.1:54321/functions/v1/mpesa/oauth | jq
```

### Expected success

```json
{
  "ok": true,
  "authenticated": true,
  "env": "sandbox",
  "tokenType": "Bearer",
  "expiresIn": 3599,
  "message": "Daraja OAuth succeeded; access token retained server-side"
}
```

The **access token is never returned** to the client.

### Expected failure examples

- Missing secrets → `500` with message about missing `MPESA_CONSUMER_KEY` / `MPESA_CONSUMER_SECRET`
- Invalid credentials → `502` with `darajaStatus` (no secrets logged)

## Remote secrets (when you deploy later)

```bash
supabase secrets set \
  MPESA_ENV=sandbox \
  MPESA_CONSUMER_KEY="your-key" \
  MPESA_CONSUMER_SECRET="your-secret"
```

Do **not** deploy or switch `VITE_PAYMENT_PROVIDER=daraja` until STK is ready.

## Routes

| Method | Path | Status |
|--------|------|--------|
| GET/POST | `/oauth` or `/token` or `/` | Implemented (OAuth only) |
| POST | `/stk-push` | Not Implemented |
| POST | `/stk-query` | Not Implemented |
| POST | `/callback` | Not Implemented |

## Frontend (unchanged)

Keep:

```env
VITE_PAYMENT_PROVIDER=mock
```

`darajaMpesaProvider.js` will later call `VITE_MPESA_EDGE_URL` + `/stk-push` — not used for this OAuth test.
