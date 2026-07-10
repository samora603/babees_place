import { FiChevronLeft, FiChevronRight } from 'react-icons/fi';

export default function Pagination({ page, pages, onPage }) {
  if (pages <= 1) return null;

  const pageNumbers = Array.from({ length: Math.min(pages, 5) }, (_, i) => {
    if (pages <= 5) return i + 1;
    if (page <= 3) return i + 1;
    if (page >= pages - 2) return pages - 4 + i;
    return page - 2 + i;
  });

  return (
    <div className="flex items-center justify-center gap-1 mt-8">
      <button
        onClick={() => onPage(page - 1)}
        disabled={page === 1}
        className="w-9 h-9 rounded-xl bg-surface-card border border-surface-border text-slate-400 hover:text-white hover:border-slate-500 flex items-center justify-center disabled:opacity-30 transition-all"
      >
        <FiChevronLeft size={16} />
      </button>

      {pageNumbers.map((n) => (
        <button
          key={n}
          onClick={() => onPage(n)}
          className={`w-9 h-9 rounded-xl text-sm font-medium transition-all ${
            n === page
              ? 'bg-brand-500 text-white'
              : 'bg-surface-card border border-surface-border text-slate-400 hover:text-white hover:border-slate-500'
          }`}
        >
          {n}
        </button>
      ))}

      <button
        onClick={() => onPage(page + 1)}
        disabled={page === pages}
        className="w-9 h-9 rounded-xl bg-surface-card border border-surface-border text-slate-400 hover:text-white hover:border-slate-500 flex items-center justify-center disabled:opacity-30 transition-all"
      >
        <FiChevronRight size={16} />
      </button>
    </div>
  );
}
