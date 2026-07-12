import { Link } from 'react-router-dom';
import { FiHeart, FiShoppingCart, FiStar } from 'react-icons/fi';
import { formatCurrency, getPrimaryImage, discountPercent } from '@/utils/helpers';
import { useCart } from '@/context/CartContext';
import { useWishlist } from '@/context/WishlistContext';
import { useAuth } from '@/context/AuthContext';
import toast from 'react-hot-toast';

export default function ProductCard({ product }) {
  const { addToCart } = useCart();
  const { toggleWishlist, isWishlisted } = useWishlist();
  const { isAuthenticated } = useAuth();

  const productId = product.id || product._id || product.product_id;
  const image = getPrimaryImage(product.images) || product.image_url || '/placeholder.png';
  const wishlisted = isWishlisted(productId);
  const hasDiscount = product.discount_price && product.discount_price < product.price;
  const discount = hasDiscount ? discountPercent(product.price, product.discount_price) : 0;

  const handleAddToCart = async (e) => {
    e.preventDefault();
    if (!isAuthenticated) { toast.error('Please sign in to add to cart'); return; }
    if (product.stock === 0) { toast.error('Out of stock'); return; }
    // Construct minimal product shape required by CartContext
    const cartItem = {
      id: productId,
      name: product.name || product.title || '',
      price: product.discount_price ?? product.price ?? 0,
      image_url: getPrimaryImage(product.images || []),
    };
    addToCart(cartItem);
  };

  const handleWishlist = async (e) => {
    e.preventDefault();
    if (!isAuthenticated) { toast.error('Please sign in to save items'); return; }
    await toggleWishlist(productId);
  };

  return (
    <Link
      to={`/shop/${product.slug || productId}`}
      className="card group flex flex-col overflow-hidden hover:border-brand-500/40 transition-all duration-300 hover:shadow-[0_4px_30px_rgba(212,175,55,0.15)] bg-[#111]"
    >
      {/* Image */}
      <div className="relative aspect-square overflow-hidden bg-[#0a0a0a]">
        <img
          src={image}
          alt={product.name}
          loading="lazy"
          decoding="async"
          className="w-full h-full object-cover group-hover:scale-110 transition-transform duration-700 ease-in-out opacity-90 group-hover:opacity-100 mix-blend-luminosity hover:mix-blend-normal"
        />
        {/* Transparent dark gradient overlay for image baseline */}
        <div className="absolute inset-0 bg-gradient-to-t from-[#111] via-transparent to-transparent opacity-80 pointer-events-none"></div>

        {/* Discount badge */}
        {hasDiscount && (
          <span className="absolute top-3 left-3 bg-brand-500 text-black text-xs font-bold px-3 py-1 rounded-sm shadow-[0_0_10px_rgba(212,175,55,0.4)] tracking-wider">
            -{discount}%
          </span>
        )}
        {product.stock === 0 && (
          <span className="absolute top-3 left-3 bg-[#111] border border-slate-600 text-slate-300 text-xs font-semibold px-3 py-1 rounded-sm tracking-wider uppercase">Out of Stock</span>
        )}

        {/* Wishlist btn */}
        <button
          onClick={handleWishlist}
          className={`absolute top-3 right-3 w-9 h-9 border rounded-full flex items-center justify-center transition-all duration-300 backdrop-blur-md ${
            wishlisted
              ? 'bg-[#111] border-red-500/50 text-red-500 shadow-[0_0_10px_rgba(239,68,68,0.3)]'
              : 'bg-white/5 border-white/10 text-white hover:border-brand-500/50 hover:text-brand-500'
          }`}
          aria-label={wishlisted ? 'Remove from wishlist' : 'Add to wishlist'}
        >
          <FiHeart size={16} className={wishlisted ? 'fill-current' : ''} />
        </button>
      </div>

      {/* Info */}
      <div className="p-5 flex flex-col flex-1 gap-2 relative z-10">
        <p className="text-[10px] uppercase tracking-widest text-brand-500 font-semibold">{product.categories?.name || product.category}</p>
        <h3 className="text-sm font-display font-medium text-white line-clamp-2 leading-relaxed tracking-wide group-hover:text-brand-100 transition-colors">{product.name}</h3>

        {/* Rating */}
        {product.reviewCount > 0 && (
          <div className="flex items-center gap-1.5 mt-1">
            <FiStar size={12} className="text-brand-500 fill-current drop-shadow-[0_0_3px_rgba(212,175,55,0.8)]" />
            <span className="text-[11px] text-slate-400 tracking-wider pt-0.5">{product.rating} ({product.reviewCount})</span>
          </div>
        )}

        <div className="flex items-end justify-between mt-auto pt-4 border-t border-brand-500/10">
          <div>
            {hasDiscount ? (
              <div className="flex flex-col gap-0.5">
                <span className="font-display font-bold text-lg text-brand-400">{formatCurrency(product.discount_price)}</span>
                <span className="text-xs text-slate-500 line-through tracking-wider">{formatCurrency(product.price)}</span>
              </div>
            ) : (
              <span className="font-display font-bold text-lg text-white">{formatCurrency(product.price)}</span>
            )}
          </div>

          <button
            onClick={handleAddToCart}
            disabled={product.stock === 0}
            className="w-10 h-10 rounded border border-brand-500/30 bg-brand-500/5 text-brand-500 hover:bg-brand-500 hover:text-black flex items-center justify-center transition-all duration-300 disabled:opacity-30 shadow-[0_0_10px_rgba(212,175,55,0.05)] hover:shadow-[0_0_15px_rgba(212,175,55,0.4)]"
            aria-label="Add to cart"
          >
            <FiShoppingCart size={18} className={`${product.stock > 0 ? 'group-hover/btn:scale-110' : ''} transition-transform`} />
          </button>
        </div>
      </div>
    </Link>
  );
}
