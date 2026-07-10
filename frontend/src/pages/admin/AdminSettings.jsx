import { GiBee } from 'react-icons/gi';
import { FiSettings, FiSliders } from 'react-icons/fi';

export default function AdminSettings() {
  return (
    <div className="space-y-8 bg-[#0B0B0B] min-h-full pb-12">
      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-4 border-b border-brand-500/10 pb-6 relative">
        <div className="absolute top-0 right-0 w-40 h-40 bg-brand-500/5 rounded-full blur-[60px] pointer-events-none"></div>
        <div>
          <h1 className="font-display font-bold text-3xl text-white tracking-wide uppercase flex items-center gap-3">
             <GiBee className="text-brand-500/80" /> System Preferences
          </h1>
          <p className="text-sm text-slate-400 font-light mt-1">Configure global platform parameters</p>
        </div>
      </div>

      <div className="max-w-3xl">
        <div className="bg-[#111] p-10 rounded-2xl border border-brand-500/10 shadow-[0_10px_30px_rgba(0,0,0,0.5)] flex flex-col items-center justify-center text-center relative overflow-hidden h-96">
           <div className="absolute inset-0 bg-[url('data:image/svg+xml,%3Csvg width=\'40\' height=\'40\' viewBox=\'0 0 40 40\' xmlns=\'http://www.w3.org/2000/svg\'%3E%3Cpath d=\'M20 0l20 10v20L20 40 0 30V10z\' fill=\'none\' stroke=\'%23D4AF37\' stroke-width=\'1\' stroke-opacity=\'0.03\'/%3E%3C/svg%3E')] opacity-50 pointer-events-none"></div>
           
           <div className="w-20 h-20 rounded-2xl bg-[#0A0A0A] border border-brand-500/20 shadow-[0_0_20px_rgba(212,175,55,0.1)] flex items-center justify-center text-brand-500 mb-6 relative z-10">
              <FiSliders size={32} />
           </div>
           
           <h2 className="font-display font-semibold text-xl text-white tracking-wide mb-3 relative z-10">Configuration Module Offline</h2>
           <p className="text-sm text-slate-400 max-w-md mx-auto leading-relaxed relative z-10">
              Advanced platform parameters, including delivery routing variables, OTP authentication settings, and notification protocols, are currently under maintenance.
           </p>
           
           <div className="mt-8 inline-flex items-center gap-2 px-4 py-2 rounded-full border border-brand-500/20 bg-brand-500/5 text-xs uppercase tracking-widest font-semibold text-brand-500/80 relative z-10">
              <span className="w-1.5 h-1.5 rounded-full bg-brand-500 animate-pulse"></span> Pending Integration
           </div>
        </div>
      </div>
    </div>
  );
}
