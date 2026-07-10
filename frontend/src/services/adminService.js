import { supabase } from '@/lib/supabaseClient';

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
          .select("total_amount, created_at"),

        supabase
          .from("products")
          .select("id")
          .lt("stock", 5),
      ]);

      const orders = revenueResult.data || [];

      const totalRevenue = orders.reduce(
        (sum, order) => sum + Number(order.total_amount || order.total_price || 0),
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
            (sum, o) => sum + Number(o.total_amount || o.total_price || 0),
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
            total_amount,
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
        update.updated_at = new Date().toISOString();

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
        const { data, error, count } = await supabase.from('profiles').select('*', { count: 'exact' }).range(from, to);
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
                const { data, error } = await supabase.storage.from('products').upload(path, file, { upsert: true });
                if (error) throw error;
                const { publicURL } = supabase.storage.from('products').getPublicUrl(path);
                uploaded.push({ path, url: publicURL });
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
    getInventory: async (params = {}) => {
        // For simplicity, inventory is product stock
        const { data, error } = await supabase.from('products').select('id,name,stock');
        return { data: { data: data || [], error } };
    },
    getLowStock: async () => {
        const { data, error } = await supabase.from('products').select('id,name,stock').lt('stock', 5);
        return { data: { data: data || [], error } };
    },
    updateStock: async (productId, body) => {
        const { data, error } = await supabase.from('products').update(body).eq('id', productId).select().single();
        return { data: { data, error } };
    },

    // Pickup Locations
    getPickupLocations: async () => {
        const { data, error } = await supabase.from('pickup_locations').select('*');
        return { data: { data: data || [], error } };
    },
    addPickupLocation: async (body) => {
        const { data, error } = await supabase.from('pickup_locations').insert(body).select().single();
        return { data: { data, error } };
    },
    updatePickupLocation: async (id, body) => {
        const { data, error } = await supabase.from('pickup_locations').update(body).eq('id', id).select().single();
        return { data: { data, error } };
    },
    deletePickupLocation: async (id) => {
        const { data, error } = await supabase.from('pickup_locations').delete().eq('id', id).select();
        return { data: { data, error } };
    },
};