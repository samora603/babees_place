import { supabase } from '@/lib/supabase';

// The `addresses` table is DEFERRED (Phase 2) — it is not part of the approved
// canonical schema. Address methods are guarded so they never query a missing
// table; wire them to a real table when the feature is designed.
const FEATURE_DEFERRED = { message: 'This feature is not available yet.' };

export const userService = {
    getProfile: async () => {
        const { data, error } = await supabase.auth.getUser();
        return { data: { data, error } };
    },
    updateProfile: async (payload) => {
        const { data: userRes } = await supabase.auth.getUser();
        const user = userRes.user;
        if (!user) return { data: { data: null, error: 'Not authenticated' } };

        // Strip privilege-related columns so a client cannot self-escalate.
        const { full_name, name, email, role, is_admin, created_at, ...rest } = payload;
        void role;
        void is_admin;
        void created_at;
        const update = { id: user.id, ...rest };

        if (full_name !== undefined || name !== undefined) {
            update.full_name = full_name ?? name;
        }
        if (email !== undefined) {
            update.email = email;
        }

        const { data, error } = await supabase.from('profiles').upsert(update).select().single();
        return { data: { data, error } };
    },
    // Address book — DEFERRED (Phase 2); no `addresses` table in canonical schema.
    getAddresses: async () => ({ data: { data: [], error: null } }),
    addAddress: async () => ({ data: { data: null, error: FEATURE_DEFERRED } }),
    updateAddress: async () => ({ data: { data: null, error: FEATURE_DEFERRED } }),
    deleteAddress: async () => ({ data: { data: null, error: FEATURE_DEFERRED } }),
};
