import { useEffect, useMemo, useState } from 'react';
import { cartService } from '@/services/cartService';
import { useAuth } from '@/context/AuthContext';
import { supabase } from '@/lib/supabaseClient';

export function useCart() {
  const { user } = useAuth();
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetchCart = async () => {
    if (!user?.id) {
      setItems([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      const { data, error: cartError } = await cartService.getCart(user.id);
      if (cartError) throw cartError;
      setItems(Array.isArray(data?.items) ? data.items : []);
      setError(null);
    } catch (err) {
      console.error('useCart fetch error:', err);
      setError(err);
      setItems([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchCart();

    const channel = supabase.channel('cart').on('postgres_changes', { event: '*', schema: 'public', table: 'cart' }, () => fetchCart()).subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [user?.id]);

  const subtotal = useMemo(() => items.reduce((sum, item) => sum + (Number(item.product?.price || 0) * Number(item.quantity || 1)), 0), [items]);
  const itemCount = useMemo(() => items.reduce((sum, item) => sum + Number(item.quantity || 0), 0), [items]);

  return { data: items, items, subtotal, itemCount, loading, error, refetch: fetchCart };
}
