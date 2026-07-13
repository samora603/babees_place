/**
 * Africa's Talking SMS stub — Edge Function holds API key + username.
 */
export function createAfricasTalkingSmsProvider() {
  const edgeUrl = import.meta.env.VITE_SMS_EDGE_URL || '';

  return {
    id: 'africastalking',
    channel: /** @type {const} */ ('sms'),
    async send(req) {
      if (!edgeUrl) {
        return {
          ok: false,
          error: 'VITE_SMS_EDGE_URL is not configured for Africa\'s Talking',
        };
      }
      try {
        const res = await fetch(`${edgeUrl.replace(/\/$/, '')}/send`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ provider: 'africastalking', ...req }),
        });
        const raw = await res.json().catch(() => ({}));
        if (!res.ok) {
          return { ok: false, error: raw.error || `HTTP ${res.status}`, raw };
        }
        return { ok: true, externalId: raw.messageId || raw.externalId, raw };
      } catch (error) {
        return { ok: false, error: error.message || 'Africa\'s Talking send failed' };
      }
    },
  };
}
