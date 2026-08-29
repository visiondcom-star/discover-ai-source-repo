import { chromium } from 'playwright';

const BASE = 'http://localhost:3000';
const SHOTS = '/tmp/pw_shots';
const EMAIL = 'demo@algeria.travel';
const PASSWORD = 'demo1234';

const results = [];
function log(step, ok, extra = '') {
  const line = `[${ok ? 'PASS' : 'FAIL'}] ${step}${extra ? ' :: ' + extra : ''}`;
  results.push(line);
  console.log(line);
}

const browser = await chromium.launch();
const context = await browser.newContext();
const page = await context.newPage();

try {
  // ---- 1) Landing + open login form ----
  await page.goto(BASE, { waitUntil: 'networkidle' });
  await page.screenshot({ path: `${SHOTS}/01-landing.png` });
  log('Landing page loaded', await page.locator('[data-nextjs-dialog-overlay]').count() === 0);

  await page.getByRole('button', { name: /J.ai déjà un compte/i }).click();
  await page.getByPlaceholder('Email').waitFor();
  await page.screenshot({ path: `${SHOTS}/02-login-form.png` });
  log('Login form visible', true);

  const consoleErrors = [];
  page.on('console', m => { if (m.type() === 'error') consoleErrors.push(m.text()); });
  page.on('pageerror', e => consoleErrors.push(e.message));

  // ---- 2) Fill + submit real login ----
  await page.getByPlaceholder('Email').fill(EMAIL);
  await page.getByPlaceholder('Mot de passe').fill(PASSWORD);
  await page.getByRole('button', { name: /Se connecter/i }).click();

  await page.getByRole('button', { name: 'Profil' }).waitFor({ timeout: 15000 });
  await page.screenshot({ path: `${SHOTS}/03-after-login.png` });
  log('Login succeeded, authenticated shell rendered', true);

  // ---- 3) Verify cookies on the real browser context ----
  const cookies = await context.cookies(BASE);
  const access = cookies.find(c => c.name === 'access_token');
  const csrf = cookies.find(c => c.name === 'csrf_token');
  log('access_token cookie set', !!access, access ? `httpOnly=${access.httpOnly} secure=${access.secure} sameSite=${access.sameSite}` : 'missing');
  log('access_token is httpOnly', !!(access && access.httpOnly));
  log('csrf_token cookie set with httpOnly=false', !!(csrf && !csrf.httpOnly), csrf ? `httpOnly=${csrf.httpOnly}` : 'missing');

  // ---- 4) localStorage must be empty ----
  const lsLen = await page.evaluate(() => localStorage.length);
  const lsKeys = await page.evaluate(() => Object.keys(localStorage));
  log('localStorage is empty (len=0)', lsLen === 0, `len=${lsLen} keys=${JSON.stringify(lsKeys)}`);

  // ---- 5) Authenticated page loads real data (email shown, no redirect to login) ----
  const userEmailVisible = await page.getByText(EMAIL, { exact: false }).first().isVisible().catch(() => false);
  log('Authenticated page shows real user email (loaded real data)', userEmailVisible);
  const stillHasShell = await page.getByRole('button', { name: 'Profil' }).isVisible().catch(() => false);
  log('Still on authenticated shell (no redirect to login)', stillHasShell);
  await page.screenshot({ path: `${SHOTS}/04-authenticated.png` });

      // ---- 6) Chat: capture REAL on-the-wire headers via CDP ----
  // Playwright's Page.request.headers() masks `cookie`, and HeadlessChrome
  // 151's Network.requestWillBeSent also omits Cookie from request.headers.
  // Network.requestWillBeSentExtraInfo DOES expose it (keyed by requestId),
  // so we correlate requestWillBeSent (URL + x-csrf-token) with the matched
  // ExtraInfo (cookie) to assemble the full on-the-wire picture.
  const client = await page.context().newCDPSession(page);
  await client.send('Network.enable');
  await client.send('Network.setCacheDisabled', { cacheDisabled: true });

  // requestId -> {url, csrf, extraInfoHeaders}
  const reqs = {};
  let chatRespStatus = null;
  client.on('Network.requestWillBeSent', ({ requestId, request }) => {
    if (request.method === 'POST' && request.url.includes('/api/v1/chat')) {
      reqs[requestId] = {
        url: request.url,
        csrf: request.headers['x-csrf-token'] || request.headers['X-CSRF-Token'] || null,
      };
    }
  });
  client.on('Network.requestWillBeSentExtraInfo', ({ requestId, headers }) => {
    if (reqs[requestId]) {
      reqs[requestId].extra = headers;
    }
  });
  client.on('Network.responseReceived', ({ response }) => {
    if (response.url.includes('/api/v1/chat')) {
      chatRespStatus = response.status;
    }
  });

  await page.getByRole('button', { name: 'Assistant' }).click();
  await page.getByPlaceholder(/Posez-moi une question/i).waitFor();
  await page.getByPlaceholder(/Posez-moi une question/i).fill('Bonjour');
  await page.getByPlaceholder(/Posez-moi une question/i).press('Enter');

  await page.waitForFunction(() => document.querySelectorAll('.chat-message').length >= 2, null, { timeout: 15000 });
  await page.screenshot({ path: `${SHOTS}/05-chat-sent.png` });
  await page.waitForTimeout(300);

      // Pick the POST that carries the CSRF header (the real app request).
  // NOTE: In CDP, the X-CSRF-Token custom header shows up ONLY in
  // requestWillBeSentExtraInfo (extra), NOT in requestWillBeSent's headers,
  // so we check both places.
  const hasCsrfInExtra = r => r.extra && (r.extra['X-CSRF-Token'] || r.extra['x-csrf-token']);
  const hasCsrfInReq = r => r.csrf;
  const realPost = Object.values(reqs).find(r => r.extra && (hasCsrfInReq(r) || hasCsrfInExtra(r)));
  const chatPost = realPost || Object.values(reqs).find(r => r.extra);
  const chatOk = !!chatPost;
  log('POST /chat/ captured via CDP', chatOk, chatPost ? JSON.stringify(chatPost.extra) : 'request not seen');

  const extra = chatPost && chatPost.extra;
  const hasCookie = !!(extra && /access_token=/.test(extra.Cookie || extra.cookie || ''));
  // CSRF header lives in ExtraInfo headers (not in requestWillBeSent headers)
  const csrfHeader = (extra && (extra['X-CSRF-Token'] || extra['x-csrf-token'])) || chatPost.csrf || null;
  log('POST /chat/ carries cookie (access_token)', hasCookie, extra ? `cookie=${String(extra.Cookie || extra.cookie || '').slice(0, 40)}...` : '');
  log('POST /chat/ carries X-CSRF-Token header', !!csrfHeader, csrfHeader ? `header=${String(csrfHeader).slice(0, 8)}...` : '');
  log('POST /chat/ returned 200', chatRespStatus === 200, `status=${chatRespStatus}`);

  const lastMsg = await page.locator('.chat-message').last().textContent();
  log('Chat assistant replied (non-error)', !!lastMsg && !lastMsg.includes('Désolé'), `reply=${(lastMsg||'').slice(0, 50)}`);

  // ---- 7) Logout via Profile ----
  await page.getByRole('button', { name: 'Profil' }).click();
  await page.getByRole('button', { name: /Se déconnecter/i }).click();
  await page.getByText(/Votre voyage commence ici/i).waitFor({ timeout: 8000 });
  await page.screenshot({ path: `${SHOTS}/06-after-logout.png` });
  log('Logout returned to landing page', true);

  const cookiesAfter = await context.cookies(BASE);
  const stillAccess = cookiesAfter.find(c => c.name === 'access_token');
  const stillCsrf = cookiesAfter.find(c => c.name === 'csrf_token');
  log('access_token gone/expired after logout', !stillAccess);
  log('csrf_token gone/expired after logout', !stillCsrf);

  const profileBack = await page.getByRole('button', { name: 'Profil' }).isVisible().catch(() => false);
  log('Authenticated page inaccessible after logout (no Profil tab)', !profileBack);

  log('No console/page errors during flow', consoleErrors.length === 0, consoleErrors.slice(0, 5).join(' | '));

} catch (err) {
  log('UNEXPECTED ERROR', false, String(err && err.stack || err));
  await page.screenshot({ path: `${SHOTS}/99-error.png` }).catch(() => {});
} finally {
  await browser.close();
}

const failed = results.filter(r => r.startsWith('[FAIL]'));
console.log('\n========== SUMMARY ==========');
console.log(`TOTAL=${results.length} PASS=${results.length - failed.length} FAIL=${failed.length}`);
if (failed.length) {
  console.log('FAILURES:');
  failed.forEach(f => console.log('  ' + f));
}
