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

function scan(dir, exts) {
  const violations = [];
  for (const file of walk(dir, exts)) {
    const text = readFileSync(file, 'utf8');
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
  const found = scan(tmp, ['.js']);
  rmSync(tmp, { recursive: true, force: true });
  if (found.length === 0) {
    console.error('FAIL: self-test did not catch a planted "new KalmanFilter()" violation. Checker is broken.');
    process.exit(1);
  }
  console.log('PASS: self-test -- checker catches a planted violation.');
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
