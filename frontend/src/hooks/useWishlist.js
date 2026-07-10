import { useEffect, useState } from 'react';
import { wishlistService } from '@/services/wishlistService';
import { useAuth } from '@/context/AuthContext';
import { supabase } from '@/lib/supabaseClient';

export function useWishlist() {
  const { user } = useAuth();
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const refetch = async () => {
    if (!user?.id) {
      setProducts([]);
      setLoading(false);
      return;
    }
    setLoading(true);
    try {
      const { data, error: wishlistError } = await wishlistService.getWishlist(user.id);
      if (wishlistError) throw wishlistError;
      setProducts(Array.isArray(data?.products) ? data.products : []);
      setError(null);
    } catch (err) {
      console.error('useWishlist fetch error:', err);
      setError(err);
      setProducts([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    refetch();

    const channel = supabase.channel('wishlist').on('postgres_changes', { event: '*', schema: 'public', table: 'wishlist' }, () => refetch()).subscribe();

    return () => supabase.removeChannel(channel);
  }, [user?.id]);

  return { data: products, products, loading, error, refetch };
}
