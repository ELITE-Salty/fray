// Real browser storage, reload, and OS language/appearance checks against a local build.
import { createRequire } from 'node:module';
import { mkdir } from 'node:fs/promises';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.FRAY_PLAYWRIGHT_PATH || 'playwright');
const origin = new URL(process.env.FRAY_BROWSER_URL || 'http://127.0.0.1:18880');
if (!['127.0.0.1', 'localhost'].includes(origin.hostname)) throw new Error('Use a local validation server.');
const browser = await chromium.launch({ headless: true,
  ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
await mkdir('docs/screenshots', { recursive: true });
async function semantics(page) {
  const placeholder = page.locator('flt-semantics-placeholder');
  await placeholder.evaluate(el => el.click());
}
try {
  for (const config of [
    { locale: 'sl-SI', language: 'Slovenščina', settings: 'Nastavitve', appearance: 'Videz', light: 'Svetlo', done: 'Končano', demo: 'Razišči predstavitev', profile: 'Profil', width: 390 },
    { locale: 'hr-HR', language: 'Hrvatski', settings: 'Postavke', appearance: 'Izgled', light: 'Svijetlo', done: 'Gotovo', demo: 'Istraži probni prostor', profile: 'Profil', width: 1440 },
  ]) {
    const context = await browser.newContext({ locale: config.locale, colorScheme: 'dark', viewport: { width: config.width, height: 1000 } });
    const page = await context.newPage();
    page.setDefaultTimeout(10000);
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(origin.href);
    await semantics(page);
    await page.getByRole('button', { name: config.settings, exact: true }).click();
    await page.getByRole('button', { name: new RegExp(config.appearance) }).waitFor();
    await page.screenshot({ path: `docs/screenshots/settings-${config.locale}-dark.png` });
    // Both dropdowns initially show System. First is language, second appearance.
    await page.getByRole('button', { name: /Sistemsko|Sustav/ }).first().click();
    await page.getByRole('menuitem', { name: 'English', exact: true }).click();
    await page.getByRole('button', { name: /Appearance/ }).waitFor();
    await page.getByRole('button', { name: /System/ }).last().click();
    await page.getByRole('menuitem', { name: 'Light', exact: true }).click();
    await page.getByRole('button', { name: 'Done', exact: true }).click();
    await page.reload();
    await semantics(page);
    await page.getByRole('button', { name: 'Settings', exact: true }).click();
    await page.getByRole('button', { name: 'Language English', exact: true }).waitFor();
    await page.getByRole('button', { name: 'Appearance Light', exact: true }).waitFor();
    await page.getByRole('button', { name: /English/ }).click();
    await page.getByRole('menuitem', { name: config.language, exact: true }).click();
    await page.getByRole('button', { name: new RegExp(config.light) }).click();
    await page.getByRole('menuitem', { name: config.locale === 'sl-SI' ? 'Temno' : 'Tamno', exact: true }).click();
    await page.getByRole('button', { name: config.done, exact: true }).click();
    await page.getByRole('button', { name: config.demo, exact: true }).click();
    await (config.width < 1000
      ? page.locator(`[aria-label*="${config.profile}"]`).first()
      : page.getByRole('button', { name: config.profile, exact: true })).click();
    await page.getByRole('button', { name: new RegExp(config.appearance) }).waitFor();
    if (config.width < 1000) {
      await page.mouse.move(180, 650);
      await page.mouse.wheel(0, 600);
    }
    await page.mouse.move(8, 8);
    await page.waitForTimeout(400); // Finish the scroll/tooltip animation before the screenshot.
    await page.screenshot({ path: `docs/screenshots/profile-${config.locale}-dark.png` });
    if (errors.length) throw new Error(errors.join('\n'));
    await context.close();
    console.log(`${config.locale}: system defaults, persisted overrides, translated dark profile passed`);
  }
} finally { await browser.close(); }
