import ProductCardSkeleton from '@/components/products/ProductCardSkeleton';

export default function RecommendationSkeleton({ count = 4 }) {
  return (
    <div
      className="flex gap-4 overflow-hidden"
      role="status"
      aria-label="Loading recommendations"
    >
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="w-56 sm:w-64 shrink-0">
          <ProductCardSkeleton />
        </div>
      ))}
      <span className="sr-only">Loading…</span>
    </div>
  );
}
