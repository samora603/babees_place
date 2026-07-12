import { test, expect } from '@playwright/test';

test.describe('smoke', () => {
  test('home page loads with a title', async ({ page }) => {
    await page.goto('/');
    await expect(page).toHaveTitle(/.+/);
  });

  test('login page renders the sign-in form (auth entry point)', async ({ page }) => {
    await page.goto('/login');
    await expect(page.getByRole('button', { name: /sign in/i })).toBeVisible();
  });

  test('unknown route shows the 404 page', async ({ page }) => {
    await page.goto('/this-route-does-not-exist');
    await expect(page.getByText(/page not found/i)).toBeVisible();
  });
});
