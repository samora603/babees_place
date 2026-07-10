import { useState } from "react";
import { Link } from "react-router-dom";
import { useCart } from "@/context/CartContext";
import { supabase } from "@/lib/supabaseClient";
import { orderService } from "@/services/orderService";
import { formatCurrency } from "@/utils/helpers";
import toast from "react-hot-toast";
import { useNavigate } from "react-router-dom";
import { GiBee } from "react-icons/gi";
import Button from "@/components/ui/Button";

export default function Checkout() {
  const { cart, clearCart, subtotal, reloadCart, getItemPrice, getItemImage, loading: cartLoading } = useCart();
  const navigate = useNavigate();
  const [submitting, setSubmitting] = useState(false);

  const handleCheckout = async () => {
    setSubmitting(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();

      if (!user) {
        toast.error("Please login first");
        return;
      }

      if (!cart.length) {
        toast.error("Cart is empty");
        return;
      }

      let orderId;

      try {
        const { order } = await orderService.placeOrder(user.id);
        orderId = order.id;
      } catch (rpcError) {
        console.warn("place_order RPC failed, using client fallback:", rpcError);
        const { order } = await orderService.createOrderFromCart(user.id, cart);
        orderId = order.id;
        await clearCart();
      }

      await reloadCart();
      toast.success("Order placed successfully!");
      navigate(`/orders/${orderId}`);
    } catch (err) {
      console.error(err);
      toast.error(err.message || "Checkout failed");
    } finally {
      setSubmitting(false);
    }
  };

  if (cartLoading) {
    return (
      <div className="bg-[#0B0B0B] min-h-screen flex items-center justify-center text-slate-400">
        Loading checkout...
      </div>
    );
  }

  if (!cart.length) {
    return (
      <div className="bg-[#0B0B0B] min-h-[70vh] flex flex-col items-center justify-center p-6 text-center">
        <h2 className="font-display font-bold text-2xl text-white mb-4">Nothing to checkout</h2>
        <p className="text-slate-400 mb-6">Your cart is empty.</p>
        <Link to="/shop" className="btn-primary">Browse Collection</Link>
      </div>
    );
  }

  return (
    <div className="bg-[#0B0B0B] min-h-screen text-slate-200 py-12">
      <div className="section-container max-w-4xl">
        <div className="flex items-center gap-4 mb-10 pb-4 border-b border-brand-500/20">
          <GiBee className="text-brand-500 text-4xl opacity-80" />
          <h1 className="font-display font-bold text-4xl text-white uppercase tracking-wide">Secure Checkout</h1>
        </div>

        <div className="grid lg:grid-cols-3 gap-10">
          <div className="lg:col-span-2 space-y-4">
            <h2 className="font-display font-semibold text-lg text-white uppercase tracking-widest">Order Review</h2>
            {cart.map((item) => {
              const product = item.product || {};
              const price = getItemPrice(item);
              const image = getItemImage(item);
              return (
                <div key={item.id} className="p-4 rounded-2xl bg-[#111] border border-brand-500/10 flex gap-4">
                  <img src={image} alt={product.name} className="w-20 h-20 object-cover rounded-xl border border-brand-500/20" />
                  <div className="flex-1">
                    <p className="font-medium text-white">{product.name}</p>
                    <p className="text-sm text-slate-400">Qty: {item.quantity}</p>
                  </div>
                  <p className="font-display font-bold text-brand-400">{formatCurrency(price * item.quantity)}</p>
                </div>
              );
            })}
          </div>

          <div className="lg:col-span-1">
            <div className="bg-[#111] p-8 rounded-2xl border border-brand-500/20 shadow-[0_10px_40px_rgba(0,0,0,0.5)] sticky top-28">
              <h2 className="font-display font-semibold text-xl text-white uppercase tracking-widest mb-6 pb-4 border-b border-brand-500/20">
                Summary
              </h2>
              <div className="space-y-3 mb-6 text-sm">
                <div className="flex justify-between">
                  <span className="text-slate-400">Subtotal</span>
                  <span className="text-white">{formatCurrency(subtotal)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-slate-400">Delivery</span>
                  <span className="text-brand-500 italic">Free</span>
                </div>
              </div>
              <div className="border-t border-brand-500/20 pt-4 mb-8 flex justify-between items-end">
                <span className="text-sm uppercase tracking-widest text-slate-400">Total</span>
                <span className="font-display font-bold text-3xl text-brand-400">{formatCurrency(subtotal)}</span>
              </div>
              <Button onClick={handleCheckout} loading={submitting} className="w-full py-4 uppercase tracking-widest">
                Place Order
              </Button>
              <Link to="/cart" className="block text-center text-sm text-slate-400 hover:text-brand-400 mt-4">
                Back to cart
              </Link>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
