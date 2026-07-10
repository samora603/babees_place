import { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import { productService } from '@/services/productService';
import ProductGrid from '@/components/products/ProductGrid';
import Pagination from '@/components/ui/Pagination';
import useDebounce from '@/hooks/useDebounce';
import { SORT_OPTIONS } from '@/utils/constants';
import { FiFilter } from 'react-icons/fi';
import { GiBee } from 'react-icons/gi';

export default function Shop() {
  const [searchParams, setSearchParams] = useSearchParams();
  const [products, setProducts] = useState([]);
  const [categories, setCategories] = useState([]);
  const [total, setTotal] = useState(0);
  const [pages, setPages] = useState(1);
  const [loading, setLoading] = useState(true);

  const page = Number(searchParams.get('page') || 1);
  const [search, setSearch] = useState(searchParams.get('search') || '');
  const [category, setCategory] = useState(searchParams.get('category') || '');
  const [sort, setSort] = useState(searchParams.get('sort') || '-createdAt');
  const [minPrice, setMinPrice] = useState('');
  const [maxPrice, setMaxPrice] = useState('');
  const [inStock, setInStock] = useState(false);
  const debouncedSearch = useDebounce(search);

  useEffect(() => { productService.getCategories().then(({ data }) => setCategories(data.data)); }, []);

  useEffect(() => {
    setLoading(true);
    const params = { page, limit: 12, sort, ...(debouncedSearch && { search: debouncedSearch }), ...(category && { category }), ...(minPrice && { minPrice }), ...(maxPrice && { maxPrice }), ...(inStock && { inStock: 'true' }) };
    productService.getProducts(params).then(({ data }) => {
      setProducts(data.data); setTotal(data.total); setPages(data.pages);
    }).finally(() => setLoading(false));
  }, [page, debouncedSearch, category, sort, minPrice, maxPrice, inStock]);

  const updatePage = (n) => setSearchParams((prev) => { const p = new URLSearchParams(prev); p.set('page', n); return p; });

  return (
    <div className="bg-[#0B0B0B] min-h-screen text-slate-200">
      <div className="section-container py-12 relative z-10">
        
        {/* Page Header */}
        <div className="flex flex-col mb-12 relative">
           <div className="absolute top-0 right-10 w-64 h-64 bg-brand-500/10 rounded-full blur-[80px] pointer-events-none"></div>
           <GiBee className="text-brand-500 text-3xl mb-3 opacity-60" />
           <h1 className="font-display font-bold text-4xl text-white tracking-wide uppercase">The Collection</h1>
           <div className="w-16 h-px bg-gradient-to-r from-brand-500 to-transparent mt-4"></div>
        </div>

        <div className="flex flex-col lg:flex-row gap-10">
          {/* Filters sidebar */}
          <aside className="lg:w-64 shrink-0 space-y-8 bg-[#111]/80 backdrop-blur-xl p-6 rounded-2xl border border-brand-500/10 shadow-[0_10px_40px_rgba(0,0,0,0.5)] h-fit sticky top-28">
            <div className="flex items-center gap-2 mb-2 pb-4 border-b border-brand-500/10 text-brand-500">
               <FiFilter size={18} />
               <h3 className="font-display font-semibold uppercase tracking-widest text-sm">Refine Search</h3>
            </div>
            
            <div className="space-y-6">
              <div>
                <label className="text-[10px] font-semibold uppercase tracking-widest text-brand-500/80 mb-3 block">Search Item</label>
                <input type="search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search..." className="input text-sm py-2.5 bg-surface-card/60 border-brand-500/20 focus:border-brand-500/50 transition-colors" id="shop-search" />
              </div>
              <div>
                <label className="text-[10px] font-semibold uppercase tracking-widest text-brand-500/80 mb-3 block">Category</label>
                <select value={category} onChange={(e) => setCategory(e.target.value)} className="input text-sm py-2.5 bg-surface-card/60 border-brand-500/20 focus:border-brand-500/50 text-slate-300 appearance-none" id="shop-category">
                  <option value="">All Categories</option>
                  {categories.map((c) => <option key={c._id} value={c._id}>{c.name}</option>)}
                </select>
              </div>
              <div>
                <label className="text-[10px] font-semibold uppercase tracking-widest text-brand-500/80 mb-3 block">Sort By</label>
                <select value={sort} onChange={(e) => setSort(e.target.value)} className="input text-sm py-2.5 bg-surface-card/60 border-brand-500/20 focus:border-brand-500/50 text-slate-300 appearance-none" id="shop-sort">
                  {SORT_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
                </select>
              </div>
              <div>
                <label className="text-[10px] font-semibold uppercase tracking-widest text-brand-500/80 mb-3 block">Price Range (KES)</label>
                <div className="flex gap-3">
                  <input type="number" placeholder="Min" value={minPrice} onChange={(e) => setMinPrice(e.target.value)} className="input text-sm py-2.5 bg-surface-card/60 border-brand-500/20 focus:border-brand-500/50" />
                  <input type="number" placeholder="Max" value={maxPrice} onChange={(e) => setMaxPrice(e.target.value)} className="input text-sm py-2.5 bg-surface-card/60 border-brand-500/20 focus:border-brand-500/50" />
                </div>
              </div>
              <div className="pt-2 border-t border-brand-500/10">
                <label className="flex items-center gap-3 cursor-pointer group mt-4">
                  <input type="checkbox" checked={inStock} onChange={(e) => setInStock(e.target.checked)} className="accent-brand-500 w-4 h-4 rounded border-brand-500/30 bg-[#111] focus:ring-brand-500 focus:ring-offset-[#111]" id="shop-instock" />
                  <span className="text-sm tracking-wide text-slate-400 group-hover:text-brand-400 transition-colors">In Stock Only</span>
                </label>
              </div>
            </div>
          </aside>

          {/* Products */}
          <div className="flex-1">
            <div className="flex justify-between items-end mb-6 border-b border-brand-500/10 pb-4">
               <p className="text-sm text-slate-400 font-light tracking-wide">{loading ? 'Loading collection…' : `${total} piece${total !== 1 ? 's' : ''} found`}</p>
               <GiBee size={20} className="text-brand-500/30" />
            </div>
            
            <ProductGrid products={products} loading={loading} emptyMessage="No pieces match your designated criteria." />
            
            <div className="mt-12">
               <Pagination page={page} pages={pages} onPage={updatePage} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
