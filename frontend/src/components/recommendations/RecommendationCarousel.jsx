import SectionHeader from '@/components/recommendations/SectionHeader';
import ProductStrip from '@/components/recommendations/ProductStrip';

/**
 * Full recommendation section: header + accessible product strip.
 */
export default function RecommendationCarousel({
  title,
  subtitle,
  products = [],
  loading = false,
  emptyMessage,
  actionTo = '/shop',
  actionLabel = 'Explore collection',
  id,
}) {
  const headingId = id || `rec-${String(title || 'section').toLowerCase().replace(/\s+/g, '-')}`;

  if (!loading && products.length === 0 && !emptyMessage) {
    return null;
  }

  return (
    <section className="section-container py-12" aria-labelledby={headingId}>
      <SectionHeader
        id={headingId}
        title={title}
        subtitle={subtitle}
        actionTo={actionTo}
        actionLabel={actionLabel}
      />
      <ProductStrip
        products={products}
        loading={loading}
        emptyMessage={emptyMessage}
        labelledBy={headingId}
        ariaLabel={title}
      />
    </section>
  );
}
