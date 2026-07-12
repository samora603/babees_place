import { FiStar, FiTrash2 } from 'react-icons/fi';
import { getImageAtIndex } from '@/utils/images';

export default function ImageGallery({
  images = [],
  activeIndex = 0,
  onSetPrimary,
  onRemove,
  onSelect,
}) {
  const list = Array.isArray(images) ? images : [];

  if (!list.length) {
    return (
      <p className="text-sm text-slate-500 border border-dashed border-surface-border rounded-xl p-6 text-center">
        No images yet. Upload images below.
      </p>
    );
  }

  return (
    <div className="space-y-3">
      <div className="aspect-video max-w-md rounded-xl overflow-hidden bg-surface-card border border-surface-border">
        <img
          src={getImageAtIndex(list, activeIndex)}
          alt=""
          className="w-full h-full object-cover"
        />
      </div>
      <div className="flex flex-wrap gap-2">
        {list.map((img, i) => (
          <div
            key={img.path || img.url || i}
            className={`relative w-20 h-20 rounded-lg overflow-hidden border-2 shrink-0 ${
              i === activeIndex ? 'border-brand-500' : 'border-surface-border'
            }`}
          >
            <button
              type="button"
              onClick={() => onSelect?.(i)}
              className="w-full h-full"
              aria-label={`View image ${i + 1}`}
            >
              <img src={img.url} alt="" className="w-full h-full object-cover" />
            </button>
            <div className="absolute top-0.5 right-0.5 flex gap-0.5">
              {!img.isPrimary && (
                <button
                  type="button"
                  onClick={() => onSetPrimary?.(i)}
                  className="p-1 rounded bg-black/70 text-slate-300 hover:text-brand-400"
                  title="Set as primary"
                >
                  <FiStar size={12} />
                </button>
              )}
              <button
                type="button"
                onClick={() => onRemove?.(i)}
                className="p-1 rounded bg-black/70 text-slate-300 hover:text-red-400"
                title="Remove image"
              >
                <FiTrash2 size={12} />
              </button>
            </div>
            {img.isPrimary && (
              <span className="absolute bottom-0 inset-x-0 text-[9px] text-center bg-brand-500/90 text-black font-semibold py-0.5">
                Primary
              </span>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
