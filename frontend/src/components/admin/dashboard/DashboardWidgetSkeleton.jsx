export default function DashboardWidgetSkeleton({ rows = 5 }) {
  return (
    <div className="space-y-3" aria-busy="true" aria-label="Loading widget">
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="h-10 rounded-lg bg-slate-800/60 animate-pulse" />
      ))}
    </div>
  );
}
