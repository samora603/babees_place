import { supabase } from '@/lib/supabaseClient';

export const wishlistService = {
  getWishlist: async (userId) => {
    try {
      if (!userId) return { data: { products: [] }, error: null };
      const { data, error } = await supabase.from('wishlist').select('*, products(*)').eq('user_id', userId);
      if (error) {
        console.error('wishlistService.getWishlist error:', error);
        return { data: { products: [] }, error };
      }
      return { data: { products: (data || []).map((row) => row.products || row) }, error: null };
    } catch (err) {
      console.error('wishlistService.getWishlist exception:', err);
      return { data: { products: [] }, error: err };
    }
  },

  addToWishlist: async (userId, productId) => {
    try {
      if (!userId || !productId) return { data: { products: [] }, error: null };
      const { data: existing } = await supabase.from('wishlist').select('*').eq('user_id', userId).eq('product_id', productId).maybeSingle();
      if (existing) return { data: { products: [existing] }, error: null };
      const { data, error } = await supabase.from('wishlist').insert({ user_id: userId, product_id: productId }).select('*').single();
      if (error) return { data: { products: [] }, error };
      return { data: { products: [data] }, error: null };
    } catch (err) {
      console.error('wishlistService.addToWishlist exception:', err);
      return { data: { products: [] }, error: err };
    }
  },

  removeFromWishlist: async (userId, productId) => {
    try {
      if (!userId || !productId) return { data: { products: [] }, error: null };
      const { error } = await supabase.from('wishlist').delete().eq('user_id', userId).eq('product_id', productId);
      return { data: { products: [] }, error };
    } catch (err) {
      console.error('wishlistService.removeFromWishlist exception:', err);
      return { data: { products: [] }, error: err };
    }
  },
};
