import { useState, useEffect, lazy, Suspense } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { productService } from '@/services/productService';
import { useCart } from '@/context/CartContext';
import { useWishlist } from '@/context/WishlistContext';
import { useAuth } from '@/context/AuthContext';
import { recentlyViewedService } from '@/services/recentlyViewedService';
import { getImageAtIndex } from '@/utils/images';
import { formatCurrency, getPrimaryImage, resolveMediaUrl } from '@/utils/helpers';
import { capQuantity, isOutOfStock } from '@/constants/inventory';
import StarRating from '@/components/ui/StarRating';
import QuantitySelector from '@/components/ui/QuantitySelector';
import Skeleton from '@/components/ui/Skeleton';
import RecommendationSkeleton from '@/components/recommendations/RecommendationSkeleton';
import toast from 'react-hot-toast';
import { FiHeart, FiShoppingCart } from 'react-icons/fi';
import Button from '@/components/ui/Button';

const YouMayAlsoLike = lazy(() =>
  import('@/components/recommendations/YouMayAlsoLike'),
);
const RecentlyViewedCarousel = lazy(() =>
  import('@/components/recommendations/RecentlyViewedCarousel'),
);

export default function ProductDetail() {
  const { idOrSlug } = useParams();
  const navigate = useNavigate();
  const { addToCart } = useCart();
  const { toggleWishlist, isWishlisted } = useWishlist();
  const { isAuthenticated } = useAuth();
  const [product, setProduct] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [activeImage, setActiveImage] = useState(0);
  const [quantity, setQuantity] = useState(1);
  const [selectedVariation, setSelectedVariation] = useState(null);
  const [adding, setAdding] = useState(false);
  const [retryToken, setRetryToken] = useState(0);

  useEffect(() => {
    let mounted = true;
    const load = async () => {
      setLoading(true);
      setError(null);
      try {
        const { data, error: svcErr } = await productService.getProduct(idOrSlug);
        if (svcErr) throw svcErr;
        if (!mounted) return;
        setProduct(data?.data ?? null);
        if (data?.data) {
          recentlyViewedService.trackView(data.data);
        }
      } catch (err) {
        console.error('ProductDetail load error:', err);
        if (!mounted) return;
        setError(err || new Error('Unable to load product'));
        setProduct(null);
      } finally {
        if (mounted) setLoading(false);
      }
    };
    if (idOrSlug) load();
    return () => {
      mounted = false;
    };
  }, [idOrSlug, retryToken]);

  if (loading) {
    return (
      <div className="section-container py-10">
        <div className="grid md:grid-cols-2 gap-10 lg:gap-16">
          <div className="space-y-3">
            <Skeleton className="aspect-square w-full rounded-2xl" variant="rectangular" />
            <div className="flex gap-2">
              {[...Array(3)].map((_, i) => (
                <Skeleton key={i} className="w-16 h-16 rounded-xl" variant="rectangular" />
              ))}
            </div>
          </div>
          <div className="space-y-6">
            <Skeleton className="w-24 h-4" variant="text" />
            <Skeleton className="w-3/4 h-10" variant="text" />
            <Skeleton className="w-32 h-6" variant="text" />
            <div className="space-y-2">
              {[...Array(4)].map((_, i) => (
                <Skeleton key={i} className="w-full h-4" variant="text" />
              ))}
            </div>
            <div className="flex gap-4 mt-8">
              <Skeleton className="w-1/2 h-12 rounded-xl" variant="rectangular" />
              <Skeleton className="w-12 h-12 rounded-xl" variant="rectangular" />
            </div>
          </div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="section-container py-20 text-center space-y-4">
        <p className="text-red-400">We couldn&apos;t load this product right now. Please try again.</p>
        <Button variant="secondary" onClick={() => setRetryToken((token) => token + 1)}>
          Retry
        </Button>
      </div>
    );
  }
  if (!product) {
    return (
      <div className="section-container py-20 text-center text-slate-400">
        Product not found.
      </div>
    );
  }

  const stock = product.stock ?? 0;
  const isActive = product.is_active !== false;
  const canAddToCart = isActive && !isOutOfStock(stock);
  const productId = product.id || product._id || product.product_id;

  const handleAddToCart = async () => {
    if (!product || !canAddToCart || adding) return;
    if (!isAuthenticated) {
      toast.error('Please sign in to add to cart');
      navigate('/login', { state: { from: { pathname: `/shop/${idOrSlug}` } } });
      return;
    }

    setAdding(true);
    try {
      await addToCart(
        {
          id: productId,
          name: product.name || product.title || '',
          price: product.discount_price ?? product.price ?? 0,
          image_url: getPrimaryImage(product.images || []),
        },
        capQuantity(quantity, stock),
      );
    } finally {
      setAdding(false);
    }
  };

  const galleryImages = Array.isArray(product.images) ? product.images : [];
  const displayGallery = galleryImages.filter((img) => img.role !== 'thumb');
  const visibleGallery = displayGallery.length ? displayGallery : galleryImages;
  const safeIndex = Math.min(activeImage, Math.max(visibleGallery.length - 1, 0));
  const activeImg = visibleGallery[safeIndex];
  const mainImageSrc = resolveMediaUrl(activeImg?.url) || getImageAtIndex(visibleGallery, safeIndex);

  return (
    <div>
      <div className="section-container py-10">
      <div className="grid md:grid-cols-2 gap-10 lg:gap-16">
        <div className="space-y-3">
          <div className="aspect-square rounded-2xl overflow-hidden bg-surface-card border border-surface-border">
            <img
              src={mainImageSrc}
              alt={activeImg?.alt || product.name}
              loading="lazy"
              decoding="async"
              className="w-full h-full object-cover"
            />
          </div>
          {visibleGallery.length > 1 && (
            <div className="flex gap-2 overflow-x-auto">
              {visibleGallery.map((img, i) => (
                <button
                  key={img.path || img.url || i}
                  type="button"
                  onClick={() => setActiveImage(i)}
                  aria-label={img.alt || `${product.name} view ${i + 1}`}
                  className={`w-16 h-16 rounded-xl overflow-hidden border-2 shrink-0 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500/50 ${
                    i === safeIndex ? 'border-brand-500' : 'border-surface-border'
                  }`}
                >
                  <img
                    src={resolveMediaUrl(img.url)}
                    alt={img.alt || `${product.name} view ${i + 1}`}
                    loading="lazy"
                    decoding="async"
                    className="w-full h-full object-cover"
                  />
                </button>
              ))}
            </div>
          )}
        </div>

        <div className="space-y-5">
          <div>
            <p className="text-sm text-slate-500 mb-1">{product.categories?.name || product.category}</p>
            <h1 className="font-display font-bold text-3xl text-white leading-tight">{product.name}</h1>
          </div>

          <div className="flex items-center gap-3">
            <StarRating rating={product.rating} />
            <span className="text-sm text-slate-400">({product.reviewCount || 0} reviews)</span>
          </div>

          <div className="flex items-baseline gap-3">
            {product.discount_price ? (
              <>
                <span className="font-display font-bold text-3xl text-brand-400">
                  {formatCurrency(product.discount_price)}
                </span>
                <span className="text-lg text-slate-500 line-through">
                  {formatCurrency(product.price)}
                </span>
              </>
            ) : (
              <span className="font-display font-bold text-3xl">{formatCurrency(product.price)}</span>
            )}
          </div>

          <p className="text-slate-300 leading-relaxed">{product.description}</p>

          {product.variations?.map((variation) => (
            <div key={variation.name}>
              <label className="text-sm font-semibold text-slate-300 mb-2 block">{variation.name}</label>
              <div className="flex gap-2 flex-wrap">
                {variation.options.map((opt) => (
                  <button
                    key={opt.label}
                    onClick={() =>
                      setSelectedVariation({
                        name: variation.name,
                        option: opt.label,
                        priceModifier: opt.priceModifier,
                      })
                    }
                    className={`px-3 py-1.5 rounded-lg text-sm border transition-all ${
                      selectedVariation?.option === opt.label
                        ? 'border-brand-500 bg-brand-500/10 text-brand-400'
                        : 'border-surface-border text-slate-300 hover:border-slate-500'
                    }`}
                  >
                    {opt.label} {opt.priceModifier > 0 ? `+${formatCurrency(opt.priceModifier)}` : ''}
                  </button>
                ))}
              </div>
              {selectedVariation?.name === variation.name && (
                <p className="text-xs text-slate-500 mt-1">
                  Variation preference noted for this session — cart lines use the base product.
                </p>
              )}
            </div>
          ))}

          <div className="flex items-center gap-4">
            <QuantitySelector
              value={quantity}
              max={stock > 0 ? stock : 1}
              onChange={(v) => setQuantity(capQuantity(v, stock))}
            />
            <span className="text-sm text-slate-500">{stock} in stock</span>
          </div>

          <div className="flex gap-3">
            <button
              onClick={handleAddToCart}
              disabled={!canAddToCart || adding}
              className="btn-primary flex-1 flex items-center justify-center gap-2 disabled:opacity-50"
            >
              <FiShoppingCart />
              {!isActive
                ? 'Unavailable'
                : isOutOfStock(stock)
                  ? 'Out of Stock'
                  : adding
                    ? 'Adding…'
                    : 'Add to Cart'}
            </button>
            <button
              onClick={() => {
                if (!isAuthenticated) {
                  toast.error('Please sign in to save items');
                  return;
                }
                toggleWishlist(productId);
              }}
              className={`btn-secondary px-4 ${isWishlisted(productId) ? 'text-red-400 border-red-400/40' : ''}`}
            >
              <FiHeart className={isWishlisted(productId) ? 'fill-current' : ''} />
            </button>
          </div>

          {product.faqs?.length > 0 && (
            <div className="border-t border-surface-border pt-5 space-y-3">
              <h3 className="font-semibold text-slate-200">FAQs</h3>
              {product.faqs.map((faq, i) => (
                <div key={i} className="text-sm">
                  <p className="font-medium text-slate-200">{faq.question}</p>
                  <p className="text-slate-400 mt-1">{faq.answer}</p>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
      </div>

      <Suspense
        fallback={
          <div className="section-container py-12">
            <RecommendationSkeleton />
          </div>
        }
      >
        <YouMayAlsoLike product={product} />
        <RecentlyViewedCarousel excludeId={productId} />
      </Suspense>
    </div>
  );
}
