#!/usr/bin/env node
/**
 * Babees Place — official portfolio demo dataset seeder.
 *
 * Usage (from repo root or frontend/):
 *   SUPABASE_URL=https://<ref>.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=<service-role> \
 *   node scripts/seed-demo/index.mjs
 *
 * Or:
 *   cd frontend && npm run seed:demo
 *
 * Idempotent for categories/products/pickups/promotions (stable UUIDs).
 * Orders tagged with note='demo-seed-v1' are replaced on re-run.
 *
 * Schema adaptations (live 001–015):
 * - No reviews / rating columns → skipped (documented)
 * - No SKU column → slug used as product code (bp-fsh-001, …)
 * - Promotions/coupons seeded only if 018 tables exist
 *
 * Never commit the service role key.
 */

import { createClient } from '@supabase/supabase-js';
import { CATEGORIES, PRODUCTS, PRODUCT_IDS, PICKUP_LOCATIONS } from './catalog.mjs';
import { ALL_DEMO_USERS, ADDRESSES_BY_EMAIL, DEMO_CUSTOMERS } from './users.mjs';
import { PROMOTIONS, COUPONS } from './promotions.mjs';

const DELIVERY_FEE = 200;
const DEMO_ORDER_NOTE = 'demo-seed-v1';

const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !serviceRoleKey) {
  console.error('Set SUPABASE_URL (or VITE_SUPABASE_URL) and SUPABASE_SERVICE_ROLE_KEY.');
  process.exit(1);
}

const admin = createClient(url, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

function daysAgo(n) {
  return new Date(Date.now() - n * 864e5).toISOString();
}

function assertOk(label, error) {
  if (error) {
    console.error(`✗ ${label}:`, error.message || error);
    throw error;
  }
  console.log(`✓ ${label}`);
}

async function tableExists(name) {
  const { error } = await admin.from(name).select('*', { count: 'exact', head: true }).limit(1);
  if (!error) return true;
  const msg = error.message || String(error);
  if (/schema cache|does not exist|Could not find the table|relation .* does not exist/i.test(msg)) {
    return false;
  }
  console.warn(`! tableExists(${name}):`, msg);
  return false;
}

async function seedPromotionsIfPresent() {
  const hasPromos = await tableExists('promotions');
  const hasCoupons = await tableExists('coupons');
  if (!hasPromos || !hasCoupons) {
    console.log('⚠ promotions/coupons tables not found (migration 018 pending) — skipped');
    console.log('  Re-run seed after applying 016–019 to load Weekend Sale, coupons, etc.');
    return;
  }

  const { error: pErr } = await admin.from('promotions').upsert(PROMOTIONS, { onConflict: 'id' });
  if (pErr) {
    console.warn('⚠ promotions skipped:', pErr.message);
    return;
  }
  console.log(`✓ promotions (${PROMOTIONS.length})`);

  const { error: cErr } = await admin.from('coupons').upsert(COUPONS, { onConflict: 'id' });
  if (cErr) {
    console.warn('⚠ coupons skipped:', cErr.message);
    return;
  }
  console.log(`✓ coupons (${COUPONS.length})`);

  const { error: lErr } = await admin.from('loyalty_rules').upsert(
    {
      code: 'default',
      name: 'Default loyalty rules',
      is_active: true,
      earn_points_per_currency: 0.01,
      redeem_points_per_currency: 10,
      free_delivery_points: 500,
      min_redeem_points: 100,
    },
    { onConflict: 'code' },
  );
  if (lErr) console.warn('! loyalty_rules:', lErr.message);
  else console.log('✓ loyalty_rules default');
}

async function ensureAuthUsers() {
  const map = new Map();
  const { data: listed, error: listError } = await admin.auth.admin.listUsers({ perPage: 200 });
  assertOk('list auth users', listError);
  const existingByEmail = new Map((listed?.users || []).map((u) => [u.email, u]));

  for (const user of ALL_DEMO_USERS) {
    let authUser = existingByEmail.get(user.email);
    if (!authUser) {
      const { data, error } = await admin.auth.admin.createUser({
        email: user.email,
        password: user.password,
        email_confirm: true,
        user_metadata: { full_name: user.fullName, phone: user.phone },
      });
      assertOk(`create ${user.email}`, error);
      authUser = data.user;
    } else {
      await admin.auth.admin.updateUserById(authUser.id, {
        password: user.password,
        email_confirm: true,
        user_metadata: { full_name: user.fullName, phone: user.phone },
      });
    }

    const { error: profileError } = await admin.from('profiles').upsert(
      {
        id: authUser.id,
        email: user.email,
        full_name: user.fullName,
        phone: user.phone,
        role: user.role,
      },
      { onConflict: 'id' },
    );
    assertOk(`profile ${user.email} (${user.role})`, profileError);
    map.set(user.email, authUser.id);
  }
  return map;
}

async function seedCatalog() {
  const { error: catErr } = await admin.from('categories').upsert(
    CATEGORIES.map((c) => ({
      ...c,
      created_at: daysAgo(40),
    })),
    { onConflict: 'id' },
  );
  assertOk(`categories (${CATEGORIES.length})`, catErr);

  const { error: pickErr } = await admin.from('pickup_locations').upsert(PICKUP_LOCATIONS, {
    onConflict: 'id',
  });
  assertOk(`pickup_locations (${PICKUP_LOCATIONS.length})`, pickErr);

  // Upsert in chunks
  for (let i = 0; i < PRODUCTS.length; i += 25) {
    const chunk = PRODUCTS.slice(i, i + 25).map((p) => ({
      ...p,
      created_at: daysAgo(35 - (i % 20)),
      updated_at: new Date().toISOString(),
    }));
    const { error } = await admin.from('products').upsert(chunk, { onConflict: 'id' });
    assertOk(`products ${i + 1}–${i + chunk.length}`, error);
  }

  // Soft-hide legacy non-demo SKUs so the storefront shows the curated 50
  const { data: allProducts, error: listErr } = await admin.from('products').select('id');
  if (listErr) {
    console.warn('! could not list products for deactivation:', listErr.message);
  } else {
    const demoSet = new Set(PRODUCT_IDS);
    const legacyIds = (allProducts || []).map((p) => p.id).filter((id) => !demoSet.has(id));
    if (legacyIds.length) {
      const { error: hideErr } = await admin
        .from('products')
        .update({ is_active: false })
        .in('id', legacyIds);
      if (hideErr) console.warn('! could not deactivate legacy products:', hideErr.message);
      else console.log(`✓ deactivated ${legacyIds.length} non-demo products`);
    } else {
      console.log('✓ no legacy products to deactivate');
    }
  }
}

async function seedAddressesAndPrefs(userIds) {
  for (const [email, rows] of Object.entries(ADDRESSES_BY_EMAIL)) {
    const userId = userIds.get(email);
    if (!userId) continue;
    const payload = rows.map((r) => ({ ...r, user_id: userId }));
    const { error } = await admin.from('customer_addresses').upsert(payload, { onConflict: 'id' });
    assertOk(`addresses ${email}`, error);

    const preferPickup = email.includes('james') || email.includes('lucy');
    const { error: prefErr } = await admin.from('customer_preferences').upsert(
      {
        user_id: userId,
        preferred_fulfillment: preferPickup ? 'pickup' : 'delivery',
        preferred_pickup_location_id: preferPickup
          ? PICKUP_LOCATIONS[0].id
          : null,
        marketing_emails: true,
        sms_notifications: email.includes('mercy') || email.includes('faith'),
      },
      { onConflict: 'user_id' },
    );
    assertOk(`preferences ${email}`, prefErr);
  }
}

async function seedWishlists(userIds) {
  // Clear prior demo wishlists for demo customers, then insert fresh pairs
  const customerIds = DEMO_CUSTOMERS.map((c) => userIds.get(c.email)).filter(Boolean);
  if (customerIds.length) {
    await admin.from('wishlists').delete().in('user_id', customerIds);
  }

  const pairs = [
    [0, 3],
    [0, 16],
    [0, 20],
    [1, 9],
    [1, 44],
    [2, 11],
    [2, 17],
    [3, 5],
    [3, 30],
    [4, 18],
    [4, 45],
    [5, 1],
    [5, 37],
    [6, 23],
    [6, 33],
    [7, 46],
    [7, 49],
    [7, 12],
  ];

  const rows = pairs.map(([ci, pi], idx) => ({
    id: `a7000000-0000-4000-8000-${String(idx + 1).padStart(12, '0')}`,
    user_id: userIds.get(DEMO_CUSTOMERS[ci].email),
    product_id: PRODUCTS[pi].id,
    created_at: daysAgo(12 - (idx % 10)),
  })).filter((r) => r.user_id);

  const { error } = await admin.from('wishlists').upsert(rows, { onConflict: 'id' });
  assertOk(`wishlists (${rows.length})`, error);
}

function lineTotal(product, qty) {
  const unit = Number(product.discount_price ?? product.price);
  return { unit, line: unit * qty, name: product.name, image_url: product.image_url };
}

function buildOrders(userIds) {
  const cust = (i) => userIds.get(DEMO_CUSTOMERS[i].email);
  const P = PRODUCTS;

  const specs = [
    { user: 0, days: 28, status: 'delivered', pay: 'paid', type: 'delivery', items: [[0, 2], [14, 1]] },
    { user: 0, days: 21, status: 'delivered', pay: 'paid', type: 'pickup', pick: 0, items: [[15, 1]] },
    { user: 1, days: 25, status: 'delivered', pay: 'paid', type: 'delivery', items: [[8, 1], [46, 1]] },
    { user: 1, days: 14, status: 'shipped', pay: 'paid', type: 'delivery', items: [[10, 1], [32, 1]] },
    { user: 2, days: 18, status: 'delivered', pay: 'paid', type: 'delivery', items: [[16, 1], [18, 1]] },
    { user: 2, days: 9, status: 'processing', pay: 'paid', type: 'delivery', items: [[19, 1], [22, 1]] },
    { user: 3, days: 16, status: 'delivered', pay: 'paid', type: 'pickup', pick: 1, items: [[2, 1], [6, 1]] },
    { user: 3, days: 6, status: 'confirmed', pay: 'paid', type: 'delivery', items: [[29, 1], [33, 2]] },
    { user: 4, days: 20, status: 'delivered', pay: 'paid', type: 'delivery', items: [[43, 1], [44, 1]] },
    { user: 4, days: 4, status: 'pending', pay: 'pending', type: 'delivery', items: [[17, 1]] },
    { user: 5, days: 22, status: 'cancelled', pay: 'refunded', type: 'delivery', items: [[12, 1]] },
    { user: 5, days: 11, status: 'ready_for_pickup', pay: 'paid', type: 'pickup', pick: 0, items: [[36, 1], [39, 1]] },
    { user: 6, days: 15, status: 'delivered', pay: 'paid', type: 'delivery', items: [[23, 1], [24, 1]] },
    { user: 6, days: 3, status: 'processing', pay: 'paid', type: 'delivery', items: [[4, 1]] },
    { user: 7, days: 19, status: 'delivered', pay: 'paid', type: 'delivery', items: [[30, 1], [47, 2]] },
    { user: 7, days: 8, status: 'shipped', pay: 'paid', type: 'delivery', items: [[49, 1]] },
    { user: 0, days: 2, status: 'pending', pay: 'pending', type: 'pickup', pick: 2, items: [[20, 1], [21, 1]] },
    { user: 1, days: 1, status: 'confirmed', pay: 'paid', type: 'delivery', items: [[1, 3]] },
    { user: 2, days: 5, status: 'cancelled', pay: 'failed', type: 'delivery', items: [[41, 1]] },
    { user: 3, days: 7, status: 'delivered', pay: 'paid', type: 'delivery', items: [[26, 2], [27, 2], [42, 1]] },
  ];

  return specs.map((spec, index) => {
    const orderId = `a8000000-0000-4000-8000-${String(index + 1).padStart(12, '0')}`;
    const addr = ADDRESSES_BY_EMAIL[DEMO_CUSTOMERS[spec.user].email]?.[0];
    let subtotal = 0;
    const items = spec.items.map(([pi, qty], li) => {
      const p = P[pi];
      const { unit, name, image_url } = lineTotal(p, qty);
      subtotal += unit * qty;
      return {
        id: `a9000000-0000-4000-8000-${String(index * 10 + li + 1).padStart(12, '0')}`,
        order_id: orderId,
        product_id: p.id,
        quantity: qty,
        price: unit,
        name,
        image_url,
        created_at: daysAgo(spec.days),
      };
    });

    const isDelivery = spec.type === 'delivery';
    const fee = isDelivery && spec.status !== 'cancelled' ? DELIVERY_FEE : 0;
    const total = spec.status === 'cancelled' ? subtotal : subtotal + fee;

    const delivery_address = isDelivery && addr
      ? {
          line1: addr.street_address,
          city: addr.town,
          county: addr.county,
          phone: addr.phone,
          recipient: addr.recipient_name,
        }
      : null;

    return {
      order: {
        id: orderId,
        user_id: cust(spec.user),
        status: spec.status,
        payment_status: spec.pay,
        total,
        delivery_type: spec.type,
        pickup_location_id: spec.type === 'pickup' ? PICKUP_LOCATIONS[spec.pick ?? 0].id : null,
        delivery_address,
        delivery_fee: fee,
        customer_note: index % 4 === 0 ? 'Please call on arrival' : null,
        note: DEMO_ORDER_NOTE,
        created_at: daysAgo(spec.days),
        updated_at: daysAgo(Math.max(0, spec.days - 1)),
      },
      items,
      events: [
        {
          id: `aa000000-0000-4000-8000-${String(index * 3 + 1).padStart(12, '0')}`,
          order_id: orderId,
          event_type: 'order_placed',
          payload: { source: 'demo-seed', subtotal, total },
          created_at: daysAgo(spec.days),
        },
        ...(spec.status !== 'pending'
          ? [{
              id: `aa000000-0000-4000-8000-${String(index * 3 + 2).padStart(12, '0')}`,
              order_id: orderId,
              event_type: 'status_changed',
              payload: { to: spec.status },
              created_at: daysAgo(Math.max(0, spec.days - 1)),
            }]
          : []),
        ...(spec.pay === 'paid'
          ? [{
              id: `aa000000-0000-4000-8000-${String(index * 3 + 3).padStart(12, '0')}`,
              order_id: orderId,
              event_type: 'payment_status_changed',
              payload: { to: 'paid' },
              created_at: daysAgo(Math.max(0, spec.days - 1)),
            }]
          : []),
      ],
    };
  });
}

async function seedOrders(userIds) {
  // Remove previous demo orders (cascade items/events if FKs set)
  const { data: prior } = await admin.from('orders').select('id').eq('note', DEMO_ORDER_NOTE);
  if (prior?.length) {
    const ids = prior.map((o) => o.id);
    await admin.from('order_events').delete().in('order_id', ids);
    await admin.from('order_items').delete().in('order_id', ids);
    await admin.from('orders').delete().in('id', ids);
    console.log(`✓ cleared ${ids.length} previous demo orders`);
  }

  const bundles = buildOrders(userIds);
  for (const bundle of bundles) {
    if (!bundle.order.user_id) {
      throw new Error('Missing user_id for demo order');
    }
    const { error: oErr } = await admin.from('orders').insert(bundle.order);
    assertOk(`order ${bundle.order.id.slice(-4)} ${bundle.order.status}`, oErr);
    const { error: iErr } = await admin.from('order_items').insert(bundle.items);
    assertOk(`  items (${bundle.items.length})`, iErr);
    const { error: eErr } = await admin.from('order_events').insert(bundle.events);
    assertOk(`  events (${bundle.events.length})`, eErr);
  }
  console.log(`✓ orders complete (${bundles.length})`);
}

async function seedCartSamples(userIds) {
  const uid = userIds.get('customer@babeesplace.com');
  if (!uid) return;
  await admin.from('cart_items').delete().eq('user_id', uid);
  const { error } = await admin.from('cart_items').insert([
    { user_id: uid, product_id: PRODUCTS[2].id, quantity: 1 },
    { user_id: uid, product_id: PRODUCTS[15].id, quantity: 1 },
  ]);
  assertOk('sample cart for Brian Mwangi', error);
}

async function printSummary() {
  const counts = {};
  for (const table of [
    'categories',
    'products',
    'pickup_locations',
    'profiles',
    'customer_addresses',
    'wishlists',
    'orders',
    'order_items',
  ]) {
    const { count } = await admin.from(table).select('*', { count: 'exact', head: true });
    counts[table] = count;
  }
  const { count: activeProducts } = await admin
    .from('products')
    .select('*', { count: 'exact', head: true })
    .eq('is_active', true);
  const { count: featured } = await admin
    .from('products')
    .select('*', { count: 'exact', head: true })
    .eq('featured', true)
    .eq('is_active', true);

  console.log('\n—— Demo dataset summary ——');
  console.log(counts);
  console.log({ activeProducts, featured });
  console.log('Reviews: skipped (table not in schema)');
  console.log('Login: admin@babeesplace.com / Admin123!');
  console.log('Login: customer@babeesplace.com / Customer123!');
  console.log('Other demo customers: *@babeesplace.demo / DemoUser123!');
}

async function main() {
  console.log('Seeding Babees Place demo dataset…\n');
  if (PRODUCTS.length !== 50) {
    throw new Error(`Expected 50 products, got ${PRODUCTS.length}`);
  }

  const userIds = await ensureAuthUsers();
  await seedCatalog();
  await seedAddressesAndPrefs(userIds);
  await seedWishlists(userIds);
  await seedOrders(userIds);
  await seedCartSamples(userIds);
  await seedPromotionsIfPresent();
  await printSummary();
  console.log('\nDone.');
}

main().catch((err) => {
  console.error('\nSeed failed:', err.message || err);
  process.exit(1);
});
