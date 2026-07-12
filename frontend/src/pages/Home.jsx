import { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import { FiArrowRight, FiShoppingBag, FiTruck, FiSmartphone } from 'react-icons/fi';
import { GiBee } from 'react-icons/gi';

import { productService } from '@/services/productService';

import ProductGrid from '@/components/products/ProductGrid';
import Hero from '@/components/layout/Hero';

export default function Home() {
  const [featured, setFeatured] = useState([]);
  const [categories, setCategories] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [usingFallback, setUsingFallback] = useState(false);

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
          const fallbackRes = await productService.getProducts({ limit: 8, sort: '-createdAt' });
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
  }, []);

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center text-slate-300">
        Loading featured products…
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen flex items-center justify-center text-amber-300">
        {error}
      </div>
    );
  }

  return (
    <div className="bg-[#0B0B0B] min-h-screen text-slate-200">
      <Hero />

      {/* FEATURES */}
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

      {/* CATEGORIES */}
      {categories.length > 0 && (
        <section className="section-container py-16">
          <div className="flex flex-col items-center mb-8">
            <GiBee className="text-brand-500 text-3xl mb-2" />
            <h2 className="text-2xl font-bold uppercase">Categories</h2>
          </div>

          <div className="flex flex-wrap gap-3 justify-center">
            {categories.map((cat) => (
              <Link
                key={cat.id || cat.name}
                to={`/shop?category=${cat.id}`}
                className="px-4 py-2 bg-[#111] border border-gray-700 rounded-full text-sm hover:bg-brand-500 hover:text-black transition"
              >
                {cat.name}
              </Link>
            ))}
          </div>
        </section>
      )}

      {/* FEATURED PRODUCTS */}
      <section className="section-container py-16">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-3xl font-bold uppercase">
              Featured Products
            </h2>
            <p className="text-gray-400 text-sm">
              {usingFallback ? 'Latest arrivals' : 'Hand-picked selections'}
            </p>
          </div>

          <Link
            to="/shop"
            className="text-brand-500 flex items-center gap-2"
          >
            View All <FiArrowRight />
          </Link>
        </div>

        <ProductGrid
          products={featured}
          loading={loading}
          emptyMessage="No products available."
        />
      </section>
    </div>
  );
}
