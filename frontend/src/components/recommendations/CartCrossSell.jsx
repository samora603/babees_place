import { useEffect, useState } from 'react';
import { recommendationService } from '@/services/recommendationService';
import RecommendationCarousel from '@/components/recommendations/RecommendationCarousel';

/**
 * Cart page cross-sell strip.
 */
export default function CartCrossSell({ cartItems = [], limit = 8 }) {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);

  const cartKey = (cartItems || [])
    .map((item) => `${item.product_id || item.product?.id}:${item.quantity}`)
    .join('|');

  useEffect(() => {
    let mounted = true;
    setLoading(true);

    recommendationService
      .getCartCrossSell(cartItems, limit)
      .then((list) => {
        if (mounted) setProducts(list || []);
      })
      .catch((err) => {
        console.error('CartCrossSell error:', err);
        if (mounted) setProducts([]);
      })
      .finally(() => {
        if (mounted) setLoading(false);
      });

    return () => {
      mounted = false;
    };
    // cartKey captures cart identity without deep-compare
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cartKey, limit]);

  if (!loading && products.length === 0) return null;

  return (
    <div className="mt-12">
      <RecommendationCarousel
        title="You Might Also Need"
        subtitle="Complementary picks for your cart"
        products={products}
        loading={loading}
        actionTo="/shop"
        actionLabel="Keep shopping"
        id="cart-cross-sell"
      />
    </div>
  );
}
