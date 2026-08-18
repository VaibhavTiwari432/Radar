#!/usr/bin/env node
// Step 11's acceptance criterion (MISSION_SIMULATOR_UI_SPEC.md Section 9):
// "Renders the exported log. Contains zero physics computation -- verified
// by a test that the JS bundle has no detection/tracking code."
//
// Modeled directly on tests/test_package_separation.m's approach: scan
// source text for tokens that would indicate this client re-implements
// detection/tracking/planning logic instead of just rendering an
// already-computed frame log, and prove the checker itself catches a
// planted violation (that file's own Rule-3-style self-test), not just
// that the real source happens to be clean.

import { readdirSync, statSync, readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const BANNED = [
  [/CFARDetector/i, 'CFAR detector construction'],
  [/\bcfar(Threshold|Detect|NumTraining|NumGuard)\b/i, 'CFAR threshold/detection logic'],
  [/trackerGNN/i, 'GNN tracker construction'],
  [/new\s+KalmanFilter/i, 'Kalman filter instantiation'],
  [/kalman(Predict|Update)/i, 'Kalman filter math'],
  [/\bdiscriminator\s*\(/i, 'ECCM discriminator re-implementation'],
  [/computeEccmScreens\s*\(/i, 'ECCM screen re-computation'],
  [/localMaxPeaks/i, 'peak-detection re-implementation'],
  [/mahalanobis/i, 'gating/assignment math'],
  [/cross-entropy|planner_cem|\bCEM\b/i, 'CEM planner re-implementation'],
  [/py\.cogengine/i, 'calling into the Python backend from the client'],
  // A re-typed constant is the same failure as re-implemented physics: it was
  // right the day it was typed and silently wrong the moment fs or the PRF
  // moved. Console.jsx really did carry `prf_hz: 50000` and a "10 GHz" string
  // long after +physics/Constants.m went to 8 kHz, implying R_ua = 2998 m
  // against the real 18737 m. GET /constants derives all of these.
  [/\b(prf_hz|pri_s|carrier_hz)\s*:\s*[\d.]/, 'backend constant re-typed as a client literal'],
  // `\d\s*GHz` on purpose, not `[\d.]+\s*GHz`: "10 GHz" is a hardcoded
  // carrier, `${(consts.carrier_hz / 1e9).toFixed(1)} GHz` is a unit suffix on
  // a fetched value and must stay legal.
  [/\d\s*GHz/, 'carrier frequency hardcoded in the UI'],
  [/\b(46\.84|2997\.9|18737|1798\.7)/, 'a value GET /constants derives, pasted as a literal'],
];

// Math.random() is deliberately NOT banned here: bundled vendor code (React
// assigns DOM listener/fiber keys via Math.random().toString(36); three.js's
// MathUtils carries a generateUUID/Vector.random() utility) matches it on
// sight in any built bundle, regardless of whether this project's own code
// ever calls it. Scoped instead to algorithmic terms specific enough not to
// collide with dependency internals -- the same scope test_package_
// separation.m uses (it never scans MathWorks toolbox source, only this
// project's own +packages).

function walk(dir, exts, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const s = statSync(p);
    if (s.isDirectory()) {
      if (name === 'node_modules' || name === '.git') continue;
      walk(p, exts, out);
    } else if (exts.some((e) => name.endsWith(e))) {
      out.push(p);
    }
  }
  return out;
}

// Whole-line comments are dropped before matching. This file's own headers
// quote the stale numbers they exist to warn about ("Console.jsx carried
// prf_hz = 50000 and a 10 GHz string"), and a checker that flags the warning
// as the violation forces the history to be deleted to stay green -- the
// opposite of CLAUDE.md Rule 5. Only FULL-line comments go: a trailing `//`
// could be inside a string ('http://...') and stripping those would blind the
// scan to real code after it.
const stripComments = (text) => text
  .split('\n')
  .map((l) => (/^\s*(\/\/|\*|\/\*)/.test(l) ? '' : l))
  .join('\n');

function scan(dir, exts) {
  const violations = [];
  for (const file of walk(dir, exts)) {
    const text = stripComments(readFileSync(file, 'utf8'));
    for (const [pattern, label] of BANNED) {
      const m = text.match(pattern);
      if (m) violations.push(`${file}: matched /${pattern.source}/ (${label}) near "${m[0]}"`);
    }
  }
  return violations;
}

// Self-test: prove the checker actually catches a planted violation before
// trusting a clean result on the real tree.
function selfTest() {
  const tmp = mkdtempSync(join(tmpdir(), 'verify-no-physics-selftest-'));
  writeFileSync(join(tmp, 'bad.js'), 'export function f() { return new KalmanFilter(); }\n');
  // The two constant bans get their own planted violation, since a pattern
  // that never fires reads exactly like a clean tree.
  writeFileSync(join(tmp, 'stale.js'), 'export const radar = { prf_hz: 50000 };\nconst car = "10 GHz";\n');
  // ...and one file where the SAME text is a comment, proving the ban does not
  // cost this repo the ability to document what it fixed.
  writeFileSync(join(tmp, 'doc.js'), '// was prf_hz: 50000 and "10 GHz" -- see /constants\nexport const x = 1;\n');
  const found = scan(tmp, ['.js']);
  rmSync(tmp, { recursive: true, force: true });
  const hit = (f) => found.some((v) => v.includes(f));
  if (!hit('bad.js') || !hit('stale.js')) {
    console.error('FAIL: self-test did not catch a planted violation. Checker is broken.');
    process.exit(1);
  }
  if (hit('doc.js')) {
    console.error('FAIL: self-test flagged a COMMENT as a violation. Checker would force history to be deleted.');
    process.exit(1);
  }
  console.log('PASS: self-test -- catches planted code violations, ignores the same text in comments.');
}

function main() {
  selfTest();

  const targets = [
    { dir: join(process.cwd(), 'src'), exts: ['.js', '.jsx'], label: 'source (src/)' },
    { dir: join(process.cwd(), 'dist'), exts: ['.js'], label: 'built bundle (dist/)' },
  ];

  let anyChecked = false;
  let allViolations = [];
  for (const t of targets) {
    try {
      statSync(t.dir);
    } catch {
      console.log(`SKIP: ${t.label} not found (run "npm run build" to produce dist/).`);
      continue;
    }
    anyChecked = true;
    const violations = scan(t.dir, t.exts);
    if (violations.length) {
      allViolations = allViolations.concat(violations);
    } else {
      console.log(`PASS: ${t.label} -- no detection/tracking code found.`);
    }
  }

  if (!anyChecked) {
    console.error('FAIL: nothing was checked (neither src/ nor dist/ exist).');
    process.exit(1);
  }
  if (allViolations.length) {
    console.error('FAIL: banned patterns found:\n' + allViolations.join('\n'));
    process.exit(1);
  }
  console.log('PASS: Step 11 acceptance criterion -- zero physics/detection/tracking code.');
}

main();
