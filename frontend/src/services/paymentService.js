// Payments are DEFERRED (Phase 2). The `payments` table is intentionally NOT
// part of the approved canonical schema (see Reconciliation_Decision_Log.md).
// Real payment processing (M-Pesa, etc.) requires a server-side integration and
// a dedicated table designed in a later phase. These methods are guarded so they
// never query a non-existent table.
const FEATURE_DEFERRED = { message: 'Payments are not available yet.' };

export const paymentService = {
    createPayment: async () => ({ data: { data: null, error: FEATURE_DEFERRED } }),
    verifyPayment: async () => ({ data: { data: null, error: FEATURE_DEFERRED } }),
};
