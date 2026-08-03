// bridge.js -- the ONLY place this client talks to the backend.
//
// The client renders scene + feedback. It never computes physics: no
// detection, no tracking, no screening. Everything numeric on screen arrived
// over HTTP from the real Python planner and the real MATLAB judge.
//
// HONESTY CONTRACT: a 503 from /score or /run means the judge could not run.
// This module surfaces that as `judgeOffline` and NEVER substitutes a result.
// A console that invents a verdict when the judge is down looks exactly like
// one that works, which is what makes it dangerous.

const BASE = import.meta.env?.VITE_BRIDGE ?? 'http://127.0.0.1:8000';

export class JudgeOfflineError extends Error {
  constructor(reason) {
    super(reason || 'judge unavailable');
    this.name = 'JudgeOfflineError';
    this.judgeOffline = true;
  }
}

async function post(path, body) {
  let res;
  try {
    res = await fetch(BASE + path, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  } catch (e) {
    // Bridge itself unreachable -- also an offline state, not a zero result.
    throw new JudgeOfflineError(`bridge unreachable at ${BASE}: ${e.message}`);
  }
  if (res.status === 503) {
    const d = await res.json().catch(() => ({}));
    throw new JudgeOfflineError(d?.detail?.reason || d?.detail?.error);
  }
  if (!res.ok) throw new Error(`${path} -> HTTP ${res.status}: ${await res.text()}`);
  return res.json();
}

// The backend's own physical facts (c, fs, and everything derived from them).
// Phase A2: these used to be typed into Console.jsx as finished numbers. The
// client must never carry its own copy of a constant the backend derives --
// same rule that put +physics/Constants.m and cogengine/radar_params.py in
// charge on their respective sides. Returns null when the bridge is down; the
// caller renders "--" rather than substituting a remembered value.
export const constants = async () => {
  try {
    const r = await fetch(BASE + '/constants');
    return r.ok ? r.json() : null;
  } catch {
    return null;
  }
};

export const health = async () => {
  try {
    const r = await fetch(BASE + '/health');
    return r.json();
  } catch (e) {
    return { judge_online: false, judge_error: `bridge unreachable: ${e.message}` };
  }
};

// Plans a scene WITHOUT scoring it. Cheap to re-render, but still a real
// planner run -- measured ~66 s at N=2, so this is a button, not a slider.
export const plan = (radarState, opts) => post('/plan', { radarState, opts });

// Scores an EXISTING scene. ~10 s. Use this when only the radar changed --
// re-planning an unchanged scene wastes a minute for the same answer.
export const score = (scene, radarState, opts) =>
  post('/score', { scene, radarState, opts });

export const run = (radarState, opts) => post('/run', { radarState, opts });
