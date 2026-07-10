import { supabase } from '@/lib/supabase';

export const userService = {
    getProfile: async () => {
        const { data, error } = await supabase.auth.getUser();
        return { data: { data, error } };
    },
    updateProfile: async (payload) => {
        const { data: userRes } = await supabase.auth.getUser();
        const user = userRes.user;
        if (!user) return { data: { data: null, error: 'Not authenticated' } };

        const { full_name, name, email, ...rest } = payload;
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
    getAddresses: async () => {
        const { data: userRes } = await supabase.auth.getUser();
        const user = userRes.user;
        if (!user) return { data: { data: [] } };
        const { data, error } = await supabase.from('addresses').select('*').eq('user_id', user.id);
        return { data: { data, error } };
    },
    addAddress: async (payload) => {
        const { data: userRes } = await supabase.auth.getUser();
        const user = userRes.user;
        if (!user) return { data: { data: null, error: 'Not authenticated' } };
        const { data, error } = await supabase.from('addresses').insert({ user_id: user.id, ...payload }).select();
        return { data: { data, error } };
    },
    updateAddress: async (id, payload) => {
        const { data, error } = await supabase.from('addresses').update(payload).eq('id', id).select();
        return { data: { data, error } };
    },
    deleteAddress: async (id) => {
        const { data, error } = await supabase.from('addresses').delete().eq('id', id).select();
        return { data: { data, error } };
    },
};
