import { useEffect, useState } from 'react';
import { adminService } from '@/services/adminService';
import { formatDate } from '@/utils/helpers';
import Spinner from '@/components/ui/Spinner';
import Pagination from '@/components/ui/Pagination';
import { GiBee } from 'react-icons/gi';

export default function AdminUsers() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [pages, setPages] = useState(1);
  const [search, setSearch] = useState('');

  useEffect(() => {
    setLoading(true);
    adminService.getUsers({ page, limit: 15, ...(search && { search }) })
      .then(({ data }) => { setUsers(data.data); setPages(data.pages); })
      .finally(() => setLoading(false));
  }, [page, search]);

  return (
    <div className="space-y-8 bg-[#0B0B0B] min-h-full pb-12">
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 border-b border-brand-500/10 pb-6 relative">
        <div className="absolute top-0 right-0 w-40 h-40 bg-brand-500/5 rounded-full blur-[60px] pointer-events-none"></div>
        <div>
          <h1 className="font-display font-bold text-3xl text-white tracking-wide uppercase flex items-center gap-3">
             <GiBee className="text-brand-500/80" /> Clientele
          </h1>
          <p className="text-sm text-slate-400 font-light mt-1">Manage user profiles and executive accounts</p>
        </div>
      </div>

      <div className="relative group w-full max-w-sm z-10">
         <span className="w-1.5 h-1.5 rounded-full bg-brand-500 absolute -left-4 top-1/2 -translate-y-1/2 opacity-0 group-focus-within:opacity-100 transition-opacity"></span>
         <input type="search" placeholder="Search dossier by name/phone/email..." value={search} onChange={(e) => setSearch(e.target.value)} className="input w-full bg-[#111] border-brand-500/20 focus:border-brand-500 py-3 text-slate-200 placeholder:text-slate-500 shadow-inner" id="admin-users-search" />
      </div>

      {loading ? <div className="flex justify-center py-24"><Spinner size="lg" /></div> : (
        <div className="bg-[#111] rounded-2xl border border-brand-500/10 shadow-[0_10px_30px_rgba(0,0,0,0.5)] overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm text-left whitespace-nowrap">
              <thead className="bg-[#0A0A0A] border-b border-brand-500/20 text-[10px] uppercase tracking-[0.15em] text-brand-500/80 font-semibold">
                <tr>
                  <th className="px-6 py-5">Profile Identity</th>
                  <th className="px-6 py-5">Contact Details</th>
                  <th className="px-6 py-5">Access Level</th>
                  <th className="px-6 py-5">Initiation Date</th>
                  <th className="px-6 py-5">Operational Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-brand-500/5 text-slate-300">
                {users.map((u) => (
                  <tr key={u._id} className="hover:bg-brand-500/5 transition-colors group">
                    <td className="px-6 py-4">
                      <div className="flex flex-col">
                        <span className="font-medium text-white group-hover:text-brand-400 transition-colors tracking-wide">{u.name || 'Unknown Entity'}</span>
                        <span className="text-[10px] font-mono text-slate-500 mt-1">{u.email || ''}</span>
                      </div>
                    </td>
                    <td className="px-6 py-4 text-brand-400 font-mono tracking-widest text-xs">{u.phone}</td>
                    <td className="px-6 py-4">
                      {u.role === 'admin' ? (
                        <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded border border-brand-500/30 bg-brand-500/10 text-[10px] uppercase tracking-widest text-brand-500 font-bold shadow-[0_0_10px_rgba(212,175,55,0.1)]">
                           <span className="w-1.5 h-1.5 rounded-full bg-brand-500 animate-pulse"></span> Executive
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded border border-surface-border bg-[#0A0A0A] text-[10px] uppercase tracking-widest text-slate-400 font-semibold">
                           Standard
                        </span>
                      )}
                    </td>
                    <td className="px-6 py-4 text-[11px] font-mono tracking-wider text-slate-400">{formatDate(u.createdAt)}</td>
                    <td className="px-6 py-4">
                      {u.isActive ? (
                        <span className="inline-flex items-center justify-center min-w-[5rem] px-2 py-1 rounded text-[10px] uppercase tracking-widest font-bold bg-[#0A0A0A] text-brand-500 border border-brand-500/20">
                           Active
                        </span>
                      ) : (
                        <span className="inline-flex items-center justify-center min-w-[5rem] px-2 py-1 rounded text-[10px] uppercase tracking-widest font-bold bg-orange-500/10 text-orange-400 border border-orange-500/30 shadow-inner">
                           Suspended
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
      <div className="pt-4 border-t border-brand-500/10">
         <Pagination page={page} pages={pages} onPage={setPage} />
      </div>
    </div>
  );
}
