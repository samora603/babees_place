import { useState, useEffect, lazy, Suspense } from 'react';
import { Link } from 'react-router-dom';
import { FiArrowRight, FiShoppingBag, FiTruck, FiSmartphone } from 'react-icons/fi';
import { GiBee } from 'react-icons/gi';

import { productService } from '@/services/productService';

import ProductGrid from '@/components/products/ProductGrid';
import Hero from '@/components/layout/Hero';
import RecommendationSkeleton from '@/components/recommendations/RecommendationSkeleton';
import Button from '@/components/ui/Button';

const HomeDiscoverSections = lazy(() =>
  import('@/components/recommendations/HomeDiscoverSections'),
);

export default function Home() {
  const [featured, setFeatured] = useState([]);
  const [categories, setCategories] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [usingFallback, setUsingFallback] = useState(false);
  const [retryToken, setRetryToken] = useState(0);

  useEffect(() => {
    let mounted = true;

    const loadHomeData = async () => {
      setLoading(true);
      setError(null);
      setUsingFallback(false);

      try {
        const [featuredRes, catRes] = await Promise.all([
          productService.getProducts({ featured: true, limit: 8 }),
          productService.getCategories(),
        ]);

        if (!mounted) return;

        let products = featuredRes?.data?.data || [];

        if (products.length === 0) {
          const fallbackRes = await productService.getProducts({
            limit: 8,
            sort: '-createdAt',
          });
          products = fallbackRes?.data?.data || [];
          setUsingFallback(products.length > 0);
        }

        const cats = catRes?.data?.data || [];

        setFeatured(products);
        setCategories(cats);

        if (featuredRes?.error) {
          setError('Failed to load products from Supabase');
        }
      } catch (err) {
        console.error('Home load error:', err);
        if (mounted) {
          setError('Unable to load homepage');
          setFeatured([]);
          setCategories([]);
        }
      } finally {
        if (mounted) setLoading(false);
      }
    };

    loadHomeData();

    return () => {
      mounted = false;
    };
  }, [retryToken]);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-slate-300">
        Loading featured products…
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center gap-4 text-center px-4">
        <p className="text-amber-300">{error}</p>
        <Button variant="secondary" onClick={() => setRetryToken((token) => token + 1)}>
          Retry
        </Button>
      </div>
    );
  }

  return (
    <div className="bg-[#0B0B0B] min-h-screen text-slate-200">
      <Hero />

      <section className="section-container py-12">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-8">
          {[
            {
              icon: FiSmartphone,
              title: 'Seamless Acquisition',
              desc: 'Instant secure checkout experience.',
            },
            {
              icon: FiShoppingBag,
              title: 'Pickup Options',
              desc: 'Collect from designated locations.',
            },
            {
              icon: FiTruck,
              title: 'Fast Delivery',
              desc: 'Quick and reliable delivery service.',
            },
          ].map(({ icon: Icon, title, desc }) => (
            <div
              key={title}
              className="p-6 bg-[#111] border border-gray-800 rounded-xl"
            >
              <div className="flex items-center gap-4">
                <Icon className="text-brand-500" size={22} />
                <h3 className="font-semibold">{title}</h3>
              </div>
              <p className="text-sm text-gray-400 mt-2">{desc}</p>
            </div>
          ))}
        </div>
      </section>

      {categories.length > 0 && (
        <section className="section-container py-16">
          <div className="flex flex-col items-center mb-8">
            <GiBee className="text-brand-500 text-3xl mb-2" />
            <h2 className="text-2xl font-bold uppercase">Categories</h2>
            <p className="text-gray-400 text-sm mt-2">Shop by collection</p>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {categories.map((cat) => {
              const slug = cat.slug || String(cat.name || '').toLowerCase().replace(/\s+/g, '-');
              const banner = `/category_banners/${slug}.jpg`;
              return (
                <Link
                  key={cat.id || cat.name}
                  to={`/shop?category=${cat.id}`}
                  className="group relative aspect-[16/9] overflow-hidden rounded-xl border border-gray-800 bg-[#111]"
                >
                  <img
                    src={banner}
                    alt={`${cat.name} collection`}
                    loading="lazy"
                    decoding="async"
                    className="absolute inset-0 h-full w-full object-cover opacity-80 transition duration-500 group-hover:scale-105 group-hover:opacity-100"
                  />
                  <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/30 to-transparent" />
                  <span className="absolute bottom-4 left-4 font-display text-lg font-semibold text-white tracking-wide">
                    {cat.name}
                  </span>
                </Link>
              );
            })}
          </div>
        </section>
      )}

      <section className="section-container py-16">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-3xl font-bold uppercase">Featured Products</h2>
            <p className="text-gray-400 text-sm">
              {usingFallback ? 'Latest arrivals' : 'Hand-picked selections'}
            </p>
          </div>

          <Link to="/shop" className="text-brand-500 flex items-center gap-2">
            View All <FiArrowRight />
          </Link>
        </div>

        <ProductGrid
          products={featured}
          loading={false}
          emptyMessage="No products available."
        />
      </section>

      <Suspense
        fallback={
          <div className="section-container py-12">
            <RecommendationSkeleton count={4} />
          </div>
        }
      >
        <HomeDiscoverSections />
      </Suspense>
    </div>
  );
}
