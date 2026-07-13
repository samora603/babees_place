import { useEffect, useState } from 'react';
import { recommendationService } from '@/services/recommendationService';
import RecommendationCarousel from '@/components/recommendations/RecommendationCarousel';

/**
 * Product Detail — "You May Also Like"
 */
export default function YouMayAlsoLike({ product, limit = 12 }) {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!product?.id) {
      setProducts([]);
      setLoading(false);
      return undefined;
    }

    let mounted = true;
    setLoading(true);

    recommendationService
      .getRecommendations({ seed: product, limit, excludeIds: [product.id] })
      .then((list) => {
        if (mounted) setProducts(list || []);
      })
      .catch((err) => {
        console.error('YouMayAlsoLike error:', err);
        if (mounted) setProducts([]);
      })
      .finally(() => {
        if (mounted) setLoading(false);
      });

    return () => {
      mounted = false;
    };
  }, [product, limit]);

  if (!product) return null;

  return (
    <RecommendationCarousel
      title="You May Also Like"
      subtitle="Similar products from our collection"
      products={products}
      loading={loading}
      emptyMessage="No similar products found right now."
      id="you-may-also-like"
    />
  );
}
