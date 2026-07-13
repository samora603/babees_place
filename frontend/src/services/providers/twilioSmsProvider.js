/**
 * Twilio SMS stub — Edge Function holds account SID + auth token.
 */
export function createTwilioSmsProvider() {
  const edgeUrl = import.meta.env.VITE_SMS_EDGE_URL || '';

  return {
    id: 'twilio',
    channel: /** @type {const} */ ('sms'),
    async send(req) {
      if (!edgeUrl) {
        return {
          ok: false,
          error: 'VITE_SMS_EDGE_URL is not configured for Twilio',
        };
      }
      try {
        const res = await fetch(`${edgeUrl.replace(/\/$/, '')}/send`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ provider: 'twilio', ...req }),
        });
        const raw = await res.json().catch(() => ({}));
        if (!res.ok) {
          return { ok: false, error: raw.error || `HTTP ${res.status}`, raw };
        }
        return { ok: true, externalId: raw.sid || raw.externalId, raw };
      } catch (error) {
        return { ok: false, error: error.message || 'Twilio send failed' };
      }
    },
  };
}
