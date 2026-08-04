/**
 * Apply curated product media to the linked Supabase catalog (data only).
 * Does not change schema, checkout, or business logic.
 *
 * Usage (from repo root):
 *   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... node scripts/seed-demo/apply-media.mjs
 */

import { createClient } from '@supabase/supabase-js';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { PRODUCT_MEDIA, mediaForSlug } from './media-map.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));

function loadFrontendEnv() {
  try {
    const raw = readFileSync(join(__dirname, '../../frontend/.env'), 'utf8');
    const env = {};
    for (const line of raw.split('\n')) {
      const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
      if (m) env[m[1]] = m[2].replace(/^["']|["']$/g, '');
    }
    return env;
  } catch {
    return {};
  }
}

const vite = loadFrontendEnv();
const URL = process.env.SUPABASE_URL || vite.VITE_SUPABASE_URL;
const KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!URL || !KEY) {
  console.error('Need SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY');
  process.exit(1);
}

const admin = createClient(URL, KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const { data: products, error } = await admin
  .from('products')
  .select('id, slug, name, image_url')
  .order('slug');

if (error) {
  console.error(error.message);
  process.exit(1);
}

let updated = 0;
let skipped = 0;
const missingMap = [];

for (const p of products || []) {
  const media = PRODUCT_MEDIA[p.slug] || mediaForSlug(p.slug, p.name);
  if (!PRODUCT_MEDIA[p.slug]) missingMap.push(p.slug);

  // Strip thumb_url helper field — not a DB column
  const { image_url, images } = media;
  const { error: upErr } = await admin
    .from('products')
    .update({ image_url, images })
    .eq('id', p.id);

  if (upErr) {
    console.error('FAIL', p.slug, upErr.message);
    process.exit(1);
  }
  updated += 1;
  console.log('OK', p.slug);
}

console.log(JSON.stringify({
  updated,
  skipped,
  mapped: Object.keys(PRODUCT_MEDIA).length,
  unmappedSlugs: missingMap,
}, null, 2));
