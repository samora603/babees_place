import { FiStar } from 'react-icons/fi';

export default function StarRating({ rating = 0, max = 5, onChange, size = 18 }) {
  const stars = Array.from({ length: max }, (_, i) => i + 1);

  return (
    <div className="flex items-center gap-0.5" role="group" aria-label={`Rating: ${rating} of ${max}`}>
      {stars.map((star) => (
        <button
          key={star}
          type="button"
          onClick={() => onChange?.(star)}
          className={`transition-colors ${onChange ? 'cursor-pointer hover:text-yellow-400' : 'cursor-default'} ${
            star <= rating ? 'text-yellow-400' : 'text-slate-600'
          }`}
          aria-label={`${star} star${star !== 1 ? 's' : ''}`}
        >
          <FiStar size={size} className={star <= rating ? 'fill-current' : ''} />
        </button>
      ))}
    </div>
  );
}
