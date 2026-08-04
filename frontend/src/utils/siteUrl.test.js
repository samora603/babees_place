import { describe, it, expect, vi, afterEach } from 'vitest';

describe('siteUrl helpers', () => {
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.resetModules();
  });

  it('strips trailing slash from VITE_SITE_URL', async () => {
    vi.stubEnv('VITE_SITE_URL', 'https://example.com/');
    const { getSiteUrl, absoluteUrl } = await import('./siteUrl');
    expect(getSiteUrl()).toBe('https://example.com');
    expect(absoluteUrl('/og-image.png')).toBe('https://example.com/og-image.png');
    expect(absoluteUrl('https://cdn.example/x.jpg')).toBe('https://cdn.example/x.jpg');
  });
});
