import { useCallback, useEffect, useState } from 'react';
import { productService } from '@/services/productService';

export default function useProducts(params = {}) {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const fetchProducts = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: supabaseError } = await productService.getProducts(params);
      if (supabaseError) throw supabaseError;
      setProducts(Array.isArray(data?.data) ? data.data : []);
    } catch (err) {
      console.error('useProducts fetch error:', err);
      setError(err);
      setProducts([]);
    } finally {
      setLoading(false);
    }
  }, [JSON.stringify(params)]);

  useEffect(() => {
    let mounted = true;
    const run = async () => {
      await fetchProducts();
      if (!mounted) return;
    };
    run();
    return () => { mounted = false; };
  }, [fetchProducts]);

  return { products, loading, error, refetch: fetchProducts };
}
