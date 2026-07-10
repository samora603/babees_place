import { Link, NavLink, useNavigate } from 'react-router-dom';
import { useState } from 'react';
import { FiShoppingCart, FiHeart, FiSearch, FiUser, FiMenu, FiX } from 'react-icons/fi';
import { GiBee } from 'react-icons/gi';
import { useAuth } from '@/context/AuthContext';
import { useCart } from '@/context/CartContext';

export default function Navbar() {
  const { user, profile, logout } = useAuth();
  const { itemCount } = useCart();
  const navigate = useNavigate();
  const [menuOpen, setMenuOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');

  const handleSearch = (e) => {
    e.preventDefault();
    if (searchQuery.trim()) {
      navigate(`/shop?search=${encodeURIComponent(searchQuery.trim())}`);
      setSearchQuery('');
    }
  };

  return (
    <nav className="sticky top-0 z-50 bg-[#0B0B0B]/90 backdrop-blur-xl border-b border-brand-500/20 shadow-[0_4px_30px_rgba(212,175,55,0.05)]">
      <div className="section-container">
        <div className="flex items-center justify-between h-20 gap-4">
          {/* Logo */}
          <Link to="/" className="flex items-center gap-2 font-display font-bold text-2xl tracking-wide shrink-0 group">
            <GiBee className="text-brand-500 text-3xl group-hover:drop-shadow-[0_0_8px_rgba(212,175,55,0.8)] transition-all duration-300" />
            <span className="bg-gradient-to-r from-brand-300 via-brand-500 to-brand-400 bg-clip-text text-transparent">Babis</span>
            <span className="text-white font-light">Place</span>
          </Link>

          {/* Search bar */}
          <form onSubmit={handleSearch} className="hidden md:flex flex-1 max-w-md ml-8">
            <div className="relative w-full group">
              <FiSearch className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-400 group-focus-within:text-brand-500 transition-colors" />
              <input
                type="search"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="Search premium products..."
                className="input pl-12 py-2.5 text-sm bg-surface-card/50 hover:bg-surface-card transition-colors duration-300"
                id="navbar-search"
              />
            </div>
          </form>

          {/* Nav links (desktop) */}
          <div className="hidden md:flex items-center gap-2">
            <NavLink to="/shop" className={({ isActive }) => `btn-ghost text-sm uppercase tracking-wider font-semibold ${isActive ? 'text-brand-400' : ''}`}>
              Collection
            </NavLink>

            {user ? (
              <div className="flex items-center gap-2 ml-4 border-l border-brand-500/20 pl-6">
                <NavLink to="/wishlist" className="btn-ghost relative hover:text-brand-400 group">
                  <FiHeart size={20} className="group-hover:scale-110 transition-transform" />
                </NavLink>
                <NavLink to="/cart" className="btn-ghost relative hover:text-brand-400 group">
                  <FiShoppingCart size={20} className="group-hover:scale-110 transition-transform" />
                  {itemCount > 0 && (
                    <span className="absolute -top-1.5 -right-1.5 bg-brand-500 text-black text-[10px] rounded-full w-4 h-4 flex items-center justify-center font-bold shadow-[0_0_10px_rgba(212,175,55,0.5)]">
                      {itemCount > 9 ? '9+' : itemCount}
                    </span>
                  )}
                </NavLink>
                <div className="relative group ml-2">
                  <button className="flex items-center gap-2 pl-4 py-2 text-sm font-medium text-slate-300 hover:text-brand-400 transition-colors">
                    <div className="w-8 h-8 rounded-full bg-brand-500/10 border border-brand-500/30 flex items-center justify-center text-brand-500 group-hover:bg-brand-500 group-hover:text-black transition-all">
                       <FiUser size={16} />
                    </div>
                    <span className="hidden lg:block">{profile?.full_name?.split(' ')[0] || user?.name?.split(' ')[0] || 'Account'}</span>
                  </button>
                  <div className="absolute right-0 mt-2 w-48 bg-surface-card border border-brand-500/20 rounded-xl shadow-[0_10px_40px_rgba(0,0,0,0.5)] opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all duration-300 transform origin-top-right group-hover:scale-100 scale-95 z-50">
                    <div className="p-2 space-y-1">
                      <Link to="/profile" className="block px-4 py-2.5 rounded-lg text-sm text-slate-300 hover:text-brand-400 hover:bg-brand-500/10 transition-colors">Profile</Link>
                      <Link to="/orders" className="block px-4 py-2.5 rounded-lg text-sm text-slate-300 hover:text-brand-400 hover:bg-brand-500/10 transition-colors">My Orders</Link>
                      {profile?.role === 'admin' && (
                        <Link to="/admin/dashboard" className="block px-4 py-2.5 rounded-lg text-sm text-brand-500 font-medium hover:bg-brand-500/10 transition-colors">Admin Dashboard</Link>
                      )}
                      <div className="h-px bg-brand-500/10 my-1"></div>
                      <button onClick={logout} className="w-full text-left px-4 py-2.5 rounded-lg text-sm text-red-400 hover:bg-red-400/10 transition-colors">
                        Sign Out
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            ) : (
              <Link to="/login" className="btn-primary text-sm ml-4 shadow-[0_0_15px_rgba(212,175,55,0.15)]">Sign In</Link>
            )}
          </div>

          {/* Mobile menu toggle */}
          <button
            id="mobile-menu-btn"
            className="md:hidden text-slate-300 hover:text-brand-400 p-2"
            onClick={() => setMenuOpen(!menuOpen)}
            aria-label="Toggle menu"
          >
            {menuOpen ? <FiX size={26} /> : <FiMenu size={26} />}
          </button>
        </div>
      </div>

      {/* Mobile menu */}
      {menuOpen && (
        <div className="md:hidden bg-[#0B0B0B] border-t border-brand-500/20 px-4 py-6 space-y-4 animate-slide-up h-screen">
          <form onSubmit={handleSearch}>
            <div className="relative">
              <FiSearch className="absolute left-4 top-1/2 -translate-y-1/2 text-brand-500" />
              <input type="search" value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} placeholder="Search premium items…" className="input pl-12 py-3 text-sm bg-surface-card/80" />
            </div>
          </form>
          <div className="space-y-2 pt-4">
              <Link to="/shop" className="block py-3 px-4 rounded-xl text-slate-200 hover:bg-brand-500/10 hover:text-brand-400 font-medium transition-colors" onClick={() => setMenuOpen(false)}>Collection</Link>
              {user ? (
                <>
                  <Link to="/cart" className="block py-3 px-4 rounded-xl text-slate-200 hover:bg-brand-500/10 hover:text-brand-400 font-medium transition-colors" onClick={() => setMenuOpen(false)}>Cart ({itemCount})</Link>
                  <Link to="/wishlist" className="block py-3 px-4 rounded-xl text-slate-200 hover:bg-brand-500/10 hover:text-brand-400 font-medium transition-colors" onClick={() => setMenuOpen(false)}>Wishlist</Link>
                  <Link to="/orders" className="block py-3 px-4 rounded-xl text-slate-200 hover:bg-brand-500/10 hover:text-brand-400 font-medium transition-colors" onClick={() => setMenuOpen(false)}>My Orders</Link>
                  <Link to="/profile" className="block py-3 px-4 rounded-xl text-slate-200 hover:bg-brand-500/10 hover:text-brand-400 font-medium transition-colors" onClick={() => setMenuOpen(false)}>Profile</Link>
                  {profile?.role === 'admin' && <Link to="/admin/dashboard" className="block py-3 px-4 rounded-xl text-brand-500 font-bold hover:bg-brand-500/10 transition-colors" onClick={() => setMenuOpen(false)}>Admin Dashboard</Link>}
                  <button onClick={() => { logout(); setMenuOpen(false); }} className="w-full text-left py-3 px-4 rounded-xl text-red-400 hover:bg-red-400/10 font-medium transition-colors mt-4">Sign Out</button>
                </>
              ) : (
                <div className="pt-4">
                  <Link to="/login" className="btn-primary block text-center w-full py-3" onClick={() => setMenuOpen(false)}>Sign In</Link>
                </div>
              )}
          </div>
        </div>
      )}
    </nav>
  );
}
