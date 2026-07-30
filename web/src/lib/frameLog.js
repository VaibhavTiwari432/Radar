// Pure data plumbing: normalizes and reshapes an already-computed frame log
// for rendering. Deliberately contains NO detection, tracking, CFAR, filter,
// or scoring logic -- every number here was already produced by the real
// MATLAB backend (+missionsim/buildFrameLog.m) before export. See
// scripts/verify-no-physics.mjs, which enforces this at build time.

// This project's own MATLAB jsonencode has a documented gotcha (see
// +missionsim/buildFrameLog.m's header and CLAUDE.md's bug log): a struct
// array of length 1 encodes as a bare JSON object, not a 1-element array.
// Any field that is schema-defined as a list must be defended the same way
// the MATLAB side already defends against union()'s orientation gotcha.
export function asList(x) {
  if (x === null || x === undefined) return [];
  return Array.isArray(x) ? x : [x];
}

export function normalizeFrame(f) {
  return {
    ...f,
    synth: { ...f.synth, phantoms: asList(f.synth?.phantoms) },
    truth: { ...f.truth, phantoms: asList(f.truth?.phantoms) },
    radar: { ...f.radar, tracks: asList(f.radar?.tracks) },
  };
}

export function normalizeFrameLog(raw) {
  return asList(raw).map(normalizeFrame);
}

export function validateShape(frames) {
  const errors = [];
  frames.forEach((f, i) => {
    if (typeof f.frame !== 'number') errors.push(`frame[${i}]: missing "frame" index`);
    if (typeof f.t !== 'number') errors.push(`frame[${i}]: missing "t"`);
    if (!f.radar?.identity) errors.push(`frame[${i}]: missing radar.identity`);
  });
  return errors;
}

// Reshapes the log into per-track time series (range estimate vs. frame) for
// the history chart. This is aggregation, not computation: every rangeEst
// value is copied verbatim from a frame the MATLAB judge already produced.
export function trackRangeSeries(frames) {
  const byId = new Map();
  frames.forEach((f) => {
    f.radar.tracks.forEach((tr) => {
      if (tr.state === 'DELETED' || !Number.isFinite(tr.rangeEst)) return;
      if (!byId.has(tr.id)) byId.set(tr.id, []);
      byId.get(tr.id).push({ t: f.t, v: tr.rangeEst });
    });
  });
  return byId;
}

// Confirmed-track count per frame -- a straight tally of state==='CONFIRMED',
// nothing inferred.
export function confirmedCountSeries(frames) {
  return frames.map((f) => ({
    t: f.t,
    v: f.radar.tracks.filter((tr) => tr.state === 'CONFIRMED').length,
  }));
}
