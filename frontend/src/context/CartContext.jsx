import { createContext, useContext, useEffect, useState, useMemo, useCallback } from "react";
import toast from "react-hot-toast";
import { cartService } from "@/services/cartService";
import { supabase } from "@/lib/supabaseClient";
import { getPrimaryImage } from "@/utils/helpers";

const CartContext = createContext(null);

const getItemPrice = (item) => {
  const product = item?.product;
  if (!product) return 0;
  return Number(product.discount_price ?? product.price ?? 0);
};

export const CartProvider = ({ children }) => {
  const [cart, setCart] = useState([]);
  const [loading, setLoading] = useState(true);

  const loadCartForUser = useCallback(async (userId) => {
    setLoading(true);

    if (!userId) {
      setCart([]);
      setLoading(false);
      return;
    }

    const { data } = await cartService.getCart(userId);
    setCart(data.items || []);
    setLoading(false);
  }, []);

  useEffect(() => {
    let mounted = true;

    const bootstrap = async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!mounted) return;
      await loadCartForUser(user?.id);
    };

    bootstrap();

    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      if (!mounted) return;

      if (!session?.user) {
        setCart([]);
        setLoading(false);
        return;
      }

      const userId = session.user.id;
      queueMicrotask(() => {
        if (!mounted) return;
        void loadCartForUser(userId);
      });
    });

    return () => {
      mounted = false;
      subscription.unsubscribe();
    };
  }, [loadCartForUser]);

  const loadCart = useCallback(async () => {
    const { data: { user } } = await supabase.auth.getUser();
    await loadCartForUser(user?.id);
  }, [loadCartForUser]);

  const addToCart = async (product, quantity = 1) => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return toast.error("Login required");

    const { error } = await cartService.addToCart(
      user.id,
      product.id,
      quantity
    );

    if (error) return toast.error(error.message || "Failed to add item");

    toast.success("Added to cart");
    await loadCartForUser(user.id);
  };

  const removeFromCart = async (cartId) => {
    const { error } = await cartService.removeFromCart(cartId);

    if (error) return toast.error("Failed to remove item");

    toast.success("Removed from cart");
    await loadCart();
  };

  const setQuantity = async (cartId, quantity) => {
    const { error } = await cartService.updateQuantity(cartId, quantity);

    if (error) return toast.error(error.message || "Failed to update quantity");

    await loadCart();
  };

  const clearCart = async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return;

    await cartService.clearCart(user.id);
    setCart([]);
  };

  const itemCount = useMemo(
    () => cart.reduce((s, it) => s + Number(it.quantity || 0), 0),
    [cart]
  );

  const subtotal = useMemo(
    () =>
      cart.reduce(
        (s, it) => s + getItemPrice(it) * Number(it.quantity || 0),
        0
      ),
    [cart]
  );

  return (
    <CartContext.Provider
      value={{
        cart,
        loading,
        addToCart,
        setQuantity,
        removeFromCart,
        clearCart,
        itemCount,
        subtotal,
        reloadCart: loadCart,
        getItemPrice,
        getItemImage: (item) => {
          const product = item?.product;
          if (!product) return '/placeholder.png';
          return getPrimaryImage(product.images || []) || product.image_url || '/placeholder.png';
        },
      }}
    >
      {children}
    </CartContext.Provider>
  );
};

export const useCart = () => {
  const ctx = useContext(CartContext);
  if (!ctx) throw new Error("useCart must be used inside CartProvider");
  return ctx;
};
