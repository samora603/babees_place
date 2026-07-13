import { Link } from 'react-router-dom';
import { useCart } from '@/context/CartContext';
import { formatCurrency } from '@/utils/helpers';
import Skeleton from '@/components/ui/Skeleton';
import { FiTrash2, FiShoppingBag } from 'react-icons/fi';
import { GiBee } from 'react-icons/gi';
import { isOutOfStock, isLowStock } from '@/constants/inventory';
import CartExpressHint from '@/components/checkout/CartExpressHint';

function cartHasBlockingIssues(items = []) {
  return items.some((item) => {
    const p = item.product || {};
    const stock = p.stock ?? 0;
    return p.is_active === false || isOutOfStock(stock) || Number(item.quantity) > stock;
  });
}

export default function Cart() {
  const { cart, loading, error, subtotal, setQuantity, removeFromCart, getItemPrice, getItemImage, reloadCart } = useCart();
  const items = cart || [];
  const checkoutBlocked = cartHasBlockingIssues(items);

  if (!loading && error && items.length === 0) {
    return (
      <div className="bg-[#0B0B0B] min-h-[70vh] flex flex-col items-center justify-center p-6">
        <div className="relative z-10 flex flex-col items-center bg-[#111] p-12 rounded-3xl border border-red-500/20 shadow-2xl max-w-md w-full text-center">
          <h2 className="font-display font-bold text-2xl text-white mb-3">Could not load cart</h2>
          <p className="text-slate-400 mb-6 text-sm">{error.message || 'Please try again.'}</p>
          <button type="button" onClick={() => reloadCart()} className="btn-primary w-full">
            Retry
          </button>
        </div>
      </div>
    );
  }

  if (!loading && items.length === 0) {
    return (
      <div className="bg-[#0B0B0B] min-h-[70vh] flex flex-col items-center justify-center p-6 relative">
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-96 h-96 bg-brand-500/5 rounded-full blur-[100px] pointer-events-none"></div>
        <div className="relative z-10 flex flex-col items-center bg-[#111] p-12 rounded-3xl border border-brand-500/10 shadow-2xl max-w-md w-full text-center">
          <div className="w-20 h-20 rounded-full bg-brand-500/10 flex items-center justify-center text-brand-500 mb-6 drop-shadow-[0_0_15px_rgba(212,175,55,0.4)]">
             <FiShoppingBag size={32} />
          </div>
          <h2 className="font-display font-bold text-3xl text-white mb-3">Your Cart is Empty</h2>
          <p className="text-slate-400 mb-8 font-light">Select from our exclusive pieces to curate your order.</p>
          <Link to="/shop" className="btn-primary w-full shadow-[0_4px_20px_rgba(212,175,55,0.2)]">Explore Collection</Link>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-[#0B0B0B] min-h-screen text-slate-200 py-12">
      <div className="section-container relative z-10">
        <div className="flex items-center gap-4 mb-10 pb-4 border-b border-brand-500/20">
           <GiBee className="text-brand-500 text-4xl opacity-80" />
           <h1 className="font-display font-bold text-4xl text-white uppercase tracking-wide">Acquisition Cart</h1>
        </div>

        <div className="grid lg:grid-cols-3 gap-10 lg:gap-14">
          <div className="lg:col-span-2 space-y-6">
            {loading ? (
              [...Array(3)].map((_, i) => (
                <div key={i} className="p-5 rounded-2xl bg-[#111] border border-brand-500/10 shadow-md flex gap-5">
                  <Skeleton className="w-28 h-28 shrink-0 rounded-xl" variant="rectangular" />
                  <div className="flex-1 flex flex-col min-w-0 pr-4">
                    <Skeleton className="w-3/4 h-6 mb-2" variant="text" />
                    <Skeleton className="w-1/4 h-4" variant="text" />
                    <div className="flex items-end justify-between mt-auto pt-4 border-t border-brand-500/5">
                      <Skeleton className="w-24 h-6" variant="text" />
                      <Skeleton className="w-20 h-8 rounded-lg" variant="rectangular" />
                    </div>
                  </div>
                </div>
              ))
            ) : (
              items.map((item) => {
                const product = item.product || {};
                const name = product.name || 'Unknown item';
                const price = getItemPrice(item);
                const image = getItemImage(item);
                const productLink = `/shop/${item.product_id}`;
                const unitPrice = price;
                const stock = product.stock ?? 0;
                const inactive = product.is_active === false;
                const atMax = Number(item.quantity) >= stock;
                const overStock = Number(item.quantity) > stock;
                const unavailable = inactive || isOutOfStock(stock);

                const increment = () => {
                  if (unavailable || atMax) return;
                  setQuantity(item.id, Number(item.quantity || 0) + 1);
                };
                const decrement = () => setQuantity(item.id, Number(item.quantity || 0) - 1);
                const handleRemove = () => removeFromCart(item.id);

                return (
                <div key={item.id} className="p-5 rounded-2xl bg-[#111] border border-brand-500/10 hover:border-brand-500/30 transition-all duration-300 shadow-md flex gap-5 group">
                  <Link to={productLink} className="shrink-0 relative overflow-hidden rounded-xl border border-brand-500/20">
                    <img src={image} alt={name} loading="lazy" decoding="async" className="w-28 h-28 object-cover group-hover:scale-110 transition-transform duration-500" />
                  </Link>
                  <div className="flex-1 flex flex-col min-w-0">
                    <div className="flex justify-between items-start gap-4">
                      <div>
                        <Link to={productLink}>
                          <h3 className="font-display font-medium text-lg text-white line-clamp-2 hover:text-brand-400 transition-colors">{name}</h3>
                        </Link>
                        {inactive && (
                          <p className="text-xs text-red-400 mt-1">This item is no longer available</p>
                        )}
                        {!inactive && isOutOfStock(stock) && (
                          <p className="text-xs text-red-400 mt-1">Out of stock — remove to continue</p>
                        )}
                        {!inactive && !isOutOfStock(stock) && isLowStock(stock) && (
                          <p className="text-xs text-orange-400 mt-1">Only {stock} left in stock</p>
                        )}
                        {overStock && !isOutOfStock(stock) && (
                          <p className="text-xs text-orange-400 mt-1">Quantity exceeds available stock ({stock})</p>
                        )}
                      </div>
                      <button onClick={handleRemove} className="w-8 h-8 rounded-full bg-surface-card flex items-center justify-center text-slate-500 hover:text-red-400 hover:bg-red-400/10 transition-colors shrink-0" aria-label="Remove item">
                        <FiTrash2 size={16} />
                      </button>
                    </div>

                    <div className="flex items-end justify-between mt-auto pt-4 border-t border-brand-500/5">
                      <p className="font-display font-bold text-xl text-brand-400">{formatCurrency(price * item.quantity)}</p>
                      <div className="bg-[#0A0A0A] border border-brand-500/20 p-1 rounded-lg flex items-center gap-2">
                        <button onClick={decrement} className="px-3 py-1 bg-surface-card rounded">-</button>
                        <div className="px-3">{item.quantity}</div>
                        <button onClick={increment} disabled={unavailable || atMax} className="px-3 py-1 bg-surface-card rounded disabled:opacity-40">+</button>
                      </div>
                    </div>
                  </div>
                </div>
              );
            })
            )}
          </div>

          <div className="lg:col-span-1">
            <div className="bg-[#111] p-8 rounded-2xl border border-brand-500/20 shadow-[0_10px_40px_rgba(0,0,0,0.5)] h-fit sticky top-28">
              <h2 className="font-display font-semibold text-xl text-white uppercase tracking-widest mb-6 pb-4 border-b border-brand-500/20 flex items-center gap-2">
                 Order Summary
              </h2>
              <div className="space-y-4 mb-6">
                <div className="flex justify-between text-sm">
                  <span className="text-slate-400 tracking-wide">Subtotal</span><span className="text-white font-medium">{formatCurrency(subtotal)}</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-slate-400 tracking-wide">Delivery</span><span className="text-brand-500 italic">Calculated at checkout</span>
                </div>
              </div>
              <div className="border-t border-brand-500/20 pt-6 mb-8 flex justify-between items-end">
                <span className="text-sm uppercase tracking-widest text-slate-400">Total</span>
                <span className="font-display font-bold text-3xl text-brand-400">{formatCurrency(subtotal)}</span>
              </div>
              {checkoutBlocked && (
                <p className="text-xs text-red-400 mb-3">Resolve stock issues above before checkout.</p>
              )}
              {!checkoutBlocked && <CartExpressHint cartValid={!loading && items.length > 0} />}
              <Link
                to="/checkout"
                className={`btn-primary w-full text-center uppercase tracking-widest text-sm shadow-[0_4px_25px_rgba(212,175,55,0.25)] hover:shadow-[0_4px_35px_rgba(212,175,55,0.4)] py-4 ${checkoutBlocked ? 'pointer-events-none opacity-50' : ''}`}
              >
                Secure Checkout
              </Link>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
