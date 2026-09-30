import { useState, useEffect, useCallback } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
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
  const [loadError, setLoadError] = useState(null);
  const [retryToken, setRetryToken] = useState(0);

  const page = Number(searchParams.get('page') || 1);
  // Search comes from Navbar / hero / deep links only — not a Shop sidebar input.
  const urlSearch = (searchParams.get('search') || '').trim();
  const urlCategory = searchParams.get('category') || '';
  const urlSort = searchParams.get('sort') || '-createdAt';
  const urlMinPrice = searchParams.get('minPrice') || '';
  const urlMaxPrice = searchParams.get('maxPrice') || '';
  const urlInStock = searchParams.get('inStock') === 'true';

  const [category, setCategory] = useState(urlCategory);
  const [sort, setSort] = useState(urlSort);
  const [minPrice, setMinPrice] = useState(urlMinPrice);
  const [maxPrice, setMaxPrice] = useState(urlMaxPrice);
  const [inStock, setInStock] = useState(urlInStock);
  const debouncedMinPrice = useDebounce(minPrice);
  const debouncedMaxPrice = useDebounce(maxPrice);

  useEffect(() => {
    setCategory(urlCategory);
  }, [urlCategory]);

  useEffect(() => {
    setSort(urlSort);
  }, [urlSort]);

  useEffect(() => {
    setMinPrice(urlMinPrice);
  }, [urlMinPrice]);

  useEffect(() => {
    setMaxPrice(urlMaxPrice);
  }, [urlMaxPrice]);

  useEffect(() => {
    setInStock(urlInStock);
  }, [urlInStock]);

  // Persist refinement filters to the URL; preserve search from Navbar/hero.
  useEffect(() => {
    const next = new URLSearchParams();
    const write = (key, value) => {
      if (value) next.set(key, value);
    };

    write('search', urlSearch);
    write('category', category);
    write('sort', sort !== '-createdAt' ? sort : '');
    write('minPrice', debouncedMinPrice);
    write('maxPrice', debouncedMaxPrice);
    write('inStock', inStock ? 'true' : '');

    const prevSearch = searchParams.get('search') || '';
    const prevCategory = searchParams.get('category') || '';
    const prevSort = searchParams.get('sort') || '';
    const prevMin = searchParams.get('minPrice') || '';
    const prevMax = searchParams.get('maxPrice') || '';
    const prevStock = searchParams.get('inStock') || '';
    const filtersChanged =
      prevSearch !== (urlSearch || '') ||
      prevCategory !== (category || '') ||
      prevSort !== (sort !== '-createdAt' ? sort : '') ||
      prevMin !== (debouncedMinPrice || '') ||
      prevMax !== (debouncedMaxPrice || '') ||
      prevStock !== (inStock ? 'true' : '');

    if (!filtersChanged && page > 1) {
      next.set('page', String(page));
    }

    const nextQs = next.toString();
    const currentQs = searchParams.toString();
    if (nextQs !== currentQs) {
      setSearchParams(next, { replace: true });
    }
  }, [
    urlSearch,
    category,
    sort,
    debouncedMinPrice,
    debouncedMaxPrice,
    inStock,
    page,
    searchParams,
    setSearchParams,
  ]);

  useEffect(() => {
    productService.getCategories().then(({ data }) => setCategories(data.data));
  }, []);

  useEffect(() => {
    setLoading(true);
    setLoadError(null);
    const params = {
      page,
      limit: 12,
      sort,
      ...(urlSearch && { search: urlSearch }),
      ...(category && { category }),
      ...(debouncedMinPrice && { minPrice: debouncedMinPrice }),
      ...(debouncedMaxPrice && { maxPrice: debouncedMaxPrice }),
      ...(inStock && { inStock: 'true' }),
    };
    productService
      .getProducts(params)
      .then(({ data, error }) => {
        if (error) {
          setLoadError(error);
          setProducts([]);
          setTotal(0);
          setPages(1);
          return;
        }
        setProducts(data.data);
        setTotal(data.total);
        setPages(data.pages);
      })
      .finally(() => setLoading(false));
  }, [page, urlSearch, category, sort, debouncedMinPrice, debouncedMaxPrice, inStock, retryToken]);

  const updatePage = (n) =>
    setSearchParams((prev) => {
      const p = new URLSearchParams(prev);
      if (n > 1) p.set('page', String(n));
      else p.delete('page');
      return p;
    });

  const clearSearch = useCallback(() => {
    setSearchParams((prev) => {
      const p = new URLSearchParams(prev);
      p.delete('search');
      p.delete('page');
      return p;
    });
  }, [setSearchParams]);

  const clearAllFilters = useCallback(() => {
    setCategory('');
    setSort('-createdAt');
    setMinPrice('');
    setMaxPrice('');
    setInStock(false);
    setSearchParams({}, { replace: true });
  }, [setSearchParams]);

  const hasActiveSearch = Boolean(urlSearch);
  const emptyMessage = hasActiveSearch
    ? `No products found for “${urlSearch}”. Try a different term or clear your search.`
    : 'No pieces match your designated criteria.';

  const resultsLabel = loading
    ? 'Loading collection…'
    : loadError
      ? "We couldn't load products right now."
      : hasActiveSearch
        ? `${total} piece${total !== 1 ? 's' : ''} found for “${urlSearch}”`
        : `${total} piece${total !== 1 ? 's' : ''} found`;

  return (
    <div className="bg-[#0B0B0B] min-h-screen text-slate-200">
      <div className="section-container py-12 relative z-10">
        <div className="flex flex-col mb-12 relative">
          <div className="absolute top-0 right-10 w-64 h-64 bg-brand-500/10 rounded-full blur-[80px] pointer-events-none"></div>
          <GiBee className="text-brand-500 text-3xl mb-3 opacity-60" />
          <h1 className="font-display font-bold text-4xl text-white tracking-wide uppercase">The Collection</h1>
          <div className="w-16 h-px bg-gradient-to-r from-brand-500 to-transparent mt-4"></div>
        </div>

        <div className="flex flex-col lg:flex-row gap-10">
          <aside className="lg:w-64 shrink-0 space-y-8 bg-[#111]/80 backdrop-blur-xl p-6 rounded-2xl border border-brand-500/10 shadow-[0_10px_40px_rgba(0,0,0,0.5)] h-fit lg:sticky lg:top-28">
            <div className="flex items-center gap-2 mb-2 pb-4 border-b border-brand-500/10 text-brand-500">
              <FiFilter size={18} />
              <h3 className="font-display font-semibold uppercase tracking-widest text-sm">Refine Search</h3>
            </div>

            <div className="space-y-6">
              <div>
                <label htmlFor="shop-category" className="text-[10px] font-semibold uppercase tracking-widest text-brand-500/80 mb-3 block">
                  Category
                </label>
                <select
                  value={category}
                  onChange={(e) => setCategory(e.target.value)}
                  className="input text-sm py-2.5 bg-surface-card/60 border-brand-500/20 focus:border-brand-500/50 text-slate-300 appearance-none"
                  id="shop-category"
                >
                  <option value="">All Categories</option>
                  {categories.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label htmlFor="shop-sort" className="text-[10px] font-semibold uppercase tracking-widest text-brand-500/80 mb-3 block">
                  Sort By
                </label>
                <select
                  value={sort}
                  onChange={(e) => setSort(e.target.value)}
                  className="input text-sm py-2.5 bg-surface-card/60 border-brand-500/20 focus:border-brand-500/50 text-slate-300 appearance-none"
                  id="shop-sort"
                >
                  {SORT_OPTIONS.map((o) => (
                    <option key={o.value} value={o.value}>
                      {o.label}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-[10px] font-semibold uppercase tracking-widest text-brand-500/80 mb-3 block">
                  Price Range (KES)
                </label>
                <div className="flex gap-3">
                  <input
                    type="number"
                    placeholder="Min"
                    value={minPrice}
                    onChange={(e) => setMinPrice(e.target.value)}
                    className="input text-sm py-2.5 bg-surface-card/60 border-brand-500/20 focus:border-brand-500/50"
                  />
                  <input
                    type="number"
                    placeholder="Max"
                    value={maxPrice}
                    onChange={(e) => setMaxPrice(e.target.value)}
                    className="input text-sm py-2.5 bg-surface-card/60 border-brand-500/20 focus:border-brand-500/50"
                  />
                </div>
              </div>
              <div className="pt-2 border-t border-brand-500/10">
                <label className="flex items-center gap-3 cursor-pointer group mt-4">
                  <input
                    type="checkbox"
                    checked={inStock}
                    onChange={(e) => setInStock(e.target.checked)}
                    className="accent-brand-500 w-4 h-4 rounded border-brand-500/30 bg-[#111] focus:ring-brand-500 focus:ring-offset-[#111]"
                    id="shop-instock"
                  />
                  <span className="text-sm tracking-wide text-slate-400 group-hover:text-brand-400 transition-colors">
                    In Stock Only
                  </span>
                </label>
              </div>
              {(hasActiveSearch || category || minPrice || maxPrice || inStock || sort !== '-createdAt') && (
                <button
                  type="button"
                  onClick={clearAllFilters}
                  className="w-full text-xs uppercase tracking-widest text-slate-400 hover:text-brand-400 border border-brand-500/20 rounded-lg py-2.5 transition-colors"
                >
                  Clear filters
                </button>
              )}
            </div>
          </aside>

          <div className="flex-1">
            <div className="flex justify-between items-end mb-6 border-b border-brand-500/10 pb-4">
              <p className="text-sm text-slate-400 font-light tracking-wide">{resultsLabel}</p>
              <GiBee size={20} className="text-brand-500/30" />
            </div>

            {!loading && loadError ? (
              <div className="text-center py-20 space-y-4 text-slate-400">
                <p className="text-lg text-red-400">
                  We couldn&apos;t load products right now. Please try again.
                </p>
                <button
                  type="button"
                  onClick={() => setRetryToken((token) => token + 1)}
                  className="btn-secondary text-sm"
                >
                  Retry
                </button>
              </div>
            ) : !loading && products.length === 0 ? (
              <div className="text-center py-20 space-y-4 text-slate-400">
                <p className="text-lg text-slate-300">{emptyMessage}</p>
                <div className="flex flex-wrap items-center justify-center gap-3">
                  {hasActiveSearch && (
                    <button type="button" onClick={clearSearch} className="btn-secondary text-sm">
                      Clear search
                    </button>
                  )}
                  <button type="button" onClick={clearAllFilters} className="btn-ghost text-sm">
                    Reset filters
                  </button>
                  <Link to="/shop" className="btn-ghost text-sm">
                    Browse all products
                  </Link>
                </div>
              </div>
            ) : (
              <ProductGrid products={products} loading={loading} emptyMessage={emptyMessage} />
            )}

            <div className="mt-12">
              <Pagination page={page} pages={pages} onPage={updatePage} />
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
