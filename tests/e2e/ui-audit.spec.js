const { test, expect } = require('@playwright/test');

const publicPages = [
  '/index.html',
  '/search.html',
  '/room-detail.html',
  '/booking.html',
  '/booking-history.html'
];

for (const viewport of [
  { name: 'desktop', width: 1440, height: 900 },
  { name: 'mobile', width: 390, height: 844 }
]) {
  test(`UI audit ${viewport.name}`, async ({ page }) => {
    await page.setViewportSize(viewport);
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {
      if (message.type() === 'error') errors.push(message.text());
    });

    for (const path of publicPages) {
      await page.goto(path);
      await page.waitForLoadState('domcontentloaded');
      await expect.poll(() => page.evaluate(() => document.readyState)).not.toBe('loading');
      const hasOverflow = await page.evaluate(() =>
        document.documentElement.scrollWidth > document.documentElement.clientWidth
      );
      expect(hasOverflow, `${path} must not overflow horizontally`).toBe(false);
    }

    expect(errors).toEqual([]);
  });
}
