import { lazy, Suspense, useEffect, useState } from 'react';
import { useAuth } from '@/context/AuthContext';
import { recentlyViewedService } from '@/services/recentlyViewedService';
import { recommendationService } from '@/services/recommendationService';
import { buyAgainService } from '@/services/buyAgainService';
import RecommendationSkeleton from '@/components/recommendations/RecommendationSkeleton';

const RecommendationCarousel = lazy(() =>
  import('@/components/recommendations/RecommendationCarousel'),
);
const RecentlyViewedCarousel = lazy(() =>
  import('@/components/recommendations/RecentlyViewedCarousel'),
);

function LazySection({ children }) {
  return (
    <Suspense
      fallback={
        <div className="section-container py-12">
          <RecommendationSkeleton />
        </div>
      }
    >
      {children}
    </Suspense>
  );
}

/**
 * Home discover stack: Recently Viewed, Buy Again, Recommended, Trending, New Arrivals.
 */
export default function HomeDiscoverSections() {
  const { user, isAuthenticated } = useAuth();
  const [recommended, setRecommended] = useState([]);
  const [trending, setTrending] = useState([]);
  const [arrivals, setArrivals] = useState([]);
  const [buyAgain, setBuyAgain] = useState([]);
  const [loading, setLoading] = useState(true);
  const [hasRecent, setHasRecent] = useState(false);

  useEffect(() => {
    let mounted = true;

    const load = async () => {
      setLoading(true);
      try {
        const recent = recentlyViewedService.getRecentlyViewed();
        if (mounted) setHasRecent(recent.length > 0);

        const base = await Promise.all([
          recommendationService.getRecommendedForYou(recent, 12),
          recommendationService.getTrendingProducts(12),
          recommendationService.getNewArrivals(12),
        ]);

        let buyAgainList = [];
        if (isAuthenticated && user?.id) {
          const { data } = await buyAgainService.getBuyAgainProducts(user.id, {
            limit: 12,
          });
          buyAgainList = data || [];
        }

        if (!mounted) return;
        setRecommended(base[0] || []);
        setTrending(base[1] || []);
        setArrivals(base[2] || []);
        setBuyAgain(buyAgainList);
      } catch (err) {
        console.error('HomeDiscoverSections load error:', err);
        if (mounted) {
          setRecommended([]);
          setTrending([]);
          setArrivals([]);
          setBuyAgain([]);
        }
      } finally {
        if (mounted) setLoading(false);
      }
    };

    load();
    return () => {
      mounted = false;
    };
  }, [isAuthenticated, user?.id]);

  return (
    <div className="pb-8">
      <LazySection>
        <RecentlyViewedCarousel />
      </LazySection>

      {isAuthenticated && (loading || buyAgain.length > 0) ? (
        <LazySection>
          <RecommendationCarousel
            title="Buy Again"
            subtitle="From your previous orders"
            products={buyAgain}
            loading={loading}
            actionTo="/orders"
            actionLabel="My orders"
            id="buy-again"
          />
        </LazySection>
      ) : null}

      <LazySection>
        <RecommendationCarousel
          title="Recommended For You"
          subtitle={
            hasRecent
              ? 'Based on what you have been browsing'
              : 'Popular picks to get you started'
          }
          products={recommended}
          loading={loading}
          emptyMessage="No recommendations yet — explore the collection."
          id="recommended-for-you"
        />
      </LazySection>

      <LazySection>
        <RecommendationCarousel
          title="Trending Products"
          subtitle="What shoppers are buying"
          products={trending}
          loading={loading}
          emptyMessage="Trending products will appear as orders come in."
          id="trending-products"
        />
      </LazySection>

      <LazySection>
        <RecommendationCarousel
          title="New Arrivals"
          subtitle="Fresh additions to the collection"
          products={arrivals}
          loading={loading}
          emptyMessage="No new arrivals right now."
          id="new-arrivals"
        />
      </LazySection>
    </div>
  );
}
