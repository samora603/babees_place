import ProductCard from '@/components/products/ProductCard';

/**
 * Compact product card for recommendation strips.
 * Reuses ProductCard for consistent cart/wishlist behavior.
 */
export default function ProductRecommendationCard({ product }) {
  if (!product) return null;
  return <ProductCard product={product} />;
}
