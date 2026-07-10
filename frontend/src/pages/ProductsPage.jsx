import React from 'react';
import { Link } from 'react-router-dom';
import useProducts from '@/hooks/useProducts';

export default function ProductsPage() {
  const { products, loading, error } = useProducts({ limit: 20 });

  if (loading) return <div className="p-8">Loading products…</div>;
  if (error) return <div className="p-8 text-red-400">Error loading products.</div>;

  return (
    <div className="p-8">
      <h2 className="text-2xl font-bold mb-4">Products</h2>

      <ul className="space-y-4">
        {products.length === 0 && <li>No products found.</li>}

        {products.map((p) => {
          const id = p.id || p._id || p.product_id;
          return (
            <li key={id} className="p-4 border rounded bg-[#0b0b0b]/50">
              <Link to={`/product/${id}`} className="block">
                <div className="font-semibold">
                  {p.name || p.title || 'Untitled'}
                </div>

                <div className="text-sm text-slate-400">
                  KES {p.price ?? '—'}
                </div>
              </Link>
            </li>
          );
        })}
      </ul>
    </div>
  );
}