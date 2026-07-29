const { defineConfig, devices } = require('@playwright/test');

module.exports = defineConfig({
  testDir: './tests/e2e',
  testMatch: 'core-booking.spec.js',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 90_000,
  expect: {
    timeout: 10_000
  },
  reporter: [
    ['line'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }]
  ],
  globalSetup: require.resolve('./tests/e2e/helpers/global-setup'),
  use: {
    baseURL: process.env.GOSTAY_E2E_BASE_URL || 'http://127.0.0.1:4173',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'off'
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] }
    }
  ],
  outputDir: 'test-results'
});
