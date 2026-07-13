/**
 * Pure recommendation ranking helpers (no I/O).
 * Used by recommendationService / buyAgainService.
 */

/** Relative price band around a seed product (±25%). */
export const PRICE_RANGE_RATIO = 0.25;

/** Score weights for multi-signal ranking. */
export const SCORE_WEIGHTS = {
  sameCategory: 40,
  sameBrand: 25,
  similarPrice: 20,
  bestSeller: 15,
  newArrival: 10,
};

/**
 * Effective unit price for comparisons (discount when present).
 * @param {object} product
 * @returns {number}
 */
export function getEffectivePrice(product) {
  if (!product) return 0;
  const discount = Number(product.discount_price);
  const price = Number(product.price);
  if (Number.isFinite(discount) && discount > 0 && discount < price) return discount;
  return Number.isFinite(price) ? price : 0;
}

/**
 * Optional brand field — schema has no brand column today; scores 0 when absent.
 * @param {object} product
 * @returns {string | null}
 */
export function getBrandSignal(product) {
  const brand = product?.brand;
  if (typeof brand === 'string' && brand.trim()) return brand.trim().toLowerCase();
  return null;
}

/**
 * @param {object} product
 * @returns {string | null}
 */
export function getCategoryId(product) {
  return product?.category_id || product?.categories?.id || null;
}

/**
 * @param {Iterable<string|null|undefined>} ids
 * @returns {Set<string>}
 */
export function toExcludeSet(ids = []) {
  return new Set([...ids].filter(Boolean).map(String));
}

/**
 * Remove duplicates by product id (first wins).
 * @param {object[]} products
 * @returns {object[]}
 */
export function dedupeProducts(products = []) {
  const seen = new Set();
  const out = [];
  for (const p of products) {
    const id = p?.id || p?._id;
    if (!id || seen.has(String(id))) continue;
    seen.add(String(id));
    out.push(p);
  }
  return out;
}

/**
 * Drop excluded / inactive / out-of-stock products.
 * @param {object[]} products
 * @param {Set<string>|string[]} excludeIds
 * @param {{ requireInStock?: boolean }} [opts]
 */
export function filterRecommendable(products = [], excludeIds = [], opts = {}) {
  const exclude = excludeIds instanceof Set ? excludeIds : toExcludeSet(excludeIds);
  const requireInStock = opts.requireInStock !== false;

  return products.filter((p) => {
    const id = p?.id || p?._id;
    if (!id || exclude.has(String(id))) return false;
    if (p.is_active === false) return false;
    if (requireInStock && Number(p.stock ?? 0) <= 0) return false;
    return true;
  });
}

/**
 * Score a candidate against a recommendation context.
 *
 * @param {object} candidate
 * @param {object} context
 * @param {object} [context.seed] current / reference product
 * @param {Set<string>} [context.bestSellerIds]
 * @param {Set<string>} [context.newArrivalIds]
 * @param {Map<string, number>} [context.bestSellerRanks] id → rank boost 0–1
 * @returns {{ score: number, reasons: string[] }}
 */
export function scoreCandidate(candidate, context = {}) {
  const reasons = [];
  let score = 0;
  const seed = context.seed || null;
  const candidateId = String(candidate?.id || candidate?._id || '');

  if (seed) {
    const seedCat = getCategoryId(seed);
    const candCat = getCategoryId(candidate);
    if (seedCat && candCat && String(seedCat) === String(candCat)) {
      score += SCORE_WEIGHTS.sameCategory;
      reasons.push('same_category');
    }

    const seedBrand = getBrandSignal(seed);
    const candBrand = getBrandSignal(candidate);
    if (seedBrand && candBrand && seedBrand === candBrand) {
      score += SCORE_WEIGHTS.sameBrand;
      reasons.push('same_brand');
    }

    const seedPrice = getEffectivePrice(seed);
    const candPrice = getEffectivePrice(candidate);
    if (seedPrice > 0 && candPrice > 0) {
      const low = seedPrice * (1 - PRICE_RANGE_RATIO);
      const high = seedPrice * (1 + PRICE_RANGE_RATIO);
      if (candPrice >= low && candPrice <= high) {
        score += SCORE_WEIGHTS.similarPrice;
        reasons.push('similar_price');
      }
    }
  }

  if (context.bestSellerIds?.has(candidateId)) {
    const rankBoost = context.bestSellerRanks?.get(candidateId) ?? 1;
    score += SCORE_WEIGHTS.bestSeller * rankBoost;
    reasons.push('best_seller');
  }

  if (context.newArrivalIds?.has(candidateId)) {
    score += SCORE_WEIGHTS.newArrival;
    reasons.push('new_arrival');
  }

  return { score, reasons };
}

/**
 * Rank candidates; never includes the seed product; dedupes.
 *
 * @param {object[]} candidates
 * @param {object} context
 * @param {number} [limit=12]
 * @returns {Array<object & { recommendationScore: number, recommendationReasons: string[] }>}
 */
export function rankRecommendations(candidates = [], context = {}, limit = 12) {
  const seedId = context.seed?.id || context.seed?._id;
  const exclude = toExcludeSet([
    ...(context.excludeIds || []),
    seedId,
  ]);

  const filtered = filterRecommendable(candidates, exclude);
  const scored = filtered.map((product) => {
    const { score, reasons } = scoreCandidate(product, context);
    return {
      ...product,
      recommendationScore: score,
      recommendationReasons: reasons,
    };
  });

  scored.sort((a, b) => {
    if (b.recommendationScore !== a.recommendationScore) {
      return b.recommendationScore - a.recommendationScore;
    }
    // Tie-break: newer first
    return String(b.created_at || '').localeCompare(String(a.created_at || ''));
  });

  return dedupeProducts(scored).slice(0, Math.max(0, limit));
}

/**
 * Aggregate buy-again frequency from order line items.
 * Most frequently purchased first; ties by most recent purchase.
 *
 * @param {Array<{ product_id?: string, quantity?: number, created_at?: string }>} lineItems
 * @returns {Array<{ productId: string, quantity: number, lastPurchasedAt: string|null }>}
 */
export function aggregateBuyAgainFrequency(lineItems = []) {
  /** @type {Map<string, { productId: string, quantity: number, lastPurchasedAt: string|null }>} */
  const map = new Map();

  for (const item of lineItems) {
    const productId = item?.product_id;
    if (!productId) continue;
    const qty = Number(item.quantity) || 0;
    if (qty <= 0) continue;

    const existing = map.get(productId);
    const purchasedAt = item.created_at || item.orderCreatedAt || null;

    if (!existing) {
      map.set(productId, {
        productId,
        quantity: qty,
        lastPurchasedAt: purchasedAt,
      });
      continue;
    }

    existing.quantity += qty;
    if (
      purchasedAt &&
      (!existing.lastPurchasedAt ||
        String(purchasedAt) > String(existing.lastPurchasedAt))
    ) {
      existing.lastPurchasedAt = purchasedAt;
    }
  }

  return [...map.values()].sort((a, b) => {
    if (b.quantity !== a.quantity) return b.quantity - a.quantity;
    return String(b.lastPurchasedAt || '').localeCompare(String(a.lastPurchasedAt || ''));
  });
}

/**
 * Cross-sell: prefer same category / brand as cart seeds, then bestsellers.
 * @param {object[]} candidates
 * @param {object[]} cartProducts seed products currently in cart
 * @param {object} extras bestSellerIds / newArrivalIds
 * @param {number} limit
 */
export function rankCrossSell(candidates, cartProducts = [], extras = {}, limit = 8) {
  const excludeIds = cartProducts.map((p) => p?.id || p?._id).filter(Boolean);
  // Score against each cart seed and take the max score
  const exclude = toExcludeSet(excludeIds);
  const filtered = filterRecommendable(candidates, exclude);

  const scored = filtered.map((product) => {
    let best = { score: 0, reasons: [] };
    if (cartProducts.length === 0) {
      best = scoreCandidate(product, extras);
    } else {
      for (const seed of cartProducts) {
        const result = scoreCandidate(product, { ...extras, seed });
        if (result.score > best.score) best = result;
      }
    }
    return {
      ...product,
      recommendationScore: best.score,
      recommendationReasons: best.reasons,
    };
  });

  scored.sort((a, b) => b.recommendationScore - a.recommendationScore);
  return dedupeProducts(scored).slice(0, Math.max(0, limit));
}
