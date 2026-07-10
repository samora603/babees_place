import { Link } from 'react-router-dom';
import { FiInstagram, FiTwitter, FiFacebook, FiMail } from 'react-icons/fi';
import { GiBee } from 'react-icons/gi';

export default function Footer() {
  return (
    <footer className="bg-[#0B0B0B] border-t border-brand-500/20 pt-16 relative overflow-hidden">
      {/* Decorative background glow */}
      <div className="absolute bottom-0 right-0 w-[40rem] h-[40rem] bg-brand-500/5 rounded-full blur-[100px] pointer-events-none"></div>

      <div className="section-container pb-8 relative z-10">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-12 mb-12">
          {/* Brand */}
          <div className="md:col-span-1">
            <Link to="/" className="flex items-center gap-2 font-display font-bold text-2xl tracking-wide mb-4 group inline-flex">
              <GiBee className="text-brand-500 text-3xl group-hover:drop-shadow-[0_0_8px_rgba(212,175,55,0.8)] transition-all duration-300" />
              <span className="bg-gradient-to-r from-brand-300 via-brand-500 to-brand-400 bg-clip-text text-transparent">Babis</span>
              <span className="text-white font-light">Place</span>
            </Link>
            <p className="text-slate-400 text-sm leading-relaxed mb-6 font-light">
              Elevating the campus lifestyle. The finest collections curated for you, exclusively via M-Pesa.
            </p>
            <div className="flex gap-4">
              {[FiInstagram, FiTwitter, FiFacebook].map((Icon, i) => (
                <a key={i} href="#" className="w-10 h-10 rounded-full border border-brand-500/20 flex items-center justify-center text-brand-500 hover:bg-brand-500 hover:text-black hover:scale-110 hover:shadow-[0_0_15px_rgba(212,175,55,0.4)] transition-all duration-300">
                  <Icon size={18} />
                </a>
              ))}
            </div>
          </div>

          {/* Shop */}
          <div>
            <h4 className="font-display font-semibold text-lg text-white mb-6 flex items-center gap-2">
               <span className="w-8 h-px bg-brand-500"></span> Collection
            </h4>
            <ul className="space-y-3">
              {[['All Products', '/shop'], ['New Arrivals', '/shop?sort=-createdAt'], ['Best Sellers', '/shop?sort=-soldCount']].map(([label, href]) => (
                <li key={href}><Link to={href} className="text-sm text-slate-400 hover:text-brand-400 hover:pl-2 transition-all duration-300">{label}</Link></li>
              ))}
            </ul>
          </div>

          {/* Account */}
          <div>
            <h4 className="font-display font-semibold text-lg text-white mb-6 flex items-center gap-2">
               <span className="w-8 h-px bg-brand-500"></span> Client 
            </h4>
            <ul className="space-y-3">
              {[['My Orders', '/orders'], ['My Profile', '/profile'], ['Wishlist', '/wishlist'], ['Cart', '/cart']].map(([label, href]) => (
                <li key={href}><Link to={href} className="text-sm text-slate-400 hover:text-brand-400 hover:pl-2 transition-all duration-300">{label}</Link></li>
              ))}
            </ul>
          </div>

          {/* Contact */}
          <div>
            <h4 className="font-display font-semibold text-lg text-white mb-6 flex items-center gap-2">
               <span className="w-8 h-px bg-brand-500"></span> Service
            </h4>
            <ul className="space-y-4 text-sm text-slate-400">
              <li className="flex items-center gap-3 group cursor-pointer">
                  <div className="w-8 h-8 rounded-full bg-surface-card flex items-center justify-center border border-brand-500/20 group-hover:border-brand-500 transition-colors">
                      <FiMail size={14} className="text-brand-500" /> 
                  </div>
                  <span className="group-hover:text-brand-400 transition-colors">concierge@babisplace.co.ke</span>
              </li>
              <li className="flex items-start gap-3">
                  <span className="text-brand-500 mt-1">✧</span>
                  <span>Exclusive Campus Pickup</span>
              </li>
              <li className="flex items-start gap-3">
                 <span className="text-brand-500 mt-1">✧</span>
                 <span>Secure M-Pesa Integration</span>
              </li>
            </ul>
          </div>
        </div>

        <div className="border-t border-brand-500/20 pt-8 flex flex-col md:flex-row justify-between items-center gap-4 text-xs font-light tracking-wide text-slate-500">
          <p>© {new Date().getFullYear()} BABIS PLACE. ALL RIGHTS RESERVED.</p>
          <div className="flex items-center gap-2">
              <GiBee size={14} className="text-brand-500/50" />
              <span>LUXURY EDITION</span>
          </div>
        </div>
      </div>
    </footer>
  );
}
