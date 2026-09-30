import { test, expect } from '@playwright/test';

const MOBILE_VIEWPORTS = [
  { width: 320, height: 568, name: '320px (iPhone 5/SE1)' },
  { width: 360, height: 800, name: '360px (Galaxy S8+)' },
  { width: 375, height: 667, name: '375px (iPhone SE2/8)' },
  { width: 390, height: 844, name: '390px (iPhone 12/13/14)' },
  { width: 414, height: 896, name: '414px (iPhone XR/11)' },
  { width: 430, height: 932, name: '430px (iPhone 14/15 Pro Max)' },
];

test.describe('Responsive Shop Verification - Mobile Viewports', () => {
  for (const vp of MOBILE_VIEWPORTS) {
    test(`verify shop page layout and scroll behavior on ${vp.name}`, async ({ page }) => {
      await page.setViewportSize({ width: vp.width, height: vp.height });
      await page.goto('/shop');

      // Wait for navigation and main content
      const navbar = page.locator('nav');
      await expect(navbar).toBeVisible();

      // Check no horizontal overflow
      const hasHorizontalOverflow = await page.evaluate(() => {
        return document.documentElement.scrollWidth > document.documentElement.clientWidth;
      });
      expect(hasHorizontalOverflow).toBe(false);

      // Verify the filter aside is in normal document flow (not sticky) on mobile
      const aside = page.locator('aside');
      await expect(aside).toBeVisible();
      const asidePosition = await aside.evaluate((el) => window.getComputedStyle(el).position);
      expect(asidePosition).toBe('static');

      // Verify filter controls exist and are usable
      const categorySelect = page.locator('#shop-category');
      const sortSelect = page.locator('#shop-sort');
      await expect(categorySelect).toBeVisible();
      await expect(sortSelect).toBeVisible();

      // Verify mobile menu opens and closes cleanly
      const menuBtn = page.locator('#mobile-menu-btn');
      await expect(menuBtn).toBeVisible();
      await menuBtn.click();
      const mobileNavMenu = page.locator('#mobile-nav-menu');
      await expect(mobileNavMenu).toBeVisible();
      const mobileSearchInput = page.locator('#navbar-search-mobile');
      await expect(mobileSearchInput).toBeVisible();
      // Close menu
      await menuBtn.click();
      await expect(mobileNavMenu).not.toBeVisible();

      // Scroll down so that product content scrolls past the top of the viewport
      await page.evaluate(() => window.scrollTo(0, 500));
      await page.waitForTimeout(100);

      // Verify navbar remains sticky at top-0
      const navbarBox = await navbar.boundingBox();
      expect(navbarBox).not.toBeNull();
      expect(navbarBox.y).toBe(0);

      // Verify that the filter aside scrolled off (top is above the navbar)
      const asideBox = await aside.boundingBox();
      expect(asideBox).not.toBeNull();
      // On mobile with scroll 500, aside's top has scrolled up offscreen
      expect(asideBox.y).toBeLessThan(navbarBox.height);

      // Verify products are visible and NOT covered by the aside
      const firstProductCard = page.locator('.card').first();
      if (await firstProductCard.count() > 0) {
        await expect(firstProductCard).toBeVisible();
        const cardBox = await firstProductCard.boundingBox();
        if (cardBox) {
          // If the card is in the viewport, it must not be underneath the aside
          // Check elementFromPoint at the center of the card
          const isCardOccludedByAside = await page.evaluate(() => {
            const card = document.querySelector('.card');
            if (!card) return false;
            const rect = card.getBoundingClientRect();
            if (rect.top >= 0 && rect.bottom <= window.innerHeight) {
              const el = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
              return document.querySelector('aside')?.contains(el) ?? false;
            }
            return false;
          });
          expect(isCardOccludedByAside).toBe(false);
        }
      }
    });
  }
});

test.describe('Responsive Shop Verification - Desktop Viewport', () => {
  test('verify desktop maintains sticky filter sidebar alongside product grid', async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto('/shop');

    const navbar = page.locator('nav');
    await expect(navbar).toBeVisible();

    const aside = page.locator('aside');
    await expect(aside).toBeVisible();

    // Verify aside has sticky position on desktop (>= lg)
    const asidePosition = await aside.evaluate((el) => window.getComputedStyle(el).position);
    expect(asidePosition).toBe('sticky');

    // Check no horizontal overflow
    const hasHorizontalOverflow = await page.evaluate(() => {
      return document.documentElement.scrollWidth > document.documentElement.clientWidth;
    });
    expect(hasHorizontalOverflow).toBe(false);

    // Scroll down
    await page.evaluate(() => window.scrollTo(0, 400));
    await page.waitForTimeout(100);

    // Navbar remains sticky at 0
    const navbarBox = await navbar.boundingBox();
    expect(navbarBox.y).toBe(0);

    // Aside is sticky at top-28 (112px)
    const asideBox = await aside.boundingBox();
    expect(asideBox.y).toBe(112);
  });
});
