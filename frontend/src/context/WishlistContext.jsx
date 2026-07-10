import { createContext, useContext, useState, useEffect, useCallback } from 'react';
import { wishlistService } from '@/services/wishlistService';
import { useAuth } from './AuthContext';
import { supabase } from '@/lib/supabaseClient';

const WishlistContext = createContext(null);

export const WishlistProvider = ({ children }) => {
  const { user } = useAuth();
  const [wishlist, setWishlist] = useState({ products: [] });

  const fetchWishlist = useCallback(async () => {
    if (!user?.id) {
      setWishlist({ products: [] });
      return;
    }
    const { data, error } = await wishlistService.getWishlist(user.id);
    if (!error) setWishlist({ products: Array.isArray(data?.products) ? data.products : [] });
  }, [user?.id]);

  useEffect(() => {
    fetchWishlist();
    const channel = supabase.channel('wishlist').on('postgres_changes', { event: '*', schema: 'public', table: 'wishlist' }, () => fetchWishlist()).subscribe();
    return () => supabase.removeChannel(channel);
  }, [fetchWishlist]);

  const toggleWishlist = async (productId) => {
    if (!user?.id) return;
    const inList = (wishlist.products || []).some((p) => (p.id || p.product_id || p._id) === productId);
    if (inList) {
      await wishlistService.removeFromWishlist(user.id, productId);
    } else {
      await wishlistService.addToWishlist(user.id, productId);
    }
    await fetchWishlist();
  };

  const isWishlisted = (productId) => (wishlist.products || []).some((p) => (p.id || p.product_id || p._id) === productId);

  return (
    <WishlistContext.Provider value={{ wishlist, toggleWishlist, isWishlisted, fetchWishlist }}>
      {children}
    </WishlistContext.Provider>
  );
};

export const useWishlist = () => {
  const ctx = useContext(WishlistContext);
  if (!ctx) throw new Error('useWishlist must be used inside WishlistProvider');
  return ctx;
};
