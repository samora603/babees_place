import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { recommendationService } from '@/services/recommendationService';
import ProductStrip from '@/components/recommendations/ProductStrip';

/**
 * Empty-state helper that suggests products to explore.
 */
export default function ExploreSuggestions({
  title = 'Explore products',
  message = 'Discover something from our collection.',
  limit = 6,
  ctaTo = '/shop',
  ctaLabel = 'Browse collection',
}) {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true;
    recommendationService
      .getExploreSuggestions(limit)
      .then((list) => {
        if (mounted) setProducts(list || []);
      })
      .catch(() => {
        if (mounted) setProducts([]);
      })
      .finally(() => {
        if (mounted) setLoading(false);
      });
    return () => {
      mounted = false;
    };
  }, [limit]);

  return (
    <div className="space-y-6">
      <div className="text-center">
        <p className="text-slate-400 mb-4">{message}</p>
        <Link to={ctaTo} className="btn-primary inline-block">
          {ctaLabel}
        </Link>
      </div>
      {(loading || products.length > 0) && (
        <div>
          <h3 className="font-display font-semibold text-lg text-white mb-4 text-center">
            {title}
          </h3>
          <ProductStrip
            products={products}
            loading={loading}
            emptyMessage=""
            ariaLabel={title}
          />
        </div>
      )}
    </div>
  );
}
