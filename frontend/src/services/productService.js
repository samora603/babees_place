import { supabase } from '@/lib/supabaseClient';

export const productService = {
  getProducts: async (params = {}) => {
    try {
      let query = supabase.from('products').select('*', { count: 'exact' });
      if (params.limit) query = query.limit(Number(params.limit));
      if (params.page && params.limit) {
        const from = (Number(params.page) - 1) * Number(params.limit);
        const to = from + Number(params.limit) - 1;
        query = query.range(from, to);
      }
      if (params.search) query = query.ilike('name', `%${params.search}%`);
      if (params.category) query = query.eq('category', params.category);
      if (params.minPrice) query = query.gte('price', Number(params.minPrice));
      if (params.maxPrice) query = query.lte('price', Number(params.maxPrice));
      const { data, error, count } = await query;
      if (error) {
        console.error('productService.getProducts error:', error);
        return { data: { data: [], total: 0, pages: 1 }, error: null };
      }
      const total = count ?? (Array.isArray(data) ? data.length : 0);
      const limit = Number(params.limit) || total || 1;
      const pages = Math.max(1, Math.ceil(total / limit));
      return { data: { data: Array.isArray(data) ? data : [], total, pages }, error: null };
    } catch (err) {
      console.error('productService.getProducts exception:', err);
      return { data: { data: [], total: 0, pages: 1 }, error: null };
    }
  },

  getProductById: async (id) => {
    try {
      const { data, error } = await supabase.from('products').select('*').eq('id', id).maybeSingle();
      if (error) {
        console.error('productService.getProductById error:', error);
        return { data: { data: null }, error: null };
      }
      return { data: { data }, error: null };
    } catch (err) {
      console.error('productService.getProductById exception:', err);
      return { data: { data: null }, error: null };
    }
  },

  getProduct: async (idOrSlug) => {
    try {
      const { data, error } = await supabase.from('products').select('*').eq('id', idOrSlug).maybeSingle();
      if (error || !data) {
        const fallback = await supabase.from('products').select('*').ilike('slug', `%${idOrSlug}%`).maybeSingle();
        return { data: { data: fallback.data ?? null }, error: null };
      }
      return { data: { data }, error: null };
    } catch (err) {
      console.error('productService.getProduct exception:', err);
      return { data: { data: null }, error: null };
    }
  },

    getCategories: async () => {
    const { data, error } = await supabase
      .from('products')
      .select('category');

    if (error) return { data: { data: [] }, error };

    const categories = [...new Set(data.map(p => p.category).filter(Boolean))]
      .map((name, i) => ({
        id: String(i + 1),
        name
      }));

    return { data: { data: categories }, error: null };
  },
};
