import { Link } from 'react-router-dom';
import { FiArrowRight } from 'react-icons/fi';

/**
 * Consistent section heading for recommendation strips.
 */
export default function SectionHeader({
  title,
  subtitle,
  actionLabel = 'View all',
  actionTo,
  id,
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-4 mb-6">
      <div>
        <h2
          id={id}
          className="font-display font-bold text-2xl md:text-3xl text-white uppercase tracking-wide"
        >
          {title}
        </h2>
        {subtitle ? (
          <p className="text-sm text-slate-400 mt-1">{subtitle}</p>
        ) : null}
      </div>
      {actionTo ? (
        <Link
          to={actionTo}
          className="text-brand-500 text-sm font-semibold flex items-center gap-2 hover:text-brand-400 transition-colors"
        >
          {actionLabel} <FiArrowRight aria-hidden />
        </Link>
      ) : null}
    </div>
  );
}
