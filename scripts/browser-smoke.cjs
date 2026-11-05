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
    const fixture = JSON.parse(fs.readFileSync(process.env.FRAY_BROWSER_STATE, 'utf8'));
    const context = await browser.newContext({ storageState: fixture.owner, viewport: { width: 1440, height: 1000 } });
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
    assert.match(await page.locator('#id_local_date').inputValue(), /^\d{4}-\d{2}-\d{2}$/, 'Default date must be browser-valid ISO format');
    await page.getByLabel('What are you working on?').fill('Browser-verified planning');
    await page.getByLabel('Minutes (duration only)').fill('45');
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await page.getByText('Browser-verified planning', { exact: true }).waitFor();
    await page.goto(base + '/');
    await page.getByLabel('What are you working on?').fill('Browser timer');
    await page.getByRole('button', { name: 'Start timer' }).click();
    await page.getByRole('button', { name: 'Stop & save' }).waitFor();
    await page.waitForLoadState('load');
    await page.reload();
    await page.getByRole('button', { name: 'Stop & save' }).click();
    await page.getByText('Timer stopped and time saved.', { exact: true }).waitFor();
    // Two real browser sessions: invite, explicit acceptance, shared work, privacy.
    await page.goto(base + '/items/new/project/');
    await page.getByLabel('Name', { exact: true }).fill('Shared browser depot');
    await page.getByRole('button', { name: 'Save', exact: true }).click();
    await page.getByRole('link', { name: 'Shared browser depot', exact: true }).click();
    const projectUrl = page.url();
    const projectId = projectUrl.split('/').filter(Boolean).at(-1);
    await page.getByLabel('Member email').fill(fixture.memberEmail);
    await page.getByRole('button', { name: 'Send invitation' }).click();
    await page.getByText('Invitation sent. Membership begins only after acceptance.', { exact: true }).waitFor();
    const memberContext = await browser.newContext({ storageState: fixture.member, viewport: { width: 390, height: 844 } });
    const memberPage = await memberContext.newPage();
    memberPage.on('pageerror', e => errors.push(e.message));
    await memberPage.goto(base + '/items/');
    await memberPage.getByRole('link', { name: 'Review invitation' }).click();
    await memberPage.getByRole('button', { name: 'Accept invitation' }).click();
    await memberPage.getByRole('heading', { name: 'Shared browser depot', exact: true }).waitFor();
    assert.equal(await memberPage.getByRole('button', { name: 'Send invitation' }).count(), 0);
    for (const [actor, minutes, description] of [[page, '40', 'Owner private work'], [memberPage, '20', 'Member private work']]) {
      await actor.goto(base + '/entries/new/');
      await actor.getByLabel('What are you working on?').fill(description);
      await actor.getByLabel('Activity / project').selectOption('p:' + projectId);
      await actor.getByLabel('Minutes (duration only)').fill(minutes);
      await actor.getByRole('button', { name: 'Save', exact: true }).click();
      await actor.getByText(description, { exact: true }).waitFor();
      await actor.goto(base + '/');
      await actor.getByLabel('What are you working on?').fill(description + ' timer');
      await actor.getByLabel('Activity / project').selectOption('p:' + projectId);
      await actor.getByRole('button', { name: 'Start timer' }).click();
      await actor.getByRole('button', { name: 'Stop & save' }).waitFor();
      await actor.waitForLoadState('load');
    }
    // Both timers are still running independently; each account stops only its own.
    for (const actor of [page, memberPage]) {
      await actor.reload();
      await actor.getByRole('button', { name: 'Stop & save' }).click();
      await actor.getByText('Timer stopped and time saved.', { exact: true }).waitFor();
      await actor.goto(projectUrl);
      await actor.getByRole('heading', { name: 'Member totals', exact: true }).waitFor();
      const rows = actor.locator('.item-row');
      assert.equal(await rows.count(), 2);
      const totals = await rows.locator('strong').allTextContents();
      assert(totals.some(t => t.startsWith('0h 40m')), JSON.stringify(totals));
      assert(totals.some(t => t.startsWith('0h 20m')), JSON.stringify(totals));
      assert.equal(await actor.getByText('Owner private work', { exact: true }).count(), 0);
      assert.equal(await actor.evaluate(() => document.documentElement.scrollWidth > innerWidth), false);
    }
    await page.screenshot({ path: out + '/shared-project-owner-desktop.png', fullPage: true });
    await memberPage.screenshot({ path: out + '/shared-project-member-mobile.png', fullPage: true });
    for (const [actor, hidden] of [[page, 'Member private work'], [memberPage, 'Owner private work']]) {
      await actor.goto(base + '/entries/');
      assert.equal(await actor.getByText(hidden, { exact: true }).count(), 0);
    }
    await memberContext.close();
    await page.setViewportSize({ width: 390, height: 844 });
    for (const path of ['/', '/items/', '/entries/new/', '/reports/', '/profile/']) {
      await page.goto(base + path);
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth > innerWidth), false, 'Mobile must not overflow at ' + path);
    }
    await page.goto(base + '/');
    await page.screenshot({ path: out + '/calendar-mobile.png', fullPage: true });
    assert.deepEqual(errors, []);
    console.log('Browser checks passed: desktop/mobile rendering, no overflow, manual entry, timer/refresh/stop, two-account email invite/accept, independent shared timers, correct member totals, entry privacy, no JavaScript errors.');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
