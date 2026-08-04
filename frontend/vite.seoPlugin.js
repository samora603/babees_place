/**
 * Vite plugin: inject absolute VITE_SITE_URL into index.html and emit
 * robots.txt + sitemap.xml with absolute URLs at build time.
 */
import { writeFileSync, mkdirSync } from 'fs';
import { join } from 'path';

export function siteUrlSeoPlugin(rawSiteUrl) {
  const siteUrl = String(rawSiteUrl || '').trim().replace(/\/$/, '');

  return {
    name: 'babees-site-url-seo',
    transformIndexHtml(html) {
      const base = siteUrl || '';
      const og = base ? `${base}/og-image.png` : '/og-image.png';
      const canonical = base ? `${base}/` : '/';
      return html
        .replaceAll('%VITE_SITE_URL%', base || '')
        .replaceAll('__SITE_CANONICAL__', canonical)
        .replaceAll('__SITE_OG_IMAGE__', og)
        .replaceAll('__SITE_JSONLD_URL__', base || '/');
    },
    closeBundle() {
      if (!siteUrl) return;
      const outDir = join(process.cwd(), 'dist');
      mkdirSync(outDir, { recursive: true });

      const robots = `User-agent: *
Allow: /
Disallow: /admin
Disallow: /checkout
Disallow: /cart
Disallow: /orders
Disallow: /profile
Disallow: /rewards
Disallow: /notifications
Disallow: /payment

Sitemap: ${siteUrl}/sitemap.xml
`;

      const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${siteUrl}/</loc>
    <changefreq>daily</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>${siteUrl}/shop</loc>
    <changefreq>daily</changefreq>
    <priority>0.9</priority>
  </url>
  <url>
    <loc>${siteUrl}/login</loc>
    <changefreq>monthly</changefreq>
    <priority>0.3</priority>
  </url>
  <url>
    <loc>${siteUrl}/register</loc>
    <changefreq>monthly</changefreq>
    <priority>0.3</priority>
  </url>
</urlset>
`;

      writeFileSync(join(outDir, 'robots.txt'), robots, 'utf8');
      writeFileSync(join(outDir, 'sitemap.xml'), sitemap, 'utf8');
    },
  };
}
