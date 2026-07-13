import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { recentlyViewedService } from '@/services/recentlyViewedService';
import RecommendationCarousel from '@/components/recommendations/RecommendationCarousel';

/**
 * Reads local recently-viewed list and renders a carousel.
 * Optionally hydrates with live product data when `hydrate` is true (default false — snapshots are enough for cards).
 */
export default function RecentlyViewedCarousel({
  title = 'Recently Viewed',
  subtitle = 'Pick up where you left off',
  limit = 12,
  excludeId = null,
}) {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    const items = recentlyViewedService
      .getRecentlyViewed()
      .filter((p) => !excludeId || String(p.id) !== String(excludeId))
      .slice(0, limit);
    setProducts(items);
    setLoading(false);
  }, [excludeId, limit]);

  if (!loading && products.length === 0) {
    return (
      <section className="section-container py-10">
        <div className="rounded-2xl border border-brand-500/15 bg-[#111] p-8 text-center">
          <h2 className="font-display font-semibold text-xl text-white mb-2">{title}</h2>
          <p className="text-sm text-slate-400 mb-4">
            Products you browse will appear here for quick return visits.
          </p>
          <Link to="/shop" className="btn-primary inline-block text-sm">
            Browse the collection
          </Link>
        </div>
      </section>
    );
  }

  return (
    <RecommendationCarousel
      title={title}
      subtitle={subtitle}
      products={products}
      loading={loading}
      actionTo="/shop"
      actionLabel="Continue shopping"
      id="recently-viewed"
    />
  );
}
