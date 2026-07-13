import { supabase } from '@/lib/supabaseClient';

/**
 * Fetch profiles by id and return a Map for O(1) lookup.
 * Used because orders.user_id → auth.users, not profiles — PostgREST
 * cannot embed `profiles` on orders without a direct FK (PGRST200).
 *
 * @param {string[]} userIds
 * @returns {Promise<Map<string, { id: string, full_name: string|null, email: string|null, phone: string|null }>>}
 */
export async function fetchProfilesByIds(userIds = []) {
  const unique = [...new Set((userIds || []).filter(Boolean))];
  const map = new Map();
  if (unique.length === 0) return map;

  const { data, error } = await supabase
    .from('profiles')
    .select('id, full_name, email, phone')
    .in('id', unique);

  if (error) {
    console.error('profileLookup.fetchProfilesByIds error:', error);
    return map;
  }

  for (const row of data || []) {
    map.set(row.id, row);
  }
  return map;
}

/**
 * Attach `profiles` onto order row(s) via a separate profiles query.
 * @param {object|object[]|null} rows
 * @returns {Promise<object|object[]|null>}
 */
export async function attachProfilesToOrders(rows) {
  if (!rows) return rows;

  const list = Array.isArray(rows) ? rows : [rows];
  if (list.length === 0) return rows;

  const profiles = await fetchProfilesByIds(list.map((r) => r.user_id));
  const enriched = list.map((row) => ({
    ...row,
    profiles: profiles.get(row.user_id) || null,
  }));

  return Array.isArray(rows) ? enriched : enriched[0];
}

/**
 * Attach profile onto nested `orders` objects (activity feed).
 * @param {object[]} events
 * @returns {Promise<object[]>}
 */
export async function attachProfilesToOrderEvents(events = []) {
  if (!events.length) return events;

  const userIds = events
    .map((e) => e.orders?.user_id)
    .filter(Boolean);

  const profiles = await fetchProfilesByIds(userIds);

  return events.map((event) => {
    if (!event.orders) return event;
    const profile = profiles.get(event.orders.user_id) || null;
    return {
      ...event,
      orders: {
        ...event.orders,
        profiles: profile,
      },
    };
  });
}
