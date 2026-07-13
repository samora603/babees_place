import { useWishlist } from '@/context/WishlistContext';
import { Link } from 'react-router-dom';
import { FiHeart, FiTrash2 } from 'react-icons/fi';
import { formatCurrency, getPrimaryImage } from '@/utils/helpers';
import { useCart } from '@/context/CartContext';
import ExploreSuggestions from '@/components/recommendations/ExploreSuggestions';

export default function Wishlist() {
  const { wishlist, toggleWishlist } = useWishlist();
  const { addToCart } = useCart();
  const products = wishlist?.products || [];

  return (
    <div className="section-container py-10">
      <h1 className="font-display font-bold text-3xl mb-8">
        My Wishlist ({products.length})
      </h1>
      {products.length === 0 ? (
        <div className="space-y-10">
          <div className="text-center py-10">
            <FiHeart size={48} className="mx-auto text-slate-600 mb-4" />
            <p className="text-slate-400 mb-2">Your wishlist is empty</p>
          </div>
          <ExploreSuggestions
            title="Ideas for your wishlist"
            message="Save products you love — meanwhile, explore these picks."
            ctaLabel="Browse Products"
          />
        </div>
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          {products.map((product) => {
            const id = product.id || product._id || product.product_id;
            const image = getPrimaryImage(product.images || []);
            return (
              <div key={id} className="card overflow-hidden group">
                <Link to={`/shop/${product.slug || id}`}>
                  <img
                    src={image}
                    alt={product.name}
                    className="w-full aspect-square object-cover group-hover:scale-105 transition-transform duration-300"
                  />
                </Link>
                <div className="p-4 space-y-2">
                  <Link to={`/shop/${product.slug || id}`}>
                    <h3 className="text-sm font-semibold line-clamp-2">{product.name}</h3>
                  </Link>
                  <p className="font-bold text-brand-400">
                    {formatCurrency(product.discount_price || product.price)}
                  </p>
                  <div className="flex gap-2">
                    <button
                      onClick={() =>
                        addToCart({
                          id,
                          name: product.name || '',
                          price: product.discount_price ?? product.price ?? 0,
                          image_url: image,
                        })
                      }
                      className="flex-1 btn-primary text-xs py-1.5 px-2"
                    >
                      Add to Cart
                    </button>
                    <button
                      onClick={() => toggleWishlist(id)}
                      className="btn-ghost text-red-400 px-2"
                      aria-label="Remove from wishlist"
                    >
                      <FiTrash2 size={16} />
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
