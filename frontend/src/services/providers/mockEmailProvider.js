/**
 * Mock email provider — logs to console + returns synthetic message ids.
 * Replace with Resend/SendGrid/SMTP via VITE_EMAIL_PROVIDER + Edge Function.
 */

/** @type {Array<object>} */
const mockOutbox = [];

export function getMockEmailOutbox() {
  return [...mockOutbox];
}

export function clearMockEmailOutbox() {
  mockOutbox.length = 0;
}

export function createMockEmailProvider() {
  return {
    id: 'mock_email',
    channel: /** @type {const} */ ('email'),
    async send(req) {
      const externalId = `mock-email-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      const record = {
        externalId,
        to: req.to || null,
        subject: req.subject || null,
        body: req.body,
        eventType: req.eventType,
        metadata: req.metadata || {},
        sentAt: new Date().toISOString(),
      };
      mockOutbox.push(record);
      if (import.meta.env.DEV) {
        console.info('[mock_email]', record);
      }
      return { ok: true, externalId, raw: record };
    },
  };
}
