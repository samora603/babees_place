import Button from '@/components/ui/Button';

export default function DashboardWidgetError({ message = 'Unable to load data.', onRetry }) {
  return (
    <div className="text-center py-6 space-y-3">
      <p className="text-sm text-red-400">{message}</p>
      {onRetry && (
        <Button variant="secondary" onClick={onRetry} className="text-xs">
          Retry
        </Button>
      )}
    </div>
  );
}
