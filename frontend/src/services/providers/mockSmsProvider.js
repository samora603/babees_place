/**
 * Mock SMS provider — stores sends in memory for tests/dev.
 */

/** @type {Array<object>} */
const mockOutbox = [];

export function getMockSmsOutbox() {
  return [...mockOutbox];
}

export function clearMockSmsOutbox() {
  mockOutbox.length = 0;
}

export function createMockSmsProvider() {
  return {
    id: 'mock_sms',
    channel: /** @type {const} */ ('sms'),
    async send(req) {
      if (!req.to) {
        return { ok: false, error: 'SMS requires a phone number (to)' };
      }
      const externalId = `mock-sms-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
      const record = {
        externalId,
        to: req.to,
        body: req.body,
        eventType: req.eventType,
        metadata: req.metadata || {},
        sentAt: new Date().toISOString(),
      };
      mockOutbox.push(record);
      if (import.meta.env.DEV) {
        console.info('[mock_sms]', record);
      }
      return { ok: true, externalId, raw: record };
    },
  };
}
