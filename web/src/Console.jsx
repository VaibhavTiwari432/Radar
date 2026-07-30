// Console.jsx -- LIVE mission console. Controls here cause real execution:
// every number on screen came back from the Python planner and the MATLAB
// judge over the bridge. Nothing is animated independently of a real cycle.
//
// This client computes NO physics (enforced by scripts/verify-no-physics.mjs).
//
// LATENCY, MEASURED, AND WHY THERE IS A RUN BUTTON:
//   judge call ~0.75 s warm | /score ~10 s | /plan ~66 s at N=2
// The build spec assumed the judge would be the bottleneck and prescribed a
// debounce on slider drags. It is the planner that costs. A 400 ms debounce
// cannot rescue a 66 s search, so controls stage changes and RUN commits them.
//
// WHICH CONTROLS ARE REAL. Every knob in the left column maps to a field
// server/app.py actually accepts (OptsIn / RadarStateIn). Amplitude profile,
// phase profile and trajectory pattern are deliberately NOT controls: the
// planner decides amp_scale and radial_vel_mps itself, and there is no
// azimuth anywhere on this path, so offering them as inputs would be three
// dials wired to nothing. They appear instead under ENGINE OUTPUT, which is
// what they are.

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertTriangle, Play, Square, RotateCcw, Gauge, Loader, Radar,
  Cpu, Activity, Waves, Move3d, Hand, Search, Crosshair, HelpCircle,
  Settings, Bell, User, Minus, Maximize2, X, FilePlus2, FolderOpen, Save,
  Library, LayoutGrid, Eye,
} from 'lucide-react';
import { C, MONO } from './theme.js';
import {
  PanelHead, Row, RibbonBtn, Sep, Slider, Segmented,
} from './components/Chrome.jsx';
import Scene3DHiFi from './components/Scene3DHiFi.jsx';
import PPIScope from './components/PPIScope.jsx';
import BlockChain from './components/BlockChain.jsx';
import * as bridge from './lib/bridge.js';
import { toFrame, toIdentity, scoreboard, STATUS_COLOR } from './lib/consoleFrame.js';

// DERIVED from the backend's own constants (c and fs). Mirrored here only for
// the 3D range rings and the PPI graticule; the values are not invented here.
const RANGE_CELL_M = 46.8426;
const UNAMBIG_M = 2997.9;
const CEIL_M = RANGE_CELL_M * 512;
const IDENTITY = toIdentity({ rangeCellM: RANGE_CELL_M, unambigRangeM: UNAMBIG_M });

const MANEUVERS = ['static', 'rgpo', 'vgpo', 'swarm'];
const MODES = ['OFF', 'MANUAL', 'D3QN'];

// BlockChain's own phase vocabulary. Mapped from the real request lifecycle,
// not from a clock.
const PHASE_BLOCK = { idle: 'INGRESS', planning: 'ENGINE_ACTIVE', verdict: 'DECEPTION_HOLDING' };
const PHASE_TEXT = {
  idle: ['STANDBY', 'Engine cold — nothing planned, nothing flying'],
  planning: ['SEARCHING', 'Planner running, then the MATLAB judge — scene held still'],
  // 1x and looping: the transit is stretched to hold exactly the mission's
  // own duration, so there is no playback-rate caveat to make, and it repeats
  // because a one-shot replay ~13 s into a ~76 s wait is one nobody sees.
  verdict: ['MISSION REPLAY', 'Judge has ruled; the scored engagement replays at 1x, looping'],
};

function Prov({ p }) {
  const col = { MEASURED: C.green, DERIVED: C.cyan, ASSUMED: C.amber, UNVALIDATED: C.red }[p] ?? C.faint;
  return <span style={{ fontSize: 7, color: col, marginLeft: 5, letterSpacing: 0.5 }}>{p}</span>;
}

function Panel({ title, right, children, flex }) {
  return (
    <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4,
      display: 'flex', flexDirection: 'column', flex: flex ? 1 : 'none', minHeight: 0 }}>
      <PanelHead right={right}>{title}</PanelHead>
      <div style={{ padding: 10, overflowY: 'auto', minHeight: 0 }}>{children}</div>
    </div>
  );
}

export default function Console() {
  const [judge, setJudge] = useState({ judge_online: null, judge_error: null });
  const [busy, setBusy] = useState(null);          // 'plan' | 'score' | null
  const [offline, setOffline] = useState(null);
  const [resp, setResp] = useState(null);
  const [err, setErr] = useState(null);
  const [verdictAt, setVerdictAt] = useState(null);   // spawn-animation origin
  // Verdict is the default tab: the summary reads before the detail, and the
  // live browser test asserts the verdict panel is populated after a RUN.
  const [tab, setTab] = useState('verdict');
  const [scaleKm, setScaleKm] = useState('auto');
  // Live positions reported BY the 3D scene. The scope plots these rather than
  // deriving its own, so the two views cannot disagree about where an object is.
  const [positions, setPositions] = useState(null);
  const onPositions = useCallback((p) => setPositions(p), []);
  const [elapsed, setElapsed] = useState(0);
  const labelHost = useRef(null);

  // staged controls -- committed on RUN, never on change
  const [opts, setOpts] = useState({
    n_phantoms: 3, seed: 1, interceptNoiseAmplitude: 2.0,
    maneuver: 'static', eirp_budget_dbw: 17.8, duration_s: 8.0, engine_mode: 'MANUAL',
  });
  const [radar, setRadar] = useState({
    mode: 'search', prf_hz: 50000, pri_s: 20e-6, carrier_hz: 10e9,
    range_gate_m: [0, 20000], vel_gate_mps: [-1000, 1000],
    scan_phase: 0, doubt_cue: 0,
  });

  useEffect(() => { bridge.health().then(setJudge); }, []);

  // Elapsed timer, so a 125 s plan reads as progress rather than a hang. It
  // counts the REAL wait; it does not predict a finish time, because the
  // planner is a search and its duration is not known in advance.
  useEffect(() => {
    if (!busy) return undefined;
    const t0 = Date.now();
    const id = setInterval(() => setElapsed((Date.now() - t0) / 1000), 100);
    return () => clearInterval(id);
  }, [busy]);

  const frame = useMemo(() => (resp ? toFrame(resp) : null), [resp]);
  const board = useMemo(() => scoreboard(resp?.feedback), [resp]);
  const phase = busy === 'plan' ? 'planning' : (resp ? 'verdict' : 'idle');
  const scenePhantoms = resp?.scene?.phantoms ?? [];

  // PPI targets: range MEASURED, azimuth only if the judge actually reported
  // one. track_azimuth_mean is null on a sum-channel-only export.
  const azList = resp?.feedback?.track_azimuth_mean;
  const ppiTargets = (frame?.truth.phantoms ?? []).map((p, i) => {
    const ti = resp?.attribution?.phantom_track_index?.[i];
    const azRaw = Array.isArray(azList) ? azList[ti] : (ti === 0 ? azList : null);
    return {
      id: p.id, rangeM: Array.isArray(p.pos) ? p.pos[0] : 0, status: p.status,
      azDeg: Number.isFinite(azRaw) ? azRaw : null,
    };
  });
  const measuredAz = ppiTargets.some((t) => Number.isFinite(t.azDeg));

  async function doRun() {
    setBusy('plan'); setErr(null); setOffline(null); setElapsed(0);
    try {
      const r = await bridge.run(radar, opts);
      setResp(r);
      setVerdictAt(Date.now());     // starts the spawn in BOTH views at once
    } catch (e) {
      if (e.judgeOffline) setOffline(e.message); else setErr(e.message);
    } finally { setBusy(null); bridge.health().then(setJudge); }
  }

  async function doScore() {
    if (!resp?.scene) return;
    setBusy('score'); setErr(null); setOffline(null); setElapsed(0);
    try {
      const r = await bridge.score(resp.scene, radar, opts);
      setResp({ ...resp, feedback: r.feedback });
    } catch (e) {
      if (e.judgeOffline) setOffline(e.message); else setErr(e.message);
    } finally { setBusy(null); }
  }

  function resetRun() { setResp(null); setVerdictAt(null); setErr(null); setOffline(null); }

  const engineOwned = opts.engine_mode !== 'MANUAL';
  const judgeDown = offline || judge.judge_online === false;
  const set = (k, v) => setOpts((o) => ({ ...o, [k]: v }));

  return (
    <div style={{ background: C.void, color: C.txt, fontFamily: MONO, minHeight: '100vh',
      display: 'flex', flexDirection: 'column', userSelect: 'none' }}>

      {/* ---------------- title ---------------- */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '7px 12px',
        background: C.ribbon, borderBottom: `1px solid ${C.line}` }}>
        <div style={{ width: 20, height: 20, borderRadius: 4, background: 'linear-gradient(135deg,#2ee06a,#0f6b3a)',
          display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Move3d size={12} color="#05140b" strokeWidth={2.4} />
        </div>
        <div style={{ fontSize: 12.5, fontWeight: 700, letterSpacing: 1 }}>LIVE MISSION CONSOLE</div>
        <div style={{ fontSize: 9, color: C.faint }}>HAC-2026-1166</div>
        <div style={{ flex: 1 }} />
        <div style={{ display: 'flex', gap: 12, color: C.dim }}>
          <HelpCircle size={13} /><Settings size={13} /><Bell size={13} /><User size={13} />
          <Minus size={13} /><Maximize2 size={12} /><X size={13} />
        </div>
      </div>

      {/* ---------------- tab strip ---------------- */}
      <div style={{ display: 'flex', background: C.ribbon, borderBottom: `1px solid ${C.line}`, paddingLeft: 8 }}>
        {['MISSION', 'ENGINE', 'JUDGE', 'ANALYSIS'].map((tb, i) => (
          <div key={tb} style={{ padding: '6px 14px', fontSize: 9.5, letterSpacing: 0.7,
            color: i === 0 ? C.green : C.dim, borderBottom: i === 0 ? `2px solid ${C.green}` : '2px solid transparent',
            background: i === 0 ? C.app : 'transparent' }}>{tb}</div>
        ))}
      </div>

      {/* ---------------- ribbon ---------------- */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 2, padding: '6px 10px',
        background: C.app, borderBottom: `1px solid ${C.line}`, flexWrap: 'wrap' }}>
        <RibbonBtn icon={FilePlus2} label="New" onClick={resetRun} />
        <RibbonBtn icon={FolderOpen} label="Open" disabled />
        <RibbonBtn icon={Save} label="Save" disabled />
        <Sep />
        <RibbonBtn icon={Library} label="Library" wide disabled />
        <RibbonBtn icon={Activity} label="Log" wide disabled />
        <Sep />
        <button onClick={doRun} disabled={!!busy} data-testid="run-btn"
          style={{ background: busy ? C.ribbonHi : C.greenDim, color: C.txt, border: `1px solid ${C.line}`,
            padding: '6px 16px', fontFamily: MONO, fontSize: 11, borderRadius: 3,
            cursor: busy ? 'wait' : 'pointer', display: 'flex', alignItems: 'center', gap: 6 }}>
          {busy === 'plan' ? <Loader size={12} /> : <Play size={12} />}
          {busy === 'plan' ? `PLANNING… ${elapsed.toFixed(0)}s` : 'RUN  (plan + judge)'}
        </button>
        <button onClick={doScore} disabled={!!busy || !resp}
          style={{ background: C.ribbonHi, color: resp ? C.txt : C.faint, border: `1px solid ${C.line}`,
            padding: '6px 12px', fontFamily: MONO, fontSize: 11, borderRadius: 3, marginLeft: 4,
            cursor: busy || !resp ? 'not-allowed' : 'pointer', display: 'flex', alignItems: 'center', gap: 6 }}>
          {busy === 'score' ? <Loader size={12} /> : <Gauge size={12} />}RE-JUDGE
        </button>
        <RibbonBtn icon={Square} label="Clear" onClick={resetRun} />
        <RibbonBtn icon={RotateCcw} label="Replay" wide onClick={() => resp && setVerdictAt(Date.now())} />
        <Sep />
        <RibbonBtn icon={LayoutGrid} label="Analyzer" wide disabled />
        <RibbonBtn icon={Eye} label="Bird's-Eye" wide disabled />
        <div style={{ flex: 1 }} />
        <div style={{ border: `1px solid ${C.line}`, borderRadius: 4, padding: '5px 12px',
          background: C.panel, fontSize: 9.5, lineHeight: 1.65, minWidth: 210 }}>
          <Row k="Judge" v={judge.judge_online ? 'ONLINE' : judge.judge_online === false ? 'OFFLINE' : '…'}
            vc={judge.judge_online ? C.green : C.red} />
          <Row k="Phase" v={PHASE_TEXT[phase][0]} vc={C.amber} />
          <Row k="Elapsed" v={busy ? `${elapsed.toFixed(1)} s` : '—'} />
        </div>
      </div>

      {/* ---------------- JUDGE OFFLINE banner (AC-6) ---------------- */}
      {judgeDown && (
        <div data-testid="judge-offline" style={{ display: 'flex', alignItems: 'center', gap: 8,
          padding: '6px 14px', background: '#3a0d0d', borderBottom: `1px solid ${C.red}`,
          color: '#ff9f9f', fontSize: 10.5 }}>
          <AlertTriangle size={13} /><b>JUDGE OFFLINE</b>
          <span style={{ opacity: 0.85 }}>— no verdict is being shown. {offline || judge.judge_error || ''}</span>
        </div>
      )}
      {err && (
        <div style={{ padding: '5px 14px', background: '#3a2a0d', color: C.amber, fontSize: 10 }}>
          bridge error — {err}
        </div>
      )}

      {/* ---------------- body ---------------- */}
      <div style={{ display: 'flex', gap: 6, padding: 6, flex: 1, minHeight: 0 }}>

        {/* LEFT — controls that really reach the backend */}
        <div style={{ width: 232, flexShrink: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
          <Panel title="MOTHER DRONE — CONTROL" right={<Cpu size={11} color={C.dim} />}>
            <Segmented label="Hallucination engine" value={opts.engine_mode} options={MODES}
              onChange={(v) => set('engine_mode', v)} />
            <div style={{ fontSize: 7.5, color: C.faint, marginBottom: 8, lineHeight: 1.45 }}>
              {opts.engine_mode === 'OFF'
                ? 'OFF plans ZERO phantoms. The judge confirming nothing is a negative-control result, not an empty screen.'
                : opts.engine_mode === 'D3QN'
                  ? 'D3QN owns the phantom set — count stays yours, the rest is the agent’s.'
                  : 'MANUAL — the planner searches within the budget you set.'}
            </div>
            <Slider label="Phantom count N" value={opts.n_phantoms} min={0} max={5} step={1}
              onChange={(v) => set('n_phantoms', v)} disabled={opts.engine_mode === 'OFF'}
              note="Population scales 36×N — larger N costs real search time." />
            <Segmented label="Maneuver" value={opts.maneuver} options={MANEUVERS}
              onChange={(v) => set('maneuver', v)} disabled={engineOwned} />
            <Slider label="Intercept noise" value={opts.interceptNoiseAmplitude.toFixed(1)}
              min={0.5} max={4} step={0.1} onChange={(v) => set('interceptNoiseAmplitude', v)}
              note="2.0 = the validated operating point." />
            <Slider label="EIRP budget" value={opts.eirp_budget_dbw.toFixed(1)} unit=" dBW"
              min={10} max={26} step={0.1} onChange={(v) => set('eirp_budget_dbw', v)}
              note="Shared across all N — a real physical constraint." />
            <Slider label="Duration" value={opts.duration_s.toFixed(1)} unit=" s"
              min={2} max={16} step={0.5} onChange={(v) => set('duration_s', v)} />
            <Slider label="Seed" value={opts.seed} min={1} max={40} step={1}
              onChange={(v) => set('seed', v)} note="Seeded RNG only — runs reproduce." />
          </Panel>

          <Panel title="RADAR" right={<Radar size={11} color={C.dim} />}>
            <Slider label="Doubt cue" value={radar.doubt_cue.toFixed(2)} min={0} max={1} step={0.01}
              onChange={(v) => setRadar((r) => ({ ...r, doubt_cue: v }))} />
            <Slider label="Range gate max" value={(radar.range_gate_m[1] / 1000).toFixed(1)} unit=" km"
              min={2} max={24} step={0.5}
              onChange={(v) => setRadar((r) => ({ ...r, range_gate_m: [0, v * 1000] }))} />
            <div style={{ marginTop: 8, fontSize: 9, lineHeight: 1.7 }}>
              <Row k="Range cell" v={`${RANGE_CELL_M.toFixed(1)} m`} />
              <Row k="Unambiguous" v={`${(UNAMBIG_M / 1000).toFixed(2)} km`} />
              <Row k="Record ceiling" v={`${(CEIL_M / 1000).toFixed(1)} km`} />
              <Row k="Carrier" v="10 GHz" vc={C.amber} />
            </div>
            <div style={{ fontSize: 7.5, color: C.faint, marginTop: 6, lineHeight: 1.45 }}>
              First three DERIVED from c and fs. Carrier is ASSUMED — RadChar is baseband.
            </div>
          </Panel>
        </div>

        {/* CENTRE — 3D + signal chain */}
        <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
          <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4,
            overflow: 'hidden', display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 8px',
              background: C.panelHead, borderBottom: `1px solid ${C.line}` }}>
              <div style={{ background: C.app, border: `1px solid ${C.line}`, borderRadius: 2,
                padding: '2px 8px', fontSize: 9.5 }}>3D Scenario View</div>
              <div style={{ display: 'flex', gap: 9, color: C.faint }}>
                <Move3d size={12} /><Hand size={12} /><Search size={12} /><Crosshair size={12} />
              </div>
              <div style={{ flex: 1 }} />
              <span style={{ fontSize: 9, background: phase === 'verdict' ? C.green : C.ribbonHi,
                color: phase === 'verdict' ? '#04120a' : C.dim, padding: '2px 8px',
                borderRadius: 2, fontWeight: 700 }}>{PHASE_TEXT[phase][0]}</span>
              <span style={{ fontSize: 9, color: C.dim }}>{PHASE_TEXT[phase][1]}</span>
            </div>
            <div style={{ position: 'relative', flex: 1, minHeight: 380, cursor: 'grab' }} ref={labelHost}>
              <Scene3DHiFi frame={frame} identity={IDENTITY} labelHost={labelHost}
                phase={phase} verdictAt={verdictAt} onPositions={onPositions} />
              <div style={{ position: 'absolute', left: 10, top: 8, fontSize: 8.5, color: C.faint,
                pointerEvents: 'none' }}>drag to orbit · scroll to zoom</div>
              {!resp && (
                <div style={{ position: 'absolute', left: 0, right: 0, bottom: 16, textAlign: 'center',
                  color: C.faint, fontSize: 11, pointerEvents: 'none' }}>
                  {busy === 'plan'
                    ? 'SEARCHING — the scene is held still on purpose. Nothing flies until MATLAB returns a verdict.'
                    : 'press RUN — nothing is drawn until a real plan and a real verdict exist'}
                </div>
              )}
            </div>
          </div>
          <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4 }}>
            <PanelHead>SIGNAL CHAIN</PanelHead>
            <div style={{ padding: '2px 8px' }}><BlockChain phase={PHASE_BLOCK[phase]} /></div>
          </div>
        </div>

        {/* RIGHT — what the radar holds */}
        <div style={{ width: 300, flexShrink: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
          <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4 }}>
            <PanelHead right={<span style={{ color: C.faint, letterSpacing: 0 }}>read-only</span>}>
              PPI SCOPE — WHAT THE RADAR HOLDS
            </PanelHead>
            <div style={{ padding: '6px 8px 8px' }}>
              <PPIScope targets={positions?.phantoms ?? []} tracks={positions?.tracks ?? []}
                mother={positions?.mother ?? null}
                scaleKm={scaleKm} unambigKm={UNAMBIG_M / 1000} ceilKm={CEIL_M / 1000}
                measuredAz={measuredAz} />
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 6 }}>
                <span style={{ fontSize: 8.5, color: C.dim }}>Scale</span>
                {['auto', 6, 12, 24].map((s) => (
                  <button key={s} onClick={() => setScaleKm(s)}
                    style={{ fontSize: 8, padding: '2px 7px', borderRadius: 2, cursor: 'pointer',
                      background: scaleKm === s ? 'rgba(46,224,106,0.16)' : C.app,
                      border: `1px solid ${scaleKm === s ? C.green : C.line}`,
                      color: scaleKm === s ? C.green : C.dim }}>
                    {s === 'auto' ? 'AUTO' : `${s} km`}
                  </button>
                ))}
                <Prov p="DERIVED" />
              </div>
            </div>
          </div>

          <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4, flex: 1, minHeight: 0,
            display: 'flex', flexDirection: 'column' }}>
            <div style={{ display: 'flex', borderBottom: `1px solid ${C.line}` }}>
              {[['profile', 'RANGE', Activity], ['kin', 'KINEMATICS', Waves], ['verdict', 'VERDICT', Gauge]].map(([id, lbl, Ic]) => (
                <button key={id} onClick={() => setTab(id)}
                  style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4,
                    padding: '6px 2px', fontSize: 8, fontFamily: MONO, letterSpacing: 0.3, cursor: 'pointer',
                    background: tab === id ? C.app : 'transparent', border: 'none',
                    borderBottom: tab === id ? `2px solid ${C.green}` : '2px solid transparent',
                    color: tab === id ? C.green : C.dim }}>
                  <Ic size={11} />{lbl}
                </button>
              ))}
            </div>
            <div style={{ padding: '8px 10px', overflowY: 'auto', minHeight: 0 }}>
              {!resp && <div style={{ fontSize: 10, color: C.faint }}>no run yet</div>}

              {resp && tab === 'profile' && (
                <RangeStrip phantoms={ppiTargets} tracks={frame.radar.tracks} ceilM={CEIL_M} unambigM={UNAMBIG_M} />
              )}

              {resp && tab === 'kin' && (
                <KinematicsPlot phantoms={scenePhantoms} statuses={ppiTargets.map((t) => t.status)} />
              )}

              {resp && tab === 'verdict' && board.map((m) => (
                <Row key={m.key} k={m.label}
                  v={<span>{m.value === null ? '—' : `${m.value}${m.unit ? ' ' + m.unit : ''}`}<Prov p={m.provenance} /></span>}
                  vc={m.headline ? C.green : C.txt} />
              ))}
            </div>
          </div>

          <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4 }}>
            <PanelHead>PHANTOMS — ENGINE OUTPUT vs JUDGE</PanelHead>
            <div style={{ padding: '4px 8px 8px', fontSize: 8.5 }}>
              <div style={{ display: 'flex', color: C.faint, padding: '3px 0',
                borderBottom: `1px solid ${C.line}`, letterSpacing: 0.3 }}>
                <span style={{ width: 26 }}>ID</span>
                <span style={{ flex: 1 }}>RANGE</span>
                <span style={{ width: 48, textAlign: 'right' }}>v m/s</span>
                <span style={{ width: 34, textAlign: 'right' }}>amp</span>
                <span style={{ width: 58, textAlign: 'right' }}>STATUS</span>
              </div>
              {(resp ? ppiTargets : []).map((t, i) => {
                const sp = scenePhantoms[i] ?? {};
                return (
                  <div key={t.id} data-testid="phantom-row" data-status={t.status}
                    style={{ display: 'flex', padding: '3px 0', borderBottom: `1px solid ${C.lineSoft}` }}>
                    <span style={{ width: 26, color: STATUS_COLOR[t.status] ?? C.silver, fontWeight: 600 }}>{t.id}</span>
                    <span style={{ flex: 1, color: C.txt }}>{(t.rangeM / 1000).toFixed(2)} km</span>
                    <span style={{ width: 48, textAlign: 'right', color: C.dim }}>
                      {Number.isFinite(sp.radial_vel_mps) ? sp.radial_vel_mps.toFixed(0) : '—'}
                    </span>
                    <span style={{ width: 34, textAlign: 'right', color: C.dim }}>
                      {Number.isFinite(sp.amp_scale) ? sp.amp_scale.toFixed(2) : '—'}
                    </span>
                    <span style={{ width: 58, textAlign: 'right', color: STATUS_COLOR[t.status] ?? C.dim }}>
                      {t.status}
                    </span>
                  </div>
                );
              })}
              {resp && ppiTargets.length === 0 && (
                <div style={{ padding: '8px 0', color: C.faint, textAlign: 'center', lineHeight: 1.5 }}>
                  zero phantoms — negative control. The judge confirming nothing here is a result.
                </div>
              )}
              {!resp && <div style={{ padding: '8px 0', color: C.faint, textAlign: 'center' }}>engine cold</div>}
              <div style={{ fontSize: 7.5, color: C.faint, marginTop: 6, lineHeight: 1.45 }}>
                Range / v / amp are the PLANNER’s output. Status is DERIVED — scene truth matched
                against judge measurement, not something the judge reported.
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* ---------------- status bar ---------------- */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 20, padding: '5px 14px',
        background: C.ribbon, borderTop: `1px solid ${C.line}`, fontSize: 8.5, color: C.dim }}>
        <span style={{ color: busy ? C.amber : C.green }}>{busy ? 'Running' : 'Ready'}</span>
        <span>Engine: {opts.engine_mode}</span>
        <span>N: {resp ? ppiTargets.length : 0}</span>
        <span>Doppler: {resp?.feedback?.doppler_source ?? '—'}</span>
        <span>Angle: {resp?.feedback?.angle_source ?? '—'}</span>
        <div style={{ flex: 1 }} />
        <span style={{ color: C.faint }}>
          Every value on screen came from the real planner and the real judge — or is tagged otherwise.
        </span>
      </div>
    </div>
  );
}

/* ── range strip: planner ranges + the judge's own track ranges ────────── */
function RangeStrip({ phantoms, tracks, ceilM, unambigM }) {
  const W = 280, H = 96, PL = 12, PR = 12, y0 = 54;
  const maxM = Math.max(unambigM, ...phantoms.map((p) => p.rangeM),
    ...tracks.map((t) => (Number.isFinite(t.rangeEst) ? t.rangeEst : 0))) * 1.15;
  const px = (r) => PL + (r / maxM) * (W - PL - PR);
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: H, display: 'block' }}>
        <line x1={PL} y1={y0} x2={W - PR} y2={y0} stroke={C.line} strokeWidth={1} />
        {unambigM < maxM && (
          <g>
            <line x1={px(unambigM)} y1={y0 - 24} x2={px(unambigM)} y2={y0 + 10}
              stroke={C.amber} strokeWidth={1} strokeDasharray="3 2" opacity={0.8} />
            <text x={px(unambigM)} y={y0 + 20} fontSize={6.5} fill={C.amber}
              textAnchor="middle" fontFamily={MONO}>unambig</text>
          </g>
        )}
        <circle cx={PL} cy={y0} r={4} fill={C.green} />
        <text x={PL} y={y0 + 20} fontSize={6.5} fill={C.green} textAnchor="middle" fontFamily={MONO}>radar</text>
        {phantoms.map((p) => (
          <g key={p.id}>
            <line x1={px(p.rangeM)} y1={y0} x2={px(p.rangeM)} y2={y0 - 30}
              stroke={STATUS_COLOR[p.status] ?? C.silver} strokeWidth={1} opacity={0.5} strokeDasharray="2 2" />
            <circle cx={px(p.rangeM)} cy={y0 - 30} r={3.4} fill="none"
              stroke={STATUS_COLOR[p.status] ?? C.silver} strokeWidth={1.4} />
            <text x={px(p.rangeM)} y={y0 - 36} fontSize={7} fill={STATUS_COLOR[p.status] ?? C.silver}
              textAnchor="middle" fontFamily={MONO}>{p.id}</text>
          </g>
        ))}
        {tracks.map((t) => (Number.isFinite(t.rangeEst) && (
          <path key={t.id} d={`M${px(t.rangeEst)} ${y0 + 4} l3.4 6 l-6.8 0 z`} fill={C.cyan} opacity={0.9} />
        )))}
        <text x={PL} y={H - 3} fontSize={7} fill={C.faint} fontFamily={MONO}>0</text>
        <text x={W - PR} y={H - 3} fontSize={7} fill={C.faint} fontFamily={MONO} textAnchor="end">
          {(maxM / 1000).toFixed(1)} km
        </text>
      </svg>
      <div style={{ fontSize: 7.5, color: C.faint, marginTop: 4, lineHeight: 1.45 }}>
        Rings above the axis are PLANNED ranges; cyan carets below are the mean of each confirmed
        track’s own MEASURED range series. The gap between them is the judge’s error, drawn to scale.
      </div>
    </div>
  );
}

/* ── kinematics: the planner's real (range, radial velocity) pairs ──────
   NOT a range-Doppler map. A true RD surface is the judge's internal
   matched-filter output and is not on this payload, so drawing a heatmap
   here would be inventing one. These are the planned kinematics that WOULD
   place each phantom on such a surface. ───────────────────────────────── */
function KinematicsPlot({ phantoms, statuses }) {
  const W = 280, H = 130, PL = 30, PR = 10, PT = 10, PB = 24;
  const iw = W - PL - PR, ih = H - PT - PB;
  const rs = phantoms.map((p) => p.range_m ?? 0);
  const vs = phantoms.map((p) => p.radial_vel_mps ?? 0);
  const rMax = Math.max(1, ...rs) * 1.2;
  const vAbs = Math.max(40, ...vs.map(Math.abs)) * 1.2;
  const px = (r) => PL + (r / rMax) * iw;
  const py = (v) => PT + ih / 2 - (v / vAbs) * (ih / 2);
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: H, display: 'block' }}>
        <line x1={PL} y1={py(0)} x2={W - PR} y2={py(0)} stroke={C.amber} strokeWidth={0.8}
          strokeDasharray="3 3" opacity={0.6} />
        <text x={PL - 3} y={py(0) + 3} fontSize={6.5} fill={C.amber} textAnchor="end" fontFamily={MONO}>0</text>
        {[-1, 1].map((s) => (
          <text key={s} x={PL - 3} y={py(s * vAbs * 0.8) + 3} fontSize={6.5} fill={C.faint}
            textAnchor="end" fontFamily={MONO}>{(s * vAbs * 0.8).toFixed(0)}</text>
        ))}
        <line x1={PL} y1={PT} x2={PL} y2={PT + ih} stroke={C.line} strokeWidth={0.8} />
        {phantoms.map((p, i) => {
          const col = STATUS_COLOR[statuses[i]] ?? C.silver;
          const x = px(p.range_m ?? 0), y = py(p.radial_vel_mps ?? 0);
          const r = 3 + 3 * Math.min(1, (p.amp_scale ?? 1) / 4);
          return (
            <g key={i}>
              <line x1={x} y1={py(0)} x2={x} y2={y} stroke={col} strokeWidth={0.8} opacity={0.4} />
              <circle cx={x} cy={y} r={r} fill={col} opacity={0.25} />
              <circle cx={x} cy={y} r={r} fill="none" stroke={col} strokeWidth={1.4} />
              <text x={x} y={y - r - 3} fontSize={7} fill={col} textAnchor="middle" fontFamily={MONO}>T{i + 1}</text>
            </g>
          );
        })}
        <text x={W - PR} y={H - 4} fontSize={7} fill={C.faint} textAnchor="end" fontFamily={MONO}>range →</text>
        <text x={PL} y={H - 4} fontSize={7} fill={C.faint} fontFamily={MONO}>radial velocity ↑</text>
      </svg>
      <div style={{ fontSize: 7.5, color: C.faint, marginTop: 4, lineHeight: 1.45 }}>
        Planner output: range vs radial velocity, marker size ∝ amp_scale. This is NOT a
        range-Doppler map — that surface lives inside the judge and is not on this payload,
        so it is not drawn.
      </div>
    </div>
  );
}
