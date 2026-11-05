// Run with Playwright 1.62.1 installed. Fixture state stays outside artifacts.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const { chromium } = require(process.env.FRAY_PLAYWRIGHT || 'playwright');
const base = process.env.FRAY_BASE_URL || 'http://127.0.0.1:8000';
const out = process.env.FRAY_SCREENSHOT_DIR || '.test-artifacts';
(async () => {
  fs.mkdirSync(out, { recursive: true });
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  try {
    const anonymous = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    await anonymous.goto(base + '/accounts/login/');
    await anonymous.getByRole('button', { name: 'Sign In', exact: true }).waitFor();
    await anonymous.screenshot({ path: out + '/login-desktop.png', fullPage: true });
    const context = await browser.newContext({ storageState: process.env.FRAY_BROWSER_STATE, viewport: { width: 1440, height: 1000 } });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    for (const [path, heading, file] of [
      ['/', 'Your calendar', 'calendar-desktop'],
      ['/items/', 'Projects & activities', 'projects-desktop'],
      ['/reports/', 'Your time, at a glance', 'reports-desktop'],
    ]) {
      await page.goto(base + path);
      await page.getByRole('heading', { name: heading, exact: true }).waitFor();
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, 'Desktop must not overflow');
      await page.screenshot({ path: out + '/' + file + '.png', fullPage: true });
    }
    // Complete a manual entry through rendered controls and CSRF handling.
    await page.goto(base + '/entries/new/');
    await page.getByLabel('What are you working on?').fill('Browser-verified planning');
    await page.getByLabel('Minutes (duration only)').fill('45');
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await page.getByText('Browser-verified planning', { exact: true }).waitFor();
    await page.goto(base + '/');
    await page.getByLabel('What are you working on?').fill('Browser timer');
    await page.getByRole('button', { name: 'Start timer' }).click();
    await page.reload();
    await page.getByRole('button', { name: 'Stop & save' }).click();
    await page.getByText('Timer stopped and time saved.', { exact: true }).waitFor();
    await page.setViewportSize({ width: 390, height: 844 });
    for (const path of ['/', '/items/', '/entries/new/', '/reports/', '/profile/']) {
      await page.goto(base + path);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, 'Mobile must not overflow at ' + path);
    }
    await page.goto(base + '/');
    await page.screenshot({ path: out + '/calendar-mobile.png', fullPage: true });
    assert.deepEqual(errors, []);
    console.log('Browser checks passed: desktop/mobile rendering, no overflow, manual entry, timer/refresh/stop, no JavaScript errors.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
