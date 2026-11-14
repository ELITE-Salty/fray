// Local-only signup check. Run scripts/dev.py with console mail output redirected
// to FRAY_MAIL_LOG; this test reads only its synthetic verification message.
import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { randomBytes, createHmac } from 'node:crypto';
import { execFileSync } from 'node:child_process';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.FRAY_PLAYWRIGHT_PATH || 'playwright');
const origin = new URL(process.env.FRAY_BROWSER_URL || 'http://127.0.0.1:18880');
if (!['127.0.0.1', 'localhost'].includes(origin.hostname) || !process.env.FRAY_MAIL_LOG) {
  throw new Error('Use the local development launcher and provide FRAY_MAIL_LOG.');
}
const browser = await chromium.launch({ headless: true,
  ...(process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE ? { executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE } : {}) });
const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
const email = `signup-${Date.now()}@fray.test`;
const password = randomBytes(24).toString('hex');
async function type(label, value) {
  const field = page.getByLabel(label, { exact: true });
  await field.click();
  await page.waitForTimeout(100);
  await field.press('ControlOrMeta+A');
  await field.pressSequentially(value, { delay: 15 });
  await field.press('Tab');
}
function otp(secret) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const bits = [...secret].map(c => alphabet.indexOf(c).toString(2).padStart(5, '0')).join('');
  const key = Buffer.from(bits.match(/.{8}/g).map(byte => parseInt(byte, 2)));
  const counter = Buffer.alloc(8);
  counter.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000)));
  const digest = createHmac('sha1', key).update(counter).digest();
  const offset = digest[19] & 15;
  return String((digest.readUInt32BE(offset) & 0x7fffffff) % 1000000).padStart(6, '0');
}
try {
  await page.goto(origin.href);
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await page.getByRole('button', { name: 'Create an account', exact: true }).click();
  await page.getByLabel('Confirm password', { exact: true }).waitFor();
  await page.screenshot({ path: 'docs/screenshots/signup-mobile.png' });
  await type('Name (optional)', 'Signup Browser');
  await type('Email', email);
  await type('Password', password);
  await type('Confirm password', password);
  const signup = page.waitForResponse(r => r.url().endsWith('/api/auth/signup'));
  await page.getByRole('button', { name: 'Create account', exact: true }).click();
  if ((await signup).status() !== 201) throw new Error('Signup request failed');
  await page.getByText('Check your email', { exact: true }).waitFor();
  const log = await readFile(process.env.FRAY_MAIL_LOG, 'utf8');
  const message = log.slice(log.lastIndexOf(`To: ${email}`));
  const code = message.match(/code is: (\d{6})/)?.[1];
  if (!code) throw new Error('Synthetic verification email was not found in the local console log');
  await type('Email verification code', code);
  const enrollment = page.waitForResponse(r => r.url().endsWith('/api/auth/signup/email'));
  await page.getByRole('button', { name: 'Verify email', exact: true }).click();
  const setup = await (await enrollment).json();
  if (!setup.secret) throw new Error('Authenticator enrollment did not start');
  await page.reload();
  await page.locator('flt-semantics-placeholder').evaluate(el => el.click());
  await page.getByText('Protect your account', { exact: true }).waitFor();
  await type('Authenticator code', otp(setup.secret));
  const finish = page.waitForResponse(r => r.url().endsWith('/api/auth/signup/finish'));
  await page.getByRole('button', { name: 'Finish setup', exact: true }).click();
  const account = await (await finish).json();
  if (account.recoveryCodes?.length !== 8) throw new Error('Recovery-code handoff missing');
  await page.getByText('Keep a way back in', { exact: true }).waitFor();
  await page.getByRole('checkbox', { name: 'I have saved my recovery codes' }).click();
  await page.locator('[role="checkbox"][aria-checked="true"]').waitFor();
  await page.getByRole('button', { name: 'Open my workspace', exact: true }).click();
  await page.getByText('Your time, at a glance.', { exact: true }).waitFor();
  // Mobile NavigationDestination labels also include their tab position.
  await page.locator('[aria-label*="Profile"]').last().click();
  await page.getByRole('button', { name: 'Sign out', exact: true }).click();
  await type('Email', email);
  await type('Password', password);
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await type('Authenticator or recovery code', account.recoveryCodes[0]);
  await page.getByRole('button', { name: 'Verify and sign in', exact: true }).click();
  await page.getByText('Your time, at a glance.', { exact: true }).waitFor();
  console.log('Mobile browser signup passed: email code, enrollment resume, TOTP, recovery handoff, two-step login.');
} catch (error) {
  await page.screenshot({ path: '.artifacts/signup-browser-error.png' });
  throw error;
} finally {
  await browser.close();
  execFileSync('.venv/bin/python', ['backend/manage.py', 'shell', '-c',
    'import os; from django.contrib.auth import get_user_model; from tracker.models import AuthChallenge; e=os.environ["FRAY_TEST_EMAIL"]; AuthChallenge.objects.filter(email=e).delete(); get_user_model().objects.filter(username=e).delete()'],
    { env: { ...process.env, FRAY_DEBUG: '1', FRAY_TEST_EMAIL: email }, stdio: 'ignore' });
}
