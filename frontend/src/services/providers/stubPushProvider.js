/**
 * Web Push provider interface stub — browser push not implemented yet.
 */
export function createStubPushProvider(mode = 'stub') {
  return {
    id: mode === 'webpush' ? 'webpush_stub' : 'stub_push',
    channel: /** @type {const} */ ('push'),
    async send(_req) {
      return {
        ok: false,
        skipped: true,
        error: 'Web push is not implemented yet (architecture stub only)',
      };
    },
  };
}
