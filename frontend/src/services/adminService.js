import { supabase } from '@/lib/supabaseClient';
import { LOW_STOCK_THRESHOLD } from '@/constants/inventory';

// Standard error returned by deferred (Phase 2) features whose backing tables
// are intentionally absent from the approved canonical schema.
const FEATURE_DEFERRED = { message: 'This feature is not available yet.' };

// Admin operations implemented against Supabase. These return objects shaped
// similarly to the previous API (wrapped in `{ data: ... }`) where callers
// expect that. For more advanced behavior (uploads, complex stats) the
// frontend should call Edge Functions; here we implement simple DB operations.
export const adminService = {
  getStats: async () => {
    try {
      const [
        usersResult,
        productsResult,
        ordersResult,
        revenueResult,
        lowStockResult,
      ] = await Promise.all([
        supabase
          .from("profiles")
          .select("*", { count: "exact", head: true }),

        supabase
          .from("products")
          .select("*", { count: "exact", head: true }),

        supabase
          .from("orders")
          .select("*", { count: "exact", head: true }),

        supabase
          .from("orders")
          .select("total, created_at"),

        supabase
          .from("products")
          .select("id")
          .gt("stock", 0)
          .lt("stock", LOW_STOCK_THRESHOLD),
      ]);

      const orders = revenueResult.data || [];

      const totalRevenue = orders.reduce(
        (sum, order) => sum + Number(order.total || 0),
        0
      );

      // last 7 days revenue
      const revenueByDay = [];

      for (let i = 6; i >= 0; i--) {
        const day = new Date();
        day.setDate(day.getDate() - i);

        const key = day.toISOString().slice(0, 10);

        const revenue = orders
          .filter(
            (o) =>
              o.created_at &&
              o.created_at.slice(0, 10) === key
          )
          .reduce(
            (sum, o) => sum + Number(o.total || 0),
            0
          );

        revenueByDay.push({
          _id: key,
          revenue,
        });
      }

      return {
        data: {
          data: {
            totalRevenue,

            totalOrders: ordersResult.count || 0,

            totalProducts: productsResult.count || 0,

            totalUsers: usersResult.count || 0,

            lowStockCount:
              lowStockResult.data?.length || 0,

            revenueByDay,
          },
        },
      };
    } catch (error) {
      console.error(error);

      return {
        data: {
          data: {
            totalRevenue: 0,
            totalOrders: 0,
            totalProducts: 0,
            totalUsers: 0,
            lowStockCount: 0,
            revenueByDay: [],
          },
        },
      };
    }
  },

    getOrders: async (params = {}) => {
    const limit = params.limit || 20;
    const page = params.page || 1;
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    let query = supabase
        .from('orders')
        .select(`
            id,
            status,
            total,
            payment_status,
            created_at,
            user_id,
            note,
            profiles (full_name, email, phone)
        `, { count: 'exact' })
        .order('created_at', { ascending: false })
        .range(from, to);

    if (params.status) {
        query = query.eq('status', params.status);
    }

    const { data, error, count } = await query;

    if (error) {
        console.error("getOrders error:", error);
        return { data: { data: [], total: 0 } };
    }

    return {
        data: {
            data: data || [],
            total: count || 0
        }
    };
    },

    updateOrderStatus: async (id, body) => {
        const { status, note } = body;
        const update = {};
        if (status !== undefined) update.status = status;
        if (note !== undefined) update.note = note;
        // orders.updated_at is maintained by the set_updated_at trigger (migration 003).

        const { data, error } = await supabase.from('orders').update(update).eq('id', id).select().single();
        return { data: { data, error } };
    },

    getOrder: async (id) => {
        const { data, error } = await supabase
            .from('orders')
            .select(`
                *,
                order_items (*),
                profiles (full_name, email, phone)
            `)
            .eq('id', id)
            .maybeSingle();

        return { data: { data, error } };
    },

    getUsers: async (params = {}) => {
        const limit = params.limit || 20;
        const page = params.page || 1;
        const from = (page - 1) * limit;
        const to = from + limit - 1;
        const { data, count } = await supabase.from('profiles').select('*', { count: 'exact' }).range(from, to);
        return { data: { data: data || [], total: count || 0 } };
    },

    updateUserRole: async (id, role) => {
        const { data, error } = await supabase.from('profiles').update({ role }).eq('id', id).select().single();
        return { data: { data, error } };
    },

    // Products (admin)
    createProduct: async (body) => {
        const { data, error } = await supabase.from('products').insert(body).select().single();
        return { data: { data, error } };
    },
    updateProduct: async (id, body) => {
        const { data, error } = await supabase.from('products').update(body).eq('id', id).select().single();
        return { data: { data, error } };
    },
    deleteProduct: async (id) => {
        const { data, error } = await supabase.from('products').delete().eq('id', id).select();
        return { data: { data, error } };
    },
    uploadImages: async (id, formData) => {
        // Attempt to upload images to Supabase Storage 'products' bucket.
        // Caller should provide formData with files; here we return an error if storage not configured.
        try {
            const files = formData.getAll('images');
            const uploaded = [];
            for (const file of files) {
                const path = `products/${id}/${file.name}`;
                const { error } = await supabase.storage.from('products').upload(path, file, { upsert: true });
                if (error) throw error;
                const { data: { publicUrl } } = supabase.storage.from('products').getPublicUrl(path);
                uploaded.push({ path, url: publicUrl });
            }
            return { data: { data: uploaded } };
        } catch (error) {
            return { data: { data: null, error } };
        }
    },

    // Categories
    createCategory: async (body) => {
        const { data, error } = await supabase.from('categories').insert(body).select().single();
        return { data: { data, error } };
    },
    updateCategory: async (id, body) => {
        const { data, error } = await supabase.from('categories').update(body).eq('id', id).select().single();
        return { data: { data, error } };
    },
    deleteCategory: async (id) => {
        const { data, error } = await supabase.from('categories').delete().eq('id', id).select();
        return { data: { data, error } };
    },

    // Inventory
    getInventory: async ({ stockStatus, limit, search } = {}) => {
        let query = supabase
            .from('products')
            .select('id, name, stock, price, category, images, is_active, categories (id, name)')
            .order('name', { ascending: true });

        if (stockStatus === 'out') {
            query = query.lte('stock', 0);
        } else if (stockStatus === 'low') {
            query = query.gt('stock', 0).lt('stock', LOW_STOCK_THRESHOLD);
        } else if (stockStatus === 'in') {
            query = query.gte('stock', LOW_STOCK_THRESHOLD);
        }

        if (search) {
            query = query.ilike('name', `%${search}%`);
        }
        if (limit) {
            query = query.limit(Number(limit));
        }

        const { data, error } = await query;
        return { data: { data: data || [], error } };
    },
    getLowStock: async () => {
        const { data, error } = await supabase
            .from('products')
            .select('id, name, stock, price, category, images, is_active, categories (id, name)')
            .gt('stock', 0)
            .lt('stock', LOW_STOCK_THRESHOLD)
            .order('stock', { ascending: true });
        return { data: { data: data || [], error } };
    },
    updateStock: async (productId, body) => {
        const stock = Number(body?.stock);
        if (Number.isNaN(stock) || stock < 0) {
            return { data: { data: null }, error: { message: 'Stock must be a non-negative number' } };
        }
        const { data, error } = await supabase
            .from('products')
            .update({ stock })
            .eq('id', productId)
            .select()
            .single();
        return { data: { data, error } };
    },

    // Pickup Locations — DEFERRED (Phase 2).
    // The `pickup_locations` table is NOT part of the approved canonical schema
    // (see Reconciliation_Decision_Log.md / Final_Canonical_Schema.md). These
    // methods are guarded so the admin UI degrades gracefully instead of issuing
    // queries against a non-existent table. Wire to a real table when designed.
    getPickupLocations: async () => ({ data: { data: [], error: null } }),
    addPickupLocation: async () => ({ data: { data: null, error: FEATURE_DEFERRED } }),
    updatePickupLocation: async () => ({ data: { data: null, error: FEATURE_DEFERRED } }),
    deletePickupLocation: async () => ({ data: { data: null, error: FEATURE_DEFERRED } }),
};