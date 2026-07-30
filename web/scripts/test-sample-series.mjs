#!/usr/bin/env node
// Self-check for consoleFrame.sampleSeries -- the one piece of non-trivial
// logic added for the mission replay. It decides WHERE a phantom or a track
// is at a given mission time, and just as importantly whether it should be
// drawn at all, so the boundaries are the part worth pinning.
//
// Run: node scripts/test-sample-series.mjs

import assert from 'node:assert/strict';
import { sampleSeries, toFrame } from '../src/lib/consoleFrame.js';

const t = [0, 1, 2, 3];
const r = [100, 110, 120, 130];

// interior + exact samples
assert.equal(sampleSeries(t, r, 0), 100);
assert.equal(sampleSeries(t, r, 3), 130);
assert.equal(sampleSeries(t, r, 1.5), 115);

// OUTSIDE the sampled window is null, never an extrapolation. A track held
// for 4 of 8 frames must vanish on the other four rather than coast on a
// straight line the radar never measured.
assert.equal(sampleSeries(t, r, -0.001), null);
assert.equal(sampleSeries(t, r, 3.001), null);

// GAPS are honoured: a coasted frame leaves a hole in the time base, and the
// value at the far side must come from the far sample, not from an assumed
// uniform grid. Here the 1 s..5 s gap means t=3 is the midpoint of 110->120.
assert.equal(sampleSeries([0, 1, 5], [100, 110, 120], 3), 115);

// degenerate / absent inputs never throw and never fabricate
assert.equal(sampleSeries(null, r, 1), null);
assert.equal(sampleSeries([], [], 0), null);
assert.equal(sampleSeries(t, [1, 2], 1), null);      // mismatched lengths
assert.equal(sampleSeries([2], [77], 2), 77);        // single sample, at it
assert.equal(sampleSeries([2], [77], 2.5), null);    // single sample, past it

// A payload with no truth_track (older backend, or the exported frame log)
// must still produce a renderable frame -- the scene falls back to parking
// each phantom at its t=0 range exactly as it did before.
const bare = toFrame({
  scene: { phantoms: [{ range_m: 500, radial_vel_mps: 3 }] },
  feedback: { track_label: ['decoy'], track_range_m: [[510, 512]] },
});
assert.equal(bare.mission, null);
assert.deepEqual(bare.truth.phantoms[0].pos, [500, 0, 0]);
assert.deepEqual(bare.truth.phantoms[0].rangeSeries, []);
assert.deepEqual(bare.radar.tracks[0].timeS, []);    // no track_time_s -> no faked grid

// With truth_track, the mission clock and per-phantom trajectory come through.
const full = toFrame({
  scene: { phantoms: [{ range_m: 500, radial_vel_mps: 10 }] },
  feedback: { track_label: ['decoy'], track_range_m: [[510, 515]], track_time_s: [[0, 2]] },
  truth_track: { time_s: [0, 1, 2], frame_interval_s: 1, range_m: [[500, 510, 520]] },
});
assert.equal(full.mission.durationS, 2);
assert.deepEqual(full.truth.phantoms[0].rangeSeries, [500, 510, 520]);
assert.deepEqual(full.radar.tracks[0].timeS, [0, 2]);
assert.equal(sampleSeries(full.mission.timeS, full.truth.phantoms[0].rangeSeries, 1.5), 515);

console.log('PASS: sampleSeries boundaries, gaps, and the no-truth_track fallback.');
