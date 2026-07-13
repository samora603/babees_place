export default function DashboardWidgetEmpty({ message = 'Nothing to show yet.' }) {
  return (
    <p className="text-sm text-slate-400 text-center py-6">{message}</p>
  );
}
