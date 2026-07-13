/**
 * In-app channel provider — persistence is handled by notificationService.
 * This provider marks the channel send as successful once the inbox row exists.
 */
export function createInAppProvider() {
  return {
    id: 'in_app',
    channel: /** @type {const} */ ('in_app'),
    async send(req) {
      return {
        ok: true,
        externalId: req.metadata?.notificationId || `in-app-${Date.now()}`,
        raw: { persisted: Boolean(req.metadata?.notificationId) },
      };
    },
  };
}
