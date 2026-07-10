import Skeleton from '@/components/ui/Skeleton';

export default function ProductCardSkeleton() {
  return (
    <div className="card flex flex-col overflow-hidden bg-[#111] border border-surface-border">
      {/* Image Skeleton */}
      <div className="relative aspect-square overflow-hidden bg-[#0a0a0a]">
        <Skeleton className="w-full h-full rounded-none" variant="rectangular" />
      </div>

      {/* Info Skeleton */}
      <div className="p-5 flex flex-col flex-1 gap-3">
        {/* Category placeholder */}
        <Skeleton className="w-16 h-2 object-cover" variant="text" />
        
        {/* Title placeholder */}
        <div className="space-y-1">
          <Skeleton className="w-full h-3" variant="text" />
          <Skeleton className="w-2/3 h-3" variant="text" />
        </div>

        {/* Rating placeholder */}
        <Skeleton className="w-24 h-2 mt-1" variant="text" />

        <div className="flex items-end justify-between mt-auto pt-4 border-t border-brand-500/10">
          {/* Price placeholder */}
          <Skeleton className="w-20 h-5" variant="text" />
          
          {/* Cart Btn placeholder */}
          <Skeleton className="w-10 h-10 rounded border border-brand-500/30" variant="rectangular" />
        </div>
      </div>
    </div>
  );
}
