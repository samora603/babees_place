import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright E2E config.
 *
 * NOTE: The e2e suite is opt-in. It is NOT part of the required CI gate because
 * it needs (a) browsers installed via `npx playwright install` and (b) valid
 * VITE_SUPABASE_* env vars for the preview build. Run locally with:
 *   npx playwright install
 *   npm run test:e2e
 */
export default defineConfig({
  testDir: './e2e',
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? 'line' : 'list',
  use: {
    baseURL: process.env.E2E_BASE_URL || 'http://localhost:4173',
    trace: 'on-first-retry',
  },
  webServer: {
    command: 'npm run build && npm run preview -- --port 4173',
    port: 4173,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
