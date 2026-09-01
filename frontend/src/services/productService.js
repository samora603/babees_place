import { supabase } from '@/lib/supabaseClient';
import { isUuid } from '@/utils/slug';

const PRODUCT_SELECT = '*, categories (id, name, slug)';

/**
 * Escape characters that are special in Postgres ILIKE patterns and PostgREST `.or()` filters.
 * @param {string} raw
 * @returns {string}
 */
export function escapeIlikePattern(raw) {
  return String(raw ?? '')
    .replace(/\\/g, '\\\\')
    .replace(/%/g, '\\%')
    .replace(/_/g, '\\_')
    .replace(/,/g, ' ')
    .replace(/[()]/g, '')
    .trim();
}

/**
 * Build a PostgREST `.or()` filter for storefront product search.
 * Searches name + description (case-insensitive partial match).
 * Category name matching is handled separately via category_id IN (...).
 * Brand/SKU: not present on the products schema — intentionally omitted.
 *
 * @param {string} search
 * @param {string[]} [categoryIds]
 * @returns {string|null}
 */
export function buildProductSearchOrFilter(search, categoryIds = []) {
  const pattern = escapeIlikePattern(search);
  if (!pattern) return null;

  const clauses = [
    `name.ilike.%${pattern}%`,
    `description.ilike.%${pattern}%`,
  ];

  const ids = (categoryIds || []).filter(Boolean);
  if (ids.length > 0) {
    clauses.push(`category_id.in.(${ids.join(',')})`);
  }

  return clauses.join(',');
}

/**
 * Resolve category IDs whose names partially match the search term.
 * @param {string} search
 * @returns {Promise<string[]>}
 */
async function findCategoryIdsMatchingSearch(search) {
  const pattern = escapeIlikePattern(search);
  if (!pattern) return [];

  const { data, error } = await supabase
    .from('categories')
    .select('id')
    .ilike('name', `%${pattern}%`);

  if (error) {
    console.error('productService category search error:', error);
    return [];
  }

  return (data || []).map((row) => row.id).filter(Boolean);
}

export const productService = {
  getProducts: async (params = {}) => {
    try {
      let query = supabase
        .from('products')
        .select(PRODUCT_SELECT, { count: 'exact' });

      const searchTerm = typeof params.search === 'string' ? params.search.trim() : '';
      if (searchTerm) {
        const matchedCategoryIds = await findCategoryIdsMatchingSearch(searchTerm);
        const orFilter = buildProductSearchOrFilter(searchTerm, matchedCategoryIds);
        if (orFilter) {
          query = query.or(orFilter);
        }
      }

      if (params.category) query = query.eq('category_id', params.category);
      if (params.minPrice) query = query.gte('price', Number(params.minPrice));
      if (params.maxPrice) query = query.lte('price', Number(params.maxPrice));
      if (params.inStock) query = query.gt('stock', 0);
      if (params.featured === true || params.featured === 'true') {
        query = query.eq('featured', true);
      }
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
        return { data: { data: [], total: 0, pages: 1 }, error };
      }
      const total = count ?? (Array.isArray(data) ? data.length : 0);
      const limit = Number(params.limit) || total || 1;
      const pages = Math.max(1, Math.ceil(total / limit));
      return { data: { data: Array.isArray(data) ? data : [], total, pages }, error: null };
    } catch (err) {
      console.error('productService.getProducts exception:', err);
      return { data: { data: [], total: 0, pages: 1 }, error: err };
    }
  },

  getProductById: async (id) => {
    try {
      const { data, error } = await supabase.from('products').select(PRODUCT_SELECT).eq('id', id).maybeSingle();
      if (error) {
        console.error('productService.getProductById error:', error);
        return { data: { data: null }, error };
      }
      return { data: { data }, error: null };
    } catch (err) {
      console.error('productService.getProductById exception:', err);
      return { data: { data: null }, error: err };
    }
  },

  /** Resolve by UUID (legacy bookmarks) or exact slug. */
  getProduct: async (idOrSlug) => {
    try {
      if (!idOrSlug) return { data: { data: null }, error: null };

      let query = supabase.from('products').select(PRODUCT_SELECT);
      if (isUuid(idOrSlug)) {
        query = query.eq('id', idOrSlug);
      } else {
        query = query.eq('slug', idOrSlug);
      }
      const { data, error } = await query.maybeSingle();
      if (error) {
        console.error('productService.getProduct error:', error);
        return { data: { data: null }, error };
      }
      return { data: { data }, error: null };
    } catch (err) {
      console.error('productService.getProduct exception:', err);
      return { data: { data: null }, error: err };
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
