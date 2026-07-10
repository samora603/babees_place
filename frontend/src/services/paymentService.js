import { supabase } from '@/lib/supabase';

export const paymentService = {
    createPayment: async (payload) => {
        // If you have a payments table, insert a record to keep history. Real payment processing
        // still requires server-side integration (MPesa, Stripe, etc.). This is a local stub.
        const { data, error } = await supabase.from('payments').insert(payload).select().single();
        return { data: { data, error } };
    },
    verifyPayment: async (id) => {
        const { data, error } = await supabase.from('payments').select('*').eq('id', id).single();
        return { data: { data, error } };
    },
};
