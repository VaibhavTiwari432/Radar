// verify-console-live.mjs -- exercise the ACTUAL page in a real browser.
//
// This project's rule is "no done without a pasted green test; reading the
// code is not a test". A bundle that builds and a bridge that answers curl do
// NOT prove the console works -- nobody had clicked RUN. This script does.
//
// It proves, in a real Chromium:
//   1. the page loads with zero console errors
//   2. AC-6  -- with the bridge DOWN, the JUDGE OFFLINE banner renders and no
//              verdict is shown (the single most important honesty property)
//   3. AC-7  -- with the bridge UP, clicking RUN produces exactly N phantom
//              rows and a live 3D canvas, N coming from the real planner and
//              the real MATLAB judge
//   4. AC-9  -- the word bestScore appears nowhere in the rendered DOM
//
// Usage:
//   node scripts/verify-console-live.mjs --url http://127.0.0.1:5173/console.html
//   node scripts/verify-console-live.mjs --offline-only     (no bridge needed)
//
// RUN is slow ON PURPOSE (~76 s: a real planner plus a real judge), so the
// click timeout is generous. A fast console here would mean it was faking.

import puppeteer from 'puppeteer';
import { writeFileSync, mkdirSync } from 'node:fs';

const arg = (k, d) => {
  const i = process.argv.indexOf(k);
  return i > -1 ? process.argv[i + 1] : d;
};
const URL_ = arg('--url', 'http://127.0.0.1:5173/console.html');
const BRIDGE = arg('--bridge', 'http://127.0.0.1:8000');
const OFFLINE_ONLY = process.argv.includes('--offline-only');
const RUN_TIMEOUT_MS = Number(arg('--run-timeout', '240000'));
const EXPECT_N = Number(arg('--n', '1'));

const results = [];
const ok = (name, pass, detail = '') => {
  results.push({ name, pass, detail });
  console.log(`${pass ? 'PASS' : 'FAIL'}: ${name}${detail ? ' -- ' + detail : ''}`);
};

async function bridgeUp() {
  try {
    const r = await fetch(BRIDGE + '/health', { signal: AbortSignal.timeout(4000) });
    const j = await r.json();
    return !!j.judge_online;
  } catch { return false; }
}

const main = async () => {
  mkdirSync('screenshots', { recursive: true });
  const browser = await puppeteer.launch({
    headless: 'new',
    // protocolTimeout defaults to 180 s, BELOW this script's own 240 s run
    // budget -- so waitForFunction could never actually spend the budget it
    // advertises, and a slow planner pass died in CDP with a ProtocolError
    // instead of failing (or passing) a check. Kept above RUN_TIMEOUT_MS.
    protocolTimeout: RUN_TIMEOUT_MS + 60000,
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--use-gl=swiftshader',
           '--enable-unsafe-swiftshader'],   // three.js needs a GL context headless
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1600, height: 900 });

  // Track the failing URL, not the console message text. A resource error
  // reads "Failed to load resource: ... 404" and does NOT contain the URL, so
  // filtering on message text cannot tell a favicon 404 from a real one --
  // a first version of this script tried and let a favicon fail the run.
  const consoleErrors = [];
  const failedUrls = [];
  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    if (/Failed to load resource/i.test(m.text())) return;   // covered by failedUrls
    consoleErrors.push(m.text());
  });
  page.on('pageerror', (e) => consoleErrors.push('pageerror: ' + e.message));
  page.on('response', (r) => { if (r.status() >= 400) failedUrls.push(`${r.status()} ${r.url()}`); });
  page.on('requestfailed', (r) => failedUrls.push(`${r.failure()?.errorText} ${r.url()}`));
  page.__failedUrls = failedUrls;

  const up = await bridgeUp();
  console.log(`bridge ${BRIDGE} judge_online=${up}`);

  await page.goto(URL_, { waitUntil: 'networkidle2', timeout: 60000 });
  await page.waitForSelector('[data-testid="run-btn"]', { timeout: 15000 });
  ok('page loads and mounts', true);

  // ---------------- AC-6: offline honesty ----------------
  // The banner appears only after the /health round-trip settles. Polling for
  // it rather than sampling once -- a first version sampled immediately and
  // reported a FAIL that was purely a race in this script.
  let banner = null;
  try {
    await page.waitForSelector('[data-testid="judge-offline"]',
      { timeout: up ? 1500 : 15000 });
    banner = await page.$('[data-testid="judge-offline"]');
  } catch { /* absent within the window */ }

  if (!up) {
    ok('AC-6 JUDGE OFFLINE banner shown when the judge is down', !!banner);
    const rows = await page.$$('[data-testid="phantom-row"]');
    ok('AC-6 no verdict invented while offline', rows.length === 0,
       `${rows.length} phantom rows`);
    await page.screenshot({ path: 'screenshots/console-offline.png' });
  } else {
    ok('AC-6 no offline banner while the judge is up', !banner);
  }

  if (OFFLINE_ONLY || !up) {
    await finish(browser, page, consoleErrors, true);
    return;
  }

  // ---------------- AC-7: click RUN for real ----------------
  await page.evaluate((n) => {
    const s = document.querySelector('input[type=range]');   // phantom-count slider
    const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
    setter.call(s, String(n));
    s.dispatchEvent(new Event('input', { bubbles: true }));
  }, EXPECT_N);

  const t0 = Date.now();
  await page.click('[data-testid="run-btn"]');
  await page.waitForFunction(
    () => document.querySelectorAll('[data-testid="phantom-row"]').length > 0 ||
          document.querySelector('[data-testid="judge-offline"]'),
    { timeout: RUN_TIMEOUT_MS, polling: 1000 });
  const elapsed = ((Date.now() - t0) / 1000).toFixed(1);

  const offlineAfter = await page.$('[data-testid="judge-offline"]');
  ok('AC-6 judge stayed online through the run', !offlineAfter);

  const statuses = await page.$$eval('[data-testid="phantom-row"]',
    (els) => els.map((e) => e.getAttribute('data-status')));
  ok(`AC-7 RUN produced exactly N=${EXPECT_N} phantom rows`,
     statuses.length === EXPECT_N, `got ${statuses.length} in ${elapsed}s [${statuses}]`);

  const canvas = await page.$eval('canvas', (c) => ({ w: c.width, h: c.height }))
    .catch(() => null);
  ok('AC-7 3D canvas rendered', !!canvas && canvas.w > 0 && canvas.h > 0,
     canvas ? `${canvas.w}x${canvas.h}` : 'no canvas');

  const verdict = await page.evaluate(() =>
    document.body.innerText.includes('Confirmed tracks'));
  ok('judge verdict panel populated', verdict);

  // ---------------- AC-9: golden rule, in the live DOM ----------------
  const domText = await page.evaluate(() => document.body.innerText);
  ok('AC-9 bestScore absent from the rendered DOM',
     !/bestScore/i.test(domText));

  // Let the mission replay reach station before capturing. The phantom rows
  // appear the instant the verdict lands, but the replay runs for FLIGHT_S =
  // 13 s and the phantoms are not on station until SPAWN_END = 0.48 of it
  // (~6.2 s). Screenshotting before that captures a transient and makes the
  // settled scene look wrong. Kept just past the spawn window, not the whole
  // flight, so the run does not pay 13 s for a picture.
  await new Promise((r) => setTimeout(r, 7500));
  await page.screenshot({ path: 'screenshots/console-live.png' });
  await finish(browser, page, consoleErrors);
};

async function finish(browser, page, consoleErrors, offlineExpected = false) {
  // three.js/WebGL emits benign warnings headless; only real errors count.
  const real = consoleErrors.filter(
    (e) => !/SwiftShader|WebGL|GroupMarkerNotSet|Fallback|deprecat/i.test(e));

  let badUrls = (page.__failedUrls ?? []).filter((u) => !/favicon\.ico/i.test(u));
  if (offlineExpected) {
    // With the bridge deliberately down, a refused call to it is the CONDITION
    // UNDER TEST, not a defect. Matched by URL so this cannot mask a failure
    // to any OTHER host, and applied only in offline mode.
    badUrls = badUrls.filter((u) => !u.includes(new URL(BRIDGE).host));
  }

  ok('zero page errors', real.length === 0, real.slice(0, 3).join(' | '));
  ok('zero failed requests', badUrls.length === 0, badUrls.slice(0, 3).join(' | '));

  await browser.close();
  const failed = results.filter((r) => !r.pass);
  writeFileSync('screenshots/verify-console-live.json',
    JSON.stringify(results, null, 2));
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
  if (failed.length) {
    console.error('FAILED:\n' + failed.map((f) => '  ' + f.name).join('\n'));
    process.exit(1);
  }
  console.log('ALL GREEN');
}

main().catch((e) => { console.error('harness error:', e); process.exit(2); });
