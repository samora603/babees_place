import { FiMinus, FiPlus } from 'react-icons/fi';

export default function QuantitySelector({ value, min = 1, max = 99, onChange }) {
  return (
    <div className="flex items-center gap-1">
      <button
        onClick={() => onChange(Math.max(min, value - 1))}
        disabled={value <= min}
        className="w-8 h-8 rounded-lg bg-surface border border-surface-border text-slate-400 hover:text-white hover:border-slate-500 flex items-center justify-center disabled:opacity-30 transition-all"
        aria-label="Decrease quantity"
      >
        <FiMinus size={14} />
      </button>

      <span className="w-10 text-center text-sm font-semibold text-slate-100">{value}</span>

      <button
        onClick={() => onChange(Math.min(max, value + 1))}
        disabled={value >= max}
        className="w-8 h-8 rounded-lg bg-surface border border-surface-border text-slate-400 hover:text-white hover:border-slate-500 flex items-center justify-center disabled:opacity-30 transition-all"
        aria-label="Increase quantity"
      >
        <FiPlus size={14} />
      </button>
    </div>
  );
}
