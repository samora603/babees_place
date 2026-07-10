import { Outlet, NavLink, Link } from 'react-router-dom';
import {
  FiGrid, FiPackage, FiShoppingBag, FiUsers, FiBarChart2,
  FiMapPin, FiSettings, FiLogOut, FiAlertCircle,
} from 'react-icons/fi';
import { GiBee } from 'react-icons/gi';
import { useAuth } from '@/context/AuthContext';

const navItems = [
  { to: '/admin/dashboard',        icon: FiGrid,       label: 'Command Center' },
  { to: '/admin/orders',           icon: FiShoppingBag,label: 'Acquisitions'   },
  { to: '/admin/products',         icon: FiPackage,    label: 'Collection'     },
  { to: '/admin/inventory',        icon: FiBarChart2,  label: 'Inventory'      },
  { to: '/admin/users',            icon: FiUsers,      label: 'Clients'        },
  { to: '/admin/pickup-locations', icon: FiMapPin,     label: 'Boutiques'      },
  { to: '/admin/settings',         icon: FiSettings,   label: 'Preferences'    },
];

export default function AdminLayout() {
  const { logout } = useAuth();

  return (
    <div className="flex h-screen bg-[#0B0B0B] overflow-hidden text-slate-200">
      {/* Sidebar */}
      <aside className="w-72 bg-[#111] border-r border-brand-500/10 flex flex-col shrink-0 relative overflow-hidden shadow-[10px_0_30px_rgba(0,0,0,0.5)] z-20">
        <div className="absolute top-0 right-0 w-64 h-64 bg-brand-500/5 rounded-full blur-[80px] pointer-events-none"></div>
        <div className="p-6 border-b border-brand-500/10 relative z-10">
          <Link to="/" className="flex items-center gap-3 font-display font-bold text-2xl tracking-wide group">
            <GiBee className="text-brand-500 text-3xl group-hover:drop-shadow-[0_0_8px_rgba(212,175,55,0.8)] transition-all duration-300" />
            <span className="bg-gradient-to-r from-brand-300 via-brand-500 to-brand-400 bg-clip-text text-transparent">Babis</span>
            <span className="text-white font-light">Place</span>
          </Link>
          <div className="mt-3 flex items-center gap-2">
             <div className="w-1.5 h-1.5 rounded-full bg-brand-500 animate-pulse"></div>
             <p className="text-[10px] uppercase tracking-[0.2em] font-semibold text-brand-500/80">Executive Suite</p>
          </div>
        </div>

        <nav className="flex-1 py-6 px-4 space-y-2 overflow-y-auto relative z-10 scrollbar-hide">
          <p className="text-[10px] font-semibold uppercase tracking-[0.15em] text-slate-500 mb-4 px-3">Administration</p>
          {navItems.map(({ to, icon: Icon, label }) => (
            <NavLink
              key={to}
              to={to}
              id={`admin-nav-${label.toLowerCase().replace(/\s+/g, '-')}`}
              className={({ isActive }) =>
                `flex items-center gap-4 px-4 py-3 rounded-xl text-sm font-medium transition-all duration-300 group overflow-hidden relative ${
                  isActive
                    ? 'bg-brand-500 text-black border-transparent shadow-[0_0_15px_rgba(212,175,55,0.4)]'
                    : 'text-slate-400 hover:text-brand-400 hover:bg-brand-500/5 border border-transparent hover:border-brand-500/20'
                }`
              }
            >
              {({ isActive }) => (
                <>
                  {isActive && <div className="absolute inset-0 bg-gradient-to-r from-white/20 to-transparent pointer-events-none"></div>}
                  <Icon size={20} className={`shrink-0 transition-transform ${isActive ? '' : 'group-hover:scale-110'}`} />
                  <span className="tracking-wide">{label}</span>
                </>
              )}
            </NavLink>
          ))}
        </nav>

        <div className="p-5 border-t border-brand-500/10 bg-[#0A0A0A] relative z-10">
          <button
            onClick={logout}
            className="flex items-center gap-3 w-full px-4 py-3 text-sm font-medium text-slate-400 hover:text-brand-500 border border-transparent hover:border-brand-500/30 rounded-xl hover:bg-brand-500/5 transition-all duration-300"
          >
            <FiLogOut size={18} /> <span className="uppercase tracking-widest text-[11px] font-semibold">Terminate Session</span>
          </button>
        </div>
      </aside>

      {/* Main content */}
      <div className="flex-1 flex flex-col overflow-hidden bg-[#0A0A0A]">
        <header className="bg-[#111]/80 backdrop-blur-xl border-b border-brand-500/10 px-8 py-5 flex items-center justify-between shrink-0 shadow-sm relative z-10">
          <h1 className="font-display font-semibold text-lg text-white tracking-widest uppercase flex items-center gap-3">
             <span className="w-1.5 h-1.5 rounded-full bg-brand-500"></span> Control Panel
          </h1>
          <Link to="/" className="text-xs uppercase tracking-widest font-semibold text-slate-400 hover:text-brand-500 transition-colors flex items-center gap-2 group">
             View Protocol <span className="group-hover:translate-x-1 transition-transform">→</span>
          </Link>
        </header>
        <main className="flex-1 overflow-y-auto w-full">
           <div className="mx-auto max-w-7xl">
              <Outlet />
           </div>
        </main>
      </div>
    </div>
  );
}
