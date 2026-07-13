import { useRef, useState, useCallback, useEffect } from 'react';
import { FiChevronLeft, FiChevronRight } from 'react-icons/fi';
import ProductRecommendationCard from '@/components/recommendations/ProductRecommendationCard';
import RecommendationSkeleton from '@/components/recommendations/RecommendationSkeleton';

/**
 * Horizontally scrollable product strip with keyboard + ARIA support.
 */
export default function ProductStrip({
  products = [],
  loading = false,
  emptyMessage = 'Nothing to show yet.',
  labelledBy,
  ariaLabel = 'Product recommendations',
}) {
  const scrollerRef = useRef(null);
  const [canPrev, setCanPrev] = useState(false);
  const [canNext, setCanNext] = useState(false);

  const updateScrollState = useCallback(() => {
    const el = scrollerRef.current;
    if (!el) return;
    setCanPrev(el.scrollLeft > 8);
    setCanNext(el.scrollLeft + el.clientWidth < el.scrollWidth - 8);
  }, []);

  useEffect(() => {
    updateScrollState();
    const el = scrollerRef.current;
    if (!el) return undefined;
    el.addEventListener('scroll', updateScrollState, { passive: true });
    window.addEventListener('resize', updateScrollState);
    return () => {
      el.removeEventListener('scroll', updateScrollState);
      window.removeEventListener('resize', updateScrollState);
    };
  }, [products, loading, updateScrollState]);

  const scrollByPage = (direction) => {
    const el = scrollerRef.current;
    if (!el) return;
    const amount = Math.max(240, el.clientWidth * 0.8) * direction;
    el.scrollBy({ left: amount, behavior: 'smooth' });
  };

  if (loading) return <RecommendationSkeleton />;

  if (!products.length) {
    return (
      <p className="text-sm text-slate-500 py-6" role="status">
        {emptyMessage}
      </p>
    );
  }

  return (
    <div className="relative group/strip">
      <div
        ref={scrollerRef}
        role="region"
        aria-labelledby={labelledBy}
        aria-label={labelledBy ? undefined : ariaLabel}
        tabIndex={0}
        onKeyDown={(e) => {
          if (e.key === 'ArrowRight') {
            e.preventDefault();
            scrollByPage(1);
          } else if (e.key === 'ArrowLeft') {
            e.preventDefault();
            scrollByPage(-1);
          }
        }}
        className="flex gap-4 overflow-x-auto scroll-smooth pb-2 snap-x snap-mandatory focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand-500 [-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      >
        {products.map((product) => (
          <div
            key={product.id || product._id}
            className="w-56 sm:w-64 shrink-0 snap-start"
          >
            <ProductRecommendationCard product={product} />
          </div>
        ))}
      </div>

      <button
        type="button"
        aria-label="Scroll recommendations left"
        disabled={!canPrev}
        onClick={() => scrollByPage(-1)}
        className="hidden md:flex absolute left-0 top-1/2 -translate-y-1/2 -translate-x-2 z-10 w-10 h-10 items-center justify-center rounded-full bg-[#111] border border-brand-500/30 text-brand-400 shadow-lg disabled:opacity-0 opacity-0 group-hover/strip:opacity-100 focus-visible:opacity-100 transition-opacity focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-500"
      >
        <FiChevronLeft size={20} />
      </button>
      <button
        type="button"
        aria-label="Scroll recommendations right"
        disabled={!canNext}
        onClick={() => scrollByPage(1)}
        className="hidden md:flex absolute right-0 top-1/2 -translate-y-1/2 translate-x-2 z-10 w-10 h-10 items-center justify-center rounded-full bg-[#111] border border-brand-500/30 text-brand-400 shadow-lg disabled:opacity-0 opacity-0 group-hover/strip:opacity-100 focus-visible:opacity-100 transition-opacity focus-visible:outline focus-visible:outline-2 focus-visible:outline-brand-500"
      >
        <FiChevronRight size={20} />
      </button>
    </div>
  );
}
