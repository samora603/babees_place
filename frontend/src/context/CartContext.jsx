import { createContext, useContext, useEffect, useState, useMemo, useCallback, useRef } from "react";
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
  const [error, setError] = useState(null);
  const loadSeqRef = useRef(0);

  const loadCartForUser = useCallback(async (userId, { showLoading = true } = {}) => {
    const seq = ++loadSeqRef.current;

    if (showLoading) setLoading(true);

    if (!userId) {
      if (seq !== loadSeqRef.current) return;
      setCart([]);
      setError(null);
      setLoading(false);
      return;
    }

    const { data, error: fetchError } = await cartService.getCart(userId);

    if (seq !== loadSeqRef.current) return;

    if (fetchError) {
      console.error("CartContext load error:", fetchError);
      setError(fetchError);
      // Keep previous cart on soft reload failures; clear only on initial load
      if (showLoading) setCart([]);
      setLoading(false);
      return;
    }

    setCart(data.items || []);
    setError(null);
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
        loadSeqRef.current += 1;
        setCart([]);
        setError(null);
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
    await loadCartForUser(user?.id, { showLoading: false });
  }, [loadCartForUser]);

  const addToCart = async (product, quantity = 1) => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      toast.error("Please sign in to add to cart");
      return { ok: false };
    }

    const productId = product?.id || product?._id || product?.product_id;
    if (!productId) {
      toast.error("Invalid product");
      return { ok: false };
    }

    const { error: addError } = await cartService.addToCart(
      user.id,
      productId,
      quantity
    );

    if (addError) {
      toast.error(addError.message || "Failed to add item");
      return { ok: false };
    }

    toast.success("Added to cart");
    await loadCartForUser(user.id, { showLoading: false });
    return { ok: true };
  };

  const removeFromCart = async (cartId) => {
    const { error: removeError } = await cartService.removeFromCart(cartId);

    if (removeError) {
      toast.error("Failed to remove item");
      return { ok: false };
    }

    toast.success("Removed from cart");
    await loadCart();
    return { ok: true };
  };

  const setQuantity = async (cartId, quantity) => {
    const { error: qtyError } = await cartService.updateQuantity(cartId, quantity);

    if (qtyError) {
      toast.error(qtyError.message || "Failed to update quantity");
      return { ok: false };
    }

    await loadCart();
    return { ok: true };
  };

  const clearCart = async () => {
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return { ok: false };

    const { error: clearError } = await cartService.clearCart(user.id);
    if (clearError) {
      toast.error("Failed to clear cart");
      return { ok: false };
    }

    setCart([]);
    return { ok: true };
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
        error,
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
