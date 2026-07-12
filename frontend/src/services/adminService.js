import { supabase } from '@/lib/supabaseClient';
import { LOW_STOCK_THRESHOLD } from '@/constants/inventory';

async function deleteProductStorage(productId) {
    try {
        const prefix = `products/${productId}`;
        const { data: listed, error: listError } = await supabase.storage
            .from('products')
            .list(`products/${productId}`);
        if (listError) {
            return { error: listError };
        }
        const paths = (listed || []).map((f) => `${prefix}/${f.name}`);
        if (paths.length === 0) return { error: null };
        const { error: removeError } = await supabase.storage.from('products').remove(paths);
        if (removeError) return { error: removeError };
        return { error: null };
    } catch (error) {
        return { error };
    }
}

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
            delivery_type,
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

        if (status === 'cancelled') {
            const { error } = await supabase.rpc('cancel_order', { p_order_id: id });
            if (error) return { data: { data: null, error } };
            if (note) {
                const { data, error: noteErr } = await supabase
                    .from('orders')
                    .update({ note })
                    .eq('id', id)
                    .select()
                    .single();
                return { data: { data, error: noteErr } };
            }
            const { data } = await supabase.from('orders').select('*').eq('id', id).single();
            return { data: { data, error: null } };
        }

        const { error } = await supabase.rpc('update_order_status', {
            p_order_id: id,
            p_status: status,
            p_note: note ?? null,
        });
        if (error) return { data: { data: null, error } };
        const { data, error: fetchErr } = await supabase.from('orders').select('*').eq('id', id).single();
        return { data: { data, error: fetchErr } };
    },

    updateOrderPaymentStatus: async (id, body) => {
        const { paymentStatus, note } = body;
        const { error } = await supabase.rpc('update_order_payment_status', {
            p_order_id: id,
            p_payment_status: paymentStatus,
            p_note: note ?? null,
        });
        if (error) return { data: { data: null, error } };
        const { data, error: fetchErr } = await supabase.from('orders').select('*').eq('id', id).single();
        return { data: { data, error: fetchErr } };
    },

    getOrder: async (id) => {
        const { data, error } = await supabase
            .from('orders')
            .select(`
                *,
                order_items (*),
                profiles (full_name, email, phone),
                pickup_locations (id, name, building, description, operating_hours)
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
        const storageResult = await deleteProductStorage(id);
        if (storageResult.error) {
            return { data: { data: null, error: storageResult.error } };
        }
        const { data, error } = await supabase.from('products').delete().eq('id', id).select();
        return { data: { data, error } };
    },
    deleteProductStorage,
    deleteStoragePaths: async (paths = []) => {
        if (!paths.length) return { error: null };
        try {
            const { error } = await supabase.storage.from('products').remove(paths);
            return { error: error || null };
        } catch (error) {
            return { error };
        }
    },
    uploadImages: async (id, formData) => {
        try {
            const files = formData.getAll('images');
            const uploaded = [];
            for (const file of files) {
                const ext = file.name.includes('.') ? file.name.split('.').pop() : 'jpg';
                const safeName = `${crypto.randomUUID()}.${ext}`;
                const path = `products/${id}/${safeName}`;
                const { error } = await supabase.storage.from('products').upload(path, file, {
                    upsert: false,
                    contentType: file.type,
                });
                if (error) throw error;
                const { data: { publicUrl } } = supabase.storage.from('products').getPublicUrl(path);
                uploaded.push({ path, url: publicUrl });
            }
            return { data: { data: uploaded, error: null } };
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

    // Pickup Locations
    getPickupLocations: async (includeInactive = true) => {
        let query = supabase
            .from('pickup_locations')
            .select('*')
            .order('name', { ascending: true });
        if (!includeInactive) query = query.eq('is_active', true);
        const { data, error } = await query;
        if (error) return { data: { data: [], error } };
        const mapped = (data || []).map((loc) => ({
            _id: loc.id,
            id: loc.id,
            name: loc.name,
            building: loc.building,
            description: loc.description,
            operatingHours: loc.operating_hours,
            isActive: loc.is_active,
        }));
        return { data: { data: mapped, error: null } };
    },
    addPickupLocation: async (body) => {
        const payload = {
            name: body.name?.trim(),
            building: body.building?.trim() || '',
            description: body.description?.trim() || null,
            operating_hours: body.operatingHours || body.operating_hours || {},
            is_active: body.isActive !== false,
        };
        const { data, error } = await supabase.from('pickup_locations').insert(payload).select().single();
        return { data: { data, error } };
    },
    updatePickupLocation: async (id, body) => {
        const payload = {};
        if (body.name !== undefined) payload.name = body.name.trim();
        if (body.building !== undefined) payload.building = body.building.trim();
        if (body.description !== undefined) payload.description = body.description?.trim() || null;
        if (body.operatingHours !== undefined) payload.operating_hours = body.operatingHours;
        if (body.isActive !== undefined) payload.is_active = body.isActive;
        payload.updated_at = new Date().toISOString();
        const { data, error } = await supabase.from('pickup_locations').update(payload).eq('id', id).select().single();
        return { data: { data, error } };
    },
    deletePickupLocation: async (id) => {
        const { data, error } = await supabase.from('pickup_locations').delete().eq('id', id).select();
        return { data: { data, error } };
    },
};