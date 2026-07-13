import { Link, useLocation } from 'react-router-dom';
import { FiShoppingCart } from 'react-icons/fi';
import { useCart } from '@/context/CartContext';
import { useAuth } from '@/context/AuthContext';

const HIDDEN_PATHS = ['/cart', '/checkout', '/login', '/register'];

/**
 * Persistent cart affordance with live count — complements the navbar badge
 * so Collection / Product Detail always show feedback after Add to Cart.
 */
export default function FloatingCartButton() {
  const { itemCount } = useCart();
  const { isAuthenticated } = useAuth();
  const { pathname } = useLocation();

  if (!isAuthenticated || itemCount <= 0) return null;
  if (HIDDEN_PATHS.some((p) => pathname === p || pathname.startsWith(`${p}/`))) {
    return null;
  }
  if (pathname.startsWith('/admin')) return null;

  return (
    <Link
      to="/cart"
      aria-label={`View cart, ${itemCount} items`}
      className="fixed bottom-6 right-6 z-40 flex items-center gap-2 rounded-full bg-brand-500 text-black pl-4 pr-5 py-3 shadow-[0_8px_30px_rgba(212,175,55,0.45)] hover:bg-brand-400 transition-all hover:scale-105"
    >
      <span className="relative">
        <FiShoppingCart size={20} />
        <span className="absolute -top-2 -right-2 min-w-[1.1rem] h-[1.1rem] px-0.5 bg-black text-brand-400 text-[10px] font-bold rounded-full flex items-center justify-center">
          {itemCount > 99 ? '99+' : itemCount}
        </span>
      </span>
      <span className="text-sm font-semibold tracking-wide hidden sm:inline">Cart</span>
    </Link>
  );
}
