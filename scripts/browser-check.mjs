// Optional real-browser check. npm install --no-save playwright, then:
// FRAY_BROWSER_URL=http://127.0.0.1:8787 node scripts/browser-check.mjs
import { createRequire } from 'node:module';
import { mkdir } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.FRAY_PLAYWRIGHT_PATH || 'playwright');
const browser = await chromium.launch({ headless: true,
  ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
const page = await browser.newPage({ viewport: { width: 1440, height: 1060 }, deviceScaleFactor: 1 });
async function typeInto(field, value) {
  await field.click();
  // Flutter connects its editable text input on the next frame after semantics focus.
  await page.waitForTimeout(100);
  await field.press('ControlOrMeta+A');
  await field.pressSequentially(value, { delay: 30 });
  if (await field.inputValue() !== value) throw new Error('Browser input did not accept the expected text');
  await field.press('Tab');
  await page.waitForTimeout(100);
}
// Simulate the Cloudflare HTTPS origin without publishing this local test stack.
if (process.env.FRAY_PROXY_ORIGIN) {
  const publicOrigin = new URL(process.env.FRAY_BROWSER_URL);
  await page.context().route(`${publicOrigin.origin}/**`, async route => {
    const request = route.request();
    const url = new URL(request.url());
    const response = await page.context().request.fetch(`${process.env.FRAY_PROXY_ORIGIN}${url.pathname}${url.search}`, {
      method: request.method(), headers: { ...await request.allHeaders(), host: publicOrigin.host },
      data: request.postDataBuffer() || undefined, maxRedirects: 0,
    });
    await route.fulfill({ response });
  });
}
function manage(args, extraEnv = {}, ignoreOutput = false) {
  const options = { env: { ...process.env, ...extraEnv }, ...(ignoreOutput ? { stdio: 'ignore' } : {}) };
  if (process.env.FRAY_DOCKER_PROJECT) {
    return execFileSync('docker', ['compose', '-f', resolve('infra/docker/compose.yaml'), '-p', process.env.FRAY_DOCKER_PROJECT,
      'exec', '-T', ...Object.keys(extraEnv).flatMap(key => ['-e', key]), 'api', 'python', 'manage.py', ...args], options);
  }
  return execFileSync('.venv/bin/python', ['backend/manage.py', ...args], {
    ...options, env: { ...options.env, FRAY_DEBUG: '1' },
  });
}
const errors = [];
page.on('pageerror', e => errors.push(e.message));
await mkdir('docs/screenshots', { recursive: true });
let fixtureEmail;
try {
  await page.goto(process.env.FRAY_BROWSER_URL || 'http://127.0.0.1:8080');
  await page.locator('flt-glass-pane').waitFor({ state: 'attached', timeout: 60000 });
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await page.getByRole('button', { name: 'Explore the demo' }).click();
  await page.getByText('Your time, at a glance.', { exact: true }).waitFor();
  await page.screenshot({ path: 'docs/screenshots/calendar-desktop.png' });
  await page.getByRole('button', { name: 'Reports', exact: true }).click();
  await page.getByText('See the bigger picture.', { exact: true }).waitFor();
  await page.screenshot({ path: 'docs/screenshots/reports-desktop.png' });
  const download = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export CSV', exact: true }).click();
  if (!(await download).suggestedFilename().endsWith('.csv')) throw new Error('CSV was not downloaded');
  await page.getByRole('button', { name: 'Calendar', exact: true }).click();
  await page.locator('span').filter({ hasText: /^CSV download started\.$/ }).waitFor({ state: 'hidden' });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: 'docs/screenshots/calendar-mobile.png' });
  if (process.env.FRAY_BROWSER_AUTH === '1') {
    // This opt-in check creates and removes its own account in the local dev database.
    fixtureEmail = `browser-${Date.now()}@fray.test`;
    await mkdir('.artifacts', { recursive: true });
    const account = JSON.parse(manage(['create_fray_user', fixtureEmail, '--name', 'Browser Test'],
      { FRAY_INITIAL_PASSWORD: randomBytes(24).toString('hex') }).toString());
    await page.setViewportSize({ width: 1440, height: 1060 });
    await page.getByRole('button', { name: 'Profile', exact: true }).click();
    await page.getByRole('button', { name: 'Leave demo', exact: true }).click();
    const emailField = page.getByRole('textbox', { name: 'Email', exact: true });
    await typeInto(emailField, account.email);
    await typeInto(page.getByLabel('Password', { exact: true }), account.password);
    await typeInto(page.getByRole('textbox', { name: 'Authenticator or recovery code', exact: true }), account.recovery_codes[0]);
    const loginRequest = page.waitForRequest(r => r.url().endsWith('/api/auth/login') && r.method() === 'POST');
    await page.getByRole('button', { name: 'Sign in', exact: true }).click();
    const sent = (await loginRequest).postDataJSON();
    if (sent.email !== account.email || sent.password !== account.password || sent.code !== account.recovery_codes[0]) {
      throw new Error(`Login form mismatch: email=${sent.email === account.email}, password=${sent.password === account.password}, code=${sent.code === account.recovery_codes[0]}, code length=${sent.code?.length}, expected=${account.recovery_codes[0].length}`);
    }
    await page.getByText('Your time, at a glance.', { exact: true }).waitFor();
    await page.getByRole('button', { name: 'Projects', exact: true }).click();
    await page.getByRole('button', { name: 'New project / activity', exact: true }).click();
    await typeInto(page.getByRole('textbox', { name: /^Name/ }), 'Browser test project');
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await page.getByText('Browser test project').waitFor();
    await page.getByRole('button', { name: 'Calendar', exact: true }).click();
    await page.getByRole('button', { name: 'Add entry', exact: true }).click();
    await typeInto(page.getByRole('textbox', { name: /^Duration in minutes/ }), '75');
    await typeInto(page.getByRole('textbox', { name: /^Notes/ }), 'Persistent browser test');
    await page.getByRole('button', { name: 'Save entry', exact: true }).click();
    await page.getByText('Persistent browser test').waitFor();
    await page.reload();
    await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
    await page.getByText('Persistent browser test').waitFor();
    const scope = await page.evaluate(async () => (await fetch('/api/auth/me')).json());
    if (scope.email !== fixtureEmail) throw new Error('Session did not survive reload');
    await page.getByRole('button', { name: 'Profile', exact: true }).click();
    await page.getByRole('button', { name: 'Sign out', exact: true }).click();
    await page.getByRole('button', { name: 'Sign in', exact: true }).waitFor();
    console.log('Real-account browser check passed: MFA recovery login, project, entry, reload, logout.');
  }
  if (errors.length) throw new Error(errors.join('\n'));
  console.log('Browser checks passed: desktop, mobile, navigation, CSV download.');
} finally {
  await browser.close();
  if (fixtureEmail) {
    manage(['shell', '-c',
      'import os; from django.contrib.auth import get_user_model; from tracker.models import TimeEntry, Item; u=get_user_model().objects.filter(username=os.environ["FRAY_TEST_EMAIL"]); TimeEntry.objects.filter(author__in=u).delete(); Item.objects.filter(owner__in=u).delete(); u.delete()'],
      { FRAY_TEST_EMAIL: fixtureEmail }, true);
  }
}
