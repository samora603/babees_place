/**
 * Resend email provider stub.
 * LIVE: call Edge Function that holds RESEND_API_KEY — never put the key in Vite.
 */
export function createResendEmailProvider() {
  const edgeUrl = import.meta.env.VITE_EMAIL_EDGE_URL || '';

  return {
    id: 'resend',
    channel: /** @type {const} */ ('email'),
    async send(req) {
      if (!edgeUrl) {
        return {
          ok: false,
          error: 'VITE_EMAIL_EDGE_URL is not configured for Resend',
        };
      }
      try {
        const res = await fetch(`${edgeUrl.replace(/\/$/, '')}/send`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(req),
        });
        const raw = await res.json().catch(() => ({}));
        if (!res.ok) {
          return { ok: false, error: raw.error || `HTTP ${res.status}`, raw };
        }
        return { ok: true, externalId: raw.id || raw.externalId, raw };
      } catch (error) {
        return { ok: false, error: error.message || 'Resend send failed' };
      }
    },
  };
}
