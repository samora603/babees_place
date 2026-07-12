import { supabase } from '@/lib/supabaseClient';

export const productService = {
  getProducts: async (params = {}) => {
    try {
      // Embed the canonical category row (FK products.category_id -> categories.id).
      let query = supabase
        .from('products')
        .select('*, categories (id, name, slug)', { count: 'exact' });
      if (params.search) query = query.ilike('name', `%${params.search}%`);
      // Filter by the canonical FK; Shop passes a category id (uuid).
      if (params.category) query = query.eq('category_id', params.category);
      if (params.minPrice) query = query.gte('price', Number(params.minPrice));
      if (params.maxPrice) query = query.lte('price', Number(params.maxPrice));
      if (params.inStock) query = query.gt('stock', 0);
      if (params.includeInactive !== true) query = query.eq('is_active', true);
      // Sorting is limited to canonical columns (created_at, price).
      const sortMap = {
        '-createdAt': ['created_at', false],
        price: ['price', true],
        '-price': ['price', false],
      };
      const [sortCol, sortAsc] = sortMap[params.sort] || ['created_at', false];
      query = query.order(sortCol, { ascending: sortAsc });
      if (params.page && params.limit) {
        const from = (Number(params.page) - 1) * Number(params.limit);
        const to = from + Number(params.limit) - 1;
        query = query.range(from, to);
      } else if (params.limit) {
        query = query.limit(Number(params.limit));
      }
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
      const { data, error } = await supabase.from('products').select('*, categories (id, name, slug)').eq('id', id).maybeSingle();
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
      const { data, error } = await supabase.from('products').select('*, categories (id, name, slug)').eq('id', idOrSlug).maybeSingle();
      if (error || !data) {
        const fallback = await supabase.from('products').select('*, categories (id, name, slug)').ilike('slug', `%${idOrSlug}%`).maybeSingle();
        return { data: { data: fallback.data ?? null }, error: null };
      }
      return { data: { data }, error: null };
    } catch (err) {
      console.error('productService.getProduct exception:', err);
      return { data: { data: null }, error: null };
    }
  },

  // Categories are read from the canonical `categories` table (single source of
  // truth) rather than derived from the deprecated products.category text.
  getCategories: async () => {
    const { data, error } = await supabase
      .from('categories')
      .select('id, name, slug')
      .order('name', { ascending: true });

    if (error) {
      console.error('productService.getCategories error:', error);
      return { data: { data: [] }, error: null };
    }

    return { data: { data: Array.isArray(data) ? data : [] }, error: null };
  },
};
