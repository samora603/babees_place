const STATUS_STYLES = {
  unread: 'bg-brand-500/15 text-brand-400 border-brand-500/30',
  read: 'bg-slate-500/10 text-slate-400 border-slate-500/20',
  archived: 'bg-slate-700/40 text-slate-500 border-slate-600/30',
};

export default function NotificationStatusBadge({ status }) {
  const style = STATUS_STYLES[status] || STATUS_STYLES.read;
  return (
    <span className={`inline-flex items-center px-2 py-0.5 text-[10px] uppercase tracking-wider font-semibold rounded-md border ${style}`}>
      {status}
    </span>
  );
}
