import { supabase } from '@/lib/supabaseClient';
import { productService } from '@/services/productService';
import {
  dedupeProducts,
  filterRecommendable,
  rankCrossSell,
  rankRecommendations,
  toExcludeSet,
} from '@/models/recommendations';

const CATALOG_FETCH_LIMIT = 48;
const DEFAULT_LIMIT = 12;

/** @type {Map<string, { expires: number, value: unknown }>} */
const cache = new Map();
const CACHE_TTL_MS = 60_000;

function cacheGet(key) {
  const hit = cache.get(key);
  if (!hit) return undefined;
  if (Date.now() > hit.expires) {
    cache.delete(key);
    return undefined;
  }
  return hit.value;
}

function cacheSet(key, value, ttl = CACHE_TTL_MS) {
  cache.set(key, { value, expires: Date.now() + ttl });
}

/** Test helper */
export function clearRecommendationCache() {
  cache.clear();
}

async function fetchCatalogPool(params = {}) {
  const { data, error } = await productService.getProducts({
    limit: CATALOG_FETCH_LIMIT,
    inStock: true,
    ...params,
  });
  if (error) return [];
  return data?.data || [];
}

/**
 * Best-seller ids via SECURITY DEFINER RPC (migration 015).
 * Falls back to featured products when RPC is unavailable.
 * @param {number} limit
 * @returns {Promise<{ ids: string[], ranks: Map<string, number>, products: object[] }>}
 */
export async function getBestSellerSignals(limit = DEFAULT_LIMIT) {
  const cacheKey = `bestsellers:${limit}`;
  const cached = cacheGet(cacheKey);
  if (cached) return cached;

  try {
    const { data, error } = await supabase.rpc('get_bestseller_product_ids', {
      p_limit: limit,
    });

    if (!error && Array.isArray(data) && data.length > 0) {
      const ids = data.map((row) => String(row.product_id)).filter(Boolean);
      const ranks = new Map(
        ids.map((id, index) => [id, 1 - index / Math.max(ids.length, 1)]),
      );

      const products = [];
      for (const id of ids) {
        const { data: res } = await productService.getProductById(id);
        const product = res?.data;
        if (product && product.is_active !== false) products.push(product);
      }

      const result = {
        ids,
        ranks,
        products: filterRecommendable(products, []),
      };
      cacheSet(cacheKey, result);
      return result;
    }
  } catch (err) {
    console.warn('recommendationService.getBestSellerSignals RPC failed:', err);
  }

  // Fallback: featured / newest as popularity proxy
  const featured = await fetchCatalogPool({ featured: true, limit });
  const pool = featured.length > 0 ? featured : await fetchCatalogPool({ sort: '-createdAt', limit });
  const ids = pool.map((p) => String(p.id));
  const ranks = new Map(ids.map((id, index) => [id, 1 - index / Math.max(ids.length, 1)]));
  const result = { ids, ranks, products: pool };
  cacheSet(cacheKey, result, 30_000);
  return result;
}

/**
 * Newest active products.
 * @param {number} [limit=12]
 */
export async function getNewArrivals(limit = DEFAULT_LIMIT) {
  const cacheKey = `new:${limit}`;
  const cached = cacheGet(cacheKey);
  if (cached) return cached;

  const products = await fetchCatalogPool({ sort: '-createdAt', limit });
  const result = filterRecommendable(products, []).slice(0, limit);
  cacheSet(cacheKey, result);
  return result;
}

/**
 * Trending ≈ bestsellers (with featured fallback).
 * @param {number} [limit=12]
 */
export async function getTrendingProducts(limit = DEFAULT_LIMIT) {
  const { products } = await getBestSellerSignals(limit);
  return products.slice(0, limit);
}

/**
 * Personalized / seed-based recommendations.
 *
 * @param {object} [options]
 * @param {object} [options.seed] current product
 * @param {string[]} [options.excludeIds]
 * @param {number} [options.limit]
 * @param {string} [options.preferredCategoryId] from recently viewed / prefs
 */
export async function getRecommendations(options = {}) {
  const limit = options.limit ?? DEFAULT_LIMIT;
  const seed = options.seed || null;
  const excludeIds = [...(options.excludeIds || [])];
  if (seed?.id) excludeIds.push(seed.id);

  const categoryId =
    options.preferredCategoryId ||
    seed?.category_id ||
    seed?.categories?.id ||
    null;

  const [sameCategoryPool, catalogPool, bestSellers, newArrivals] = await Promise.all([
    categoryId
      ? fetchCatalogPool({ category: categoryId, limit: CATALOG_FETCH_LIMIT })
      : Promise.resolve([]),
    fetchCatalogPool({ sort: '-createdAt', limit: CATALOG_FETCH_LIMIT }),
    getBestSellerSignals(limit),
    getNewArrivals(limit),
  ]);

  const candidates = dedupeProducts([
    ...sameCategoryPool,
    ...catalogPool,
    ...bestSellers.products,
    ...newArrivals,
  ]);

  const newArrivalIds = toExcludeSet(newArrivals.map((p) => p.id));

  return rankRecommendations(
    candidates,
    {
      seed,
      excludeIds,
      bestSellerIds: toExcludeSet(bestSellers.ids),
      bestSellerRanks: bestSellers.ranks,
      newArrivalIds,
    },
    limit,
  );
}

/**
 * Home "Recommended For You" — uses recently viewed category affinity when available.
 * @param {object[]} [recentlyViewed]
 * @param {number} [limit]
 */
export async function getRecommendedForYou(recentlyViewed = [], limit = DEFAULT_LIMIT) {
  const recent = Array.isArray(recentlyViewed) ? recentlyViewed : [];
  const seed = recent[0] || null;
  const excludeIds = recent.map((p) => p.id).filter(Boolean);

  // Prefer category of most recent view
  const preferredCategoryId =
    recent.find((p) => p.category_id || p.categories?.id)?.category_id ||
    recent.find((p) => p.categories?.id)?.categories?.id ||
    null;

  if (seed || preferredCategoryId) {
    return getRecommendations({
      seed,
      preferredCategoryId,
      excludeIds,
      limit,
    });
  }

  // Cold start: mix trending + new
  const [trending, arrivals] = await Promise.all([
    getTrendingProducts(limit),
    getNewArrivals(limit),
  ]);
  return dedupeProducts([...trending, ...arrivals]).slice(0, limit);
}

/**
 * Cart cross-sell — complementary products not already in cart.
 * @param {Array<{ product?: object, product_id?: string }>} cartItems
 * @param {number} [limit=8]
 */
export async function getCartCrossSell(cartItems = [], limit = 8) {
  const cartProducts = (cartItems || [])
    .map((item) => item.product || item)
    .filter((p) => p && (p.id || p._id));

  const excludeIds = cartProducts.map((p) => p.id || p._id).filter(Boolean);
  const categoryIds = [
    ...new Set(
      cartProducts
        .map((p) => p.category_id || p.categories?.id)
        .filter(Boolean)
        .map(String),
    ),
  ];

  const categoryPools = await Promise.all(
    categoryIds.slice(0, 3).map((category) =>
      fetchCatalogPool({ category, limit: 24 }),
    ),
  );

  const [catalogPool, bestSellers] = await Promise.all([
    fetchCatalogPool({ sort: '-createdAt', limit: 32 }),
    getBestSellerSignals(12),
  ]);

  const candidates = dedupeProducts([
    ...categoryPools.flat(),
    ...catalogPool,
    ...bestSellers.products,
  ]);

  return rankCrossSell(
    candidates,
    cartProducts,
    {
      bestSellerIds: toExcludeSet(bestSellers.ids),
      bestSellerRanks: bestSellers.ranks,
      excludeIds,
    },
    limit,
  );
}

/**
 * Lightweight empty-state suggestions (trending / new).
 * @param {number} [limit=8]
 */
export async function getExploreSuggestions(limit = 8) {
  const [trending, arrivals] = await Promise.all([
    getTrendingProducts(limit),
    getNewArrivals(limit),
  ]);
  return dedupeProducts([...trending, ...arrivals]).slice(0, limit);
}

export const recommendationService = {
  getRecommendations,
  getRecommendedForYou,
  getTrendingProducts,
  getNewArrivals,
  getCartCrossSell,
  getExploreSuggestions,
  getBestSellerSignals,
  clearRecommendationCache,
};
