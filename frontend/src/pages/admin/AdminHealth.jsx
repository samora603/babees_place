import { useEffect, useState } from 'react';
import { healthService } from '@/services/healthService';
import { auditService } from '@/services/auditService';
import { exportService } from '@/services/exportService';
import { logger } from '@/services/logger';
import Button from '@/components/ui/Button';
import Spinner from '@/components/ui/Spinner';
import toast from 'react-hot-toast';

function StatusPill({ ok, label }) {
  return (
    <span className={`inline-flex items-center gap-2 px-2.5 py-1 rounded-lg text-xs border ${
      ok
        ? 'border-emerald-500/30 text-emerald-400 bg-emerald-500/10'
        : 'border-red-500/30 text-red-400 bg-red-500/10'
    }`}>
      <span className={`w-1.5 h-1.5 rounded-full ${ok ? 'bg-emerald-400' : 'bg-red-400'}`} />
      {label}
    </span>
  );
}

export default function AdminHealth() {
  const [health, setHealth] = useState(null);
  const [audits, setAudits] = useState([]);
  const [loading, setLoading] = useState(true);
  const [logs, setLogs] = useState([]);

  const load = async () => {
    setLoading(true);
    try {
      const [h, a] = await Promise.all([
        healthService.getSystemHealth(),
        auditService.listAuditLogs({ limit: 25 }).catch(() => []),
      ]);
      setHealth(h);
      setAudits(a);
      setLogs(logger.getRecentLogs().slice(-30).reverse());
    } catch (err) {
      toast.error(err.message || 'Health check failed');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const exportAudits = (format) => {
    const rows = audits.map((a) => ({
      createdAt: a.createdAt,
      action: a.action,
      entityType: a.entityType,
      entityId: a.entityId,
      summary: a.summary,
    }));
    exportService.exportAndAudit(format, `audit-log-${Date.now()}`, rows, undefined, 'audit')
      .then(() => toast.success(`Exported ${format}`))
      .catch((err) => toast.error(err.message));
  };

  if (loading && !health) {
    return <div className="p-8 flex justify-center"><Spinner size="lg" /></div>;
  }

  const c = health?.checks || {};

  return (
    <div className="p-8 space-y-8 max-w-5xl">
      <header className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-display text-2xl text-white tracking-widest uppercase">System Health</h1>
          <p className="text-slate-400 text-sm mt-1">
            {health?.appName} v{health?.version} · {health?.status} · {health?.checkedAt
              ? new Date(health.checkedAt).toLocaleString()
              : '—'}
          </p>
        </div>
        <Button type="button" variant="secondary" onClick={load} loading={loading}>Refresh</Button>
      </header>

      <section className="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <HealthCard title="Database" ok={c.database?.ok} detail={c.database?.detail} meta={c.database?.latencyMs != null ? `${c.database.latencyMs} ms` : null} />
        <HealthCard title="Storage" ok={c.storage?.ok} detail={c.storage?.detail} meta={c.storage?.latencyMs != null ? `${c.storage.latencyMs} ms` : null} />
        <HealthCard title="Environment" ok={c.env?.ok} detail={c.env?.detail} meta={c.env?.mode} />
        <HealthCard title="Payment provider" ok={c.providers?.payment?.ok} detail={`${c.providers?.payment?.id} — ${c.providers?.payment?.detail}`} />
        <HealthCard title="Email / SMS" ok={c.providers?.email?.ok && c.providers?.sms?.ok} detail={`email:${c.providers?.email?.id} · sms:${c.providers?.sms?.id}`} />
        <HealthCard title="Migrations" ok={c.migrations?.ok} detail={c.migrations?.detail} meta={c.migrations?.latestAuthored} />
      </section>

      <section className="card p-6 space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="font-display text-lg text-white">Admin audit log</h2>
          <div className="flex gap-2">
            <Button type="button" variant="ghost" className="text-xs" onClick={() => exportAudits('csv')}>CSV</Button>
            <Button type="button" variant="ghost" className="text-xs" onClick={() => exportAudits('json')}>JSON</Button>
            <Button type="button" variant="ghost" className="text-xs" onClick={() => exportAudits('excel')}>Excel</Button>
            <Button type="button" variant="ghost" className="text-xs" onClick={() => exportAudits('pdf')}>PDF</Button>
          </div>
        </div>
        {audits.length === 0 ? (
          <p className="text-sm text-slate-500">No audit entries yet (apply migration 019).</p>
        ) : (
          <ul className="space-y-2 text-sm">
            {audits.map((a) => (
              <li key={a.id} className="flex flex-wrap justify-between gap-2 border-b border-brand-500/10 pb-2 text-slate-300">
                <span>
                  <span className="text-brand-400 font-mono text-xs">{a.action}</span>
                  <span className="text-slate-500 ml-2">{a.summary || `${a.entityType} ${a.entityId || ''}`}</span>
                </span>
                <span className="text-xs text-slate-500">{a.createdAt ? new Date(a.createdAt).toLocaleString() : ''}</span>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="card p-6 space-y-3">
        <h2 className="font-display text-lg text-white">Recent application logs</h2>
        <p className="text-xs text-slate-500">In-memory ring buffer (not persisted). Level: {logger.getLevel()}</p>
        <ul className="space-y-1 font-mono text-[11px] text-slate-400 max-h-64 overflow-y-auto">
          {logs.map((l, i) => (
            <li key={`${l.ts}-${i}`}>
              [{l.level}] [{l.category}] {l.message}
            </li>
          ))}
          {logs.length === 0 && <li>No log entries yet.</li>}
        </ul>
      </section>
    </div>
  );
}

function HealthCard({ title, ok, detail, meta }) {
  return (
    <div className="card p-5 space-y-2">
      <div className="flex items-center justify-between gap-2">
        <h3 className="text-sm font-semibold text-white">{title}</h3>
        <StatusPill ok={Boolean(ok)} label={ok ? 'OK' : 'Issue'} />
      </div>
      <p className="text-xs text-slate-400">{detail}</p>
      {meta && <p className="text-[10px] uppercase tracking-wider text-slate-500">{meta}</p>}
    </div>
  );
}
