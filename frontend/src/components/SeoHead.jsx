import { useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { absoluteUrl, getSiteUrl } from '@/utils/siteUrl';

const DEFAULTS = {
  siteName: 'Babees Place',
  description: 'Babees Place — premium campus ecommerce. Browse, checkout, and pay with M-Pesa or cash on delivery.',
  image: '/og-image.png',
  twitterHandle: '@babeesplace',
};

/**
 * Lightweight document meta updater for SPA routes (SEO / OG / Twitter).
 */
export default function SeoHead({
  title,
  description = DEFAULTS.description,
  image = DEFAULTS.image,
  type = 'website',
  noIndex = false,
  jsonLd = null,
}) {
  const location = useLocation();
  const siteUrl = getSiteUrl();
  const canonical = absoluteUrl(location.pathname || '/');

  useEffect(() => {
    const fullTitle = title
      ? `${title} · ${DEFAULTS.siteName}`
      : DEFAULTS.siteName;
    document.title = fullTitle;

    setMeta('name', 'description', description);
    setMeta('name', 'robots', noIndex ? 'noindex,nofollow' : 'index,follow');
    setMeta('property', 'og:title', fullTitle);
    setMeta('property', 'og:description', description);
    setMeta('property', 'og:type', type);
    setMeta('property', 'og:url', canonical);
    setMeta('property', 'og:image', absoluteUrl(image));
    setMeta('property', 'og:site_name', DEFAULTS.siteName);
    setMeta('name', 'twitter:card', 'summary_large_image');
    setMeta('name', 'twitter:title', fullTitle);
    setMeta('name', 'twitter:description', description);
    setMeta('name', 'twitter:image', absoluteUrl(image));
    if (DEFAULTS.twitterHandle) {
      setMeta('name', 'twitter:site', DEFAULTS.twitterHandle);
    }
    setLink('canonical', canonical);

    const defaultJsonLd = {
      '@context': 'https://schema.org',
      '@type': 'Store',
      name: DEFAULTS.siteName,
      description: DEFAULTS.description,
      url: siteUrl || canonical,
      currenciesAccepted: 'KES',
      paymentAccepted: 'Cash, M-Pesa',
    };

    let scriptEl = document.getElementById('seo-jsonld');
    const payload = jsonLd || defaultJsonLd;
    if (payload) {
      if (!scriptEl) {
        scriptEl = document.createElement('script');
        scriptEl.type = 'application/ld+json';
        scriptEl.id = 'seo-jsonld';
        document.head.appendChild(scriptEl);
      }
      scriptEl.textContent = JSON.stringify(payload);
    } else if (scriptEl) {
      scriptEl.remove();
    }
  }, [title, description, image, type, noIndex, canonical, jsonLd, siteUrl]);

  return null;
}

function setMeta(attr, key, content) {
  if (content == null) return;
  let el = document.head.querySelector(`meta[${attr}="${key}"]`);
  if (!el) {
    el = document.createElement('meta');
    el.setAttribute(attr, key);
    document.head.appendChild(el);
  }
  el.setAttribute('content', content);
}

function setLink(rel, href) {
  let el = document.head.querySelector(`link[rel="${rel}"]`);
  if (!el) {
    el = document.createElement('link');
    el.setAttribute('rel', rel);
    document.head.appendChild(el);
  }
  el.setAttribute('href', href);
}
