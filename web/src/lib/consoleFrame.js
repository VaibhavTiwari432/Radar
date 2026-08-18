// consoleFrame.js -- adapt a live {scene, feedback, attribution} response into
// the frame shape Scene3DHiFi already renders.
//
// WHY ADAPT INSTEAD OF WRITING A NEW RENDERER: Scene3DHiFi is validated
// (tests/test_missionsim_lifecycle_rendering.m plus a scripted headless pass).
// Rewriting it to take a different prop shape would throw that away to save a
// 40-line mapping. The mapping is the cheap side.
//
// This file does NO physics. It reindexes values that already came from the
// backend. Every range here was measured by the judge or planned by the
// engine; nothing is computed from a model on this side.

export const STATUS_COLOR = {
  confirmed: '#7ee787',   // fooled the tracker AND survived the screens
  flagged: '#ffab2e',     // tracked, then rejected
  undetected: '#3d4d5b',  // never confirmed at all
};

function asList(x) {
  if (x === null || x === undefined) return [];
  return Array.isArray(x) ? x : [x];
}

function meanOf(x) {
  const xs = asList(x).map(Number).filter(Number.isFinite);
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : NaN;
}

const nums = (x) => asList(x).map(Number).filter(Number.isFinite);

/**
 * @param {object} resp  the /run response: {scene, feedback, attribution, truth_track}
 * @returns {object} frame consumable by Scene3DHiFi
 */
export function toFrame(resp) {
  const scene = resp?.scene ?? { phantoms: [] };
  const fb = resp?.feedback ?? {};
  const status = asList(resp?.attribution?.per_phantom_status);
  const tt = resp?.truth_track ?? null;

  // MISSION CLOCK. Both series below are sampled against this one time base,
  // which is the judge's own: runJudge times frame k at (k-1)*frame_interval_s
  // and server/app.py's _truth_track uses the same. Without it the scene has
  // no time axis and every object sits at its t=0 range forever.
  const timeS = nums(tt?.time_s);
  const mission = timeS.length
    ? { timeS, durationS: timeS[timeS.length - 1], frameIntervalS: Number(tt.frame_interval_s) || 0 }
    : null;

  // Truth side: where the ENGINE planned each phantom, frame by frame.
  // rangeSeries is the trajectory the exporter actually rendered (DERIVED,
  // server-side); pos stays as the t=0 range so anything reading a single
  // scalar still gets the value it always got.
  // ampSeries is the amplitude the projection derived for those same ranges
  // from the two-way radar equation (server-side, DERIVED). The scene dict has
  // no amp_scale to read: the rebuilt generator derives amplitude instead of
  // letting a planner pick it.
  const truthRanges = asList(tt?.range_m);
  const truthAmps = asList(tt?.amplitude_sim);
  const phantoms = asList(scene.phantoms).map((p, i) => {
    const amp = nums(truthAmps[i]);
    return {
      id: `T${i + 1}`,
      pos: [Number(p.range_m) || 0, 0, 0],
      rangeSeries: nums(truthRanges[i]),
      ampSeries: amp,
      ampSim: amp.length ? amp[0] : NaN,
      status: status[i] ?? 'undetected',
      class: p.class,
      radialVelMps: Number(p.radial_vel_mps) || 0,
    };
  });

  // Radar side: what the JUDGE actually confirmed.
  //
  // rangeSeries/timeS are the track's own MEASURED hits, kept paired. They
  // are NOT resampled onto the frame grid: a track has one hit per DETECTED
  // frame, so a coast leaves a real gap in timeS, and closing it would
  // animate the track through moments the radar was not holding it.
  // rangeEst (the series mean) is retained for callers that want one number.
  const labels = asList(fb.track_label);
  const ranges = asList(fb.track_range_m);
  const times = asList(fb.track_time_s);
  const tracks = labels.map((lbl, i) => {
    const r = nums(ranges[i]);
    const t = nums(times[i]);
    return {
      id: i + 1,
      state: 'CONFIRMED',      // this payload carries confirmed tracks only
      misses: 0,
      rangeEst: meanOf(ranges[i]),
      rangeSeries: r,
      // Older payloads predate track_time_s. Fall back to the frame grid and
      // say so, rather than silently pretending the hits were contiguous.
      timeS: t.length === r.length ? t : [],
      label: String(lbl),
    };
  });

  return {
    mission,
    truth: { phantoms },
    radar: {
      tracks,
      tracker: { deleteMofN: [5, 5] },
    },
  };
}

/**
 * Value of `values` at mission time `t`, given the times its samples were
 * taken at. Returns null OUTSIDE the sampled window, which is the point: a
 * track that was only held for 4 of 8 frames must not be drawn on the other
 * four, and a linear extrapolation past its last hit would be an invention.
 *
 * Between two samples this interpolates. That is display interpolation
 * between two real values -- the same thing a line chart does joining two
 * points -- not a motion model: it can only ever produce values bracketed by
 * measurements that actually happened.
 */
export function sampleSeries(timeS, values, t) {
  if (!timeS?.length || timeS.length !== values?.length) return null;
  if (t < timeS[0] || t > timeS[timeS.length - 1]) return null;
  let i = 1;
  while (i < timeS.length && timeS[i] < t) i += 1;
  const t0 = timeS[i - 1], t1 = timeS[i] ?? t0;
  const v0 = values[i - 1], v1 = values[i] ?? v0;
  return t1 > t0 ? v0 + ((v1 - v0) * (t - t0)) / (t1 - t0) : v0;
}

/** Provenance-tagged identity block Scene3DHiFi reads for its range rings. */
export function toIdentity(constants) {
  return {
    rangeCellM: { value: constants.rangeCellM, unit: 'm', provenance: 'DERIVED' },
    unambigRangeM: { value: constants.unambigRangeM, unit: 'm', provenance: 'DERIVED' },
  };
}

/** Headline numbers, each tagged so the UI can never render an untagged one. */
export function scoreboard(fb) {
  const n = (v) => (Number.isFinite(Number(v)) ? Number(v) : null);
  return [
    { key: 'confirmed_tracks', label: 'Confirmed tracks',
      value: n(fb?.confirmed_tracks), unit: '', provenance: 'MEASURED' },
    { key: 'false_tracks_surviving', label: 'False tracks surviving',
      value: n(fb?.false_tracks_surviving), unit: '', provenance: 'MEASURED',
      headline: true },
    { key: 'flagged_decoys', label: 'Flagged decoys',
      value: n(fb?.flagged_decoys), unit: '', provenance: 'MEASURED' },
    { key: 'mean_track_lifetime_frames', label: 'Mean track lifetime',
      value: n(fb?.mean_track_lifetime_frames), unit: 'frames', provenance: 'MEASURED' },
    { key: 'doppler_source', label: 'Doppler',
      value: fb?.doppler_source ?? null, unit: '', provenance: 'MEASURED' },
    { key: 'angle_source', label: 'Angle',
      value: fb?.angle_source ?? null, unit: '', provenance: 'MEASURED' },
  ];
}
