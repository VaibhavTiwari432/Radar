import React, { useEffect, useMemo, useRef, useState } from 'react';
import { Play, Pause, SkipForward, RotateCcw, FolderOpen, Move3d, AlertTriangle } from 'lucide-react';
import { C, MONO, STATE_COLOR } from './theme.js';
import { PanelHead, RibbonBtn, Sep, Dot, TRow, Big, Lg, Row } from './components/Chrome.jsx';
import LineChart from './components/LineChart.jsx';
import Scene3DHiFi from './components/Scene3DHiFi.jsx';
import RangeProfile from './components/RangeProfile.jsx';
import BlockChain from './components/BlockChain.jsx';
import { normalizeFrameLog, validateShape, trackRangeSeries, confirmedCountSeries } from './lib/frameLog.js';

// Higher-visual-fidelity sibling of MissionReplay.jsx. Same contract:
// renders an exported missionsim.exportFrameLog JSON, zero physics/
// detection/tracking computation of its own (verify-no-physics.mjs covers
// this file too). The only difference from the standard client is visual
// polish -- richer 3D models, ambient camera/light motion, screen-space
// labels -- not a different data source or a looser honesty bar.

const TRACK_SERIES_COLORS = [C.green, C.cyan, C.violet, C.amber, C.silver, C.red];

function CompassHUD() {
  return (
    <div style={{
      position: 'absolute', right: 12, bottom: 12, width: 60, height: 60,
      border: `1px solid ${C.lineSoft}`, borderRadius: '50%',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: 'rgba(7,11,16,0.6)', fontSize: 8, color: C.dim,
    }}>
      <span style={{ position: 'absolute', top: 3 }}>N</span>
      <span style={{ position: 'absolute', right: 5, color: C.green }}>E</span>
      <span style={{ position: 'absolute', bottom: 3 }}>S</span>
      <span style={{ position: 'absolute', left: 5 }}>W</span>
      <div style={{ width: 1, height: 24, background: C.green, opacity: 0.6 }} />
    </div>
  );
}

export default function MissionSimulatorHiFi() {
  const [frames, setFrames] = useState([]);
  const [idx, setIdx] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [source, setSource] = useState('');
  const [loadError, setLoadError] = useState('');
  const fileInputRef = useRef(null);

  useEffect(() => {
    fetch('/sample_run.json')
      .then((r) => r.json())
      .then((raw) => loadFrames(raw, 'sample_run.json (bundled, from a real missionsim.runManualScene run)'))
      .catch(() => setLoadError('No bundled sample log found. Use "Load Log" to open an exported frameLog JSON.'));
  }, []);

  function loadFrames(raw, label) {
    const norm = normalizeFrameLog(raw);
    const errors = validateShape(norm);
    if (errors.length) {
      setLoadError(`Rejected: ${errors[0]}`);
      return;
    }
    setFrames(norm);
    setIdx(0);
    setSource(label);
    setLoadError('');
  }

  function onFilePicked(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    file.text().then((text) => {
      try {
        loadFrames(JSON.parse(text), file.name);
      } catch (err) {
        setLoadError(`Could not parse "${file.name}": ${err.message}`);
      }
    });
    e.target.value = '';
  }

  useEffect(() => {
    if (!playing || frames.length === 0) return;
    const t = setInterval(() => {
      setIdx((i) => {
        if (i >= frames.length - 1) { setPlaying(false); return i; }
        return i + 1;
      });
    }, 450);
    return () => clearInterval(t);
  }, [playing, frames.length]);

  const frame = frames[idx];
  const identity = frame?.radar.identity;
  const framesSoFar = useMemo(() => frames.slice(0, idx + 1), [frames, idx]);
  const rangeSeries = useMemo(() => trackRangeSeries(framesSoFar), [framesSoFar]);
  const confirmedSeries = useMemo(() => confirmedCountSeries(framesSoFar), [framesSoFar]);

  const confirmedNow = frame ? frame.radar.tracks.filter((t) => t.state === 'CONFIRMED').length : 0;
  const phantomCount = frame ? frame.truth.phantoms.length : 0;

  return (
    <div style={{
      width: '100%', minHeight: '100vh', background: C.void, color: C.txt, fontFamily: MONO,
      display: 'flex', flexDirection: 'column',
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10, padding: '7px 12px',
        background: C.ribbon, borderBottom: `1px solid ${C.line}`,
      }}>
        <div style={{
          width: 20, height: 20, borderRadius: 4, background: 'linear-gradient(135deg,#2ee06a,#0f6b3a)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Move3d size={12} color="#05140b" strokeWidth={2.4} />
        </div>
        <div style={{ flex: 1, fontSize: 12.5, fontWeight: 700, letterSpacing: 0.3 }}>
          Mission Simulator -- HiFi Log Replay
        </div>
        <a href="/index.html" style={{ fontSize: 8.5, color: C.cyan, textDecoration: 'none', marginRight: 12 }}>
          &larr; Standard view
        </a>
        <div style={{ fontSize: 8.5, color: C.faint }}>{source}</div>
      </div>

      <div style={{
        display: 'flex', alignItems: 'center', gap: 2, padding: '6px 10px',
        background: C.app, borderBottom: `1px solid ${C.line}`, flexWrap: 'wrap',
      }}>
        <RibbonBtn icon={playing ? Pause : Play} label={playing ? 'Pause' : 'Play'}
          accent={playing ? C.amber : C.green} disabled={!frames.length}
          onClick={() => setPlaying((p) => !p)} />
        <RibbonBtn icon={SkipForward} label="Step" disabled={!frames.length}
          onClick={() => setIdx((i) => Math.min(i + 1, frames.length - 1))} />
        <RibbonBtn icon={RotateCcw} label="Restart" wide disabled={!frames.length}
          onClick={() => { setPlaying(false); setIdx(0); }} />
        <Sep />
        <RibbonBtn icon={FolderOpen} label="Load Log" wide onClick={() => fileInputRef.current?.click()} />
        <input ref={fileInputRef} type="file" accept="application/json" style={{ display: 'none' }} onChange={onFilePicked} />
        <Sep />
        <input type="range" min={0} max={Math.max(0, frames.length - 1)} value={idx}
          disabled={!frames.length}
          onChange={(e) => { setPlaying(false); setIdx(Number(e.target.value)); }}
          style={{ flex: 1, maxWidth: 380 }} />
        <div style={{
          border: `1px solid ${C.line}`, borderRadius: 4, padding: '5px 12px',
          background: C.panel, fontSize: 9.5, lineHeight: 1.65, minWidth: 210, marginLeft: 8,
        }}>
          <Row k="Frame" v={frame ? `${idx + 1} / ${frames.length}` : '--'} vc={C.green} />
          <Row k="t" v={frame ? `${frame.t.toFixed(2)} s` : '--'} />
          <Row k="Phase" v={frame?.phase ?? '--'} vc={C.amber} />
        </div>
      </div>

      {loadError && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 6, padding: '5px 12px',
          background: '#2a1414', color: '#ff9a9a', fontSize: 9.5, borderBottom: `1px solid ${C.line}`,
        }}>
          <AlertTriangle size={12} /> {loadError}
        </div>
      )}

      {!frame ? (
        <div style={{ padding: 40, color: C.dim, fontSize: 11 }}>Loading frame log...</div>
      ) : (
        <>
          <div style={{ display: 'flex', gap: 6, padding: 6, background: C.void }}>
            <div style={{ width: 232, flexShrink: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
              <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4 }}>
                <PanelHead>SYNTH -- PHANTOM KINEMATICS</PanelHead>
                <div style={{ padding: 8 }}>
                  <div style={{ display: 'flex', fontSize: 8.5, color: C.faint, letterSpacing: 0.5, paddingBottom: 3, borderBottom: `1px solid ${C.line}` }}>
                    <span style={{ flex: 1 }}>ID</span><span style={{ width: 70, textAlign: 'right' }}>RANGE</span><span style={{ width: 60, textAlign: 'right' }}>RAD.VEL</span>
                  </div>
                  {frame.synth.phantoms.map((p) => (
                    <TRow key={p.id} k={p.id} v={p.range?.value?.toFixed(0) ?? '--'} u="m" p={p.range?.provenance} />
                  ))}
                  {frame.synth.phantoms.length === 0 && (
                    <div style={{ color: C.faint, fontSize: 9, padding: '6px 0' }}>no phantoms this frame</div>
                  )}
                </div>
              </div>

              <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4 }}>
                <PanelHead>SWARM SUMMARY</PanelHead>
                <div style={{ display: 'flex', padding: '10px 4px' }}>
                  <Big n={phantomCount} l={['Phantoms', '(truth)']} c={C.silver} />
                  <Big n={confirmedNow} l={['Confirmed', '(radar)']} c={C.green} />
                  <Big n={frame.radar.tracks.length} l={['Total', 'tracks']} c={C.txt} />
                </div>
              </div>

              <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4, flex: 1 }}>
                <PanelHead>KNOWN LIMITS (guardrail #7)</PanelHead>
                <div style={{ padding: '7px 10px', fontSize: 8.5, color: C.faint, lineHeight: 1.7 }}>
                  <div>-- Single ASSUMED shared bearing: no azimuth field exists in this schema.</div>
                  <div>-- No mother-drone own-ship position in this export; not rendered.</div>
                  <div>-- Camera drift, radar rotation, and pulse rings below are AMBIENT/decorative -- not derived from PRI/PRF timing.</div>
                  <div>-- 35 dB SIC assumption, RadChar baseband carrier assumption, IMM projected not measured -- see CLAUDE.md.</div>
                </div>
              </div>
            </div>

            <div style={{ flex: 1, minWidth: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
              <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4, overflow: 'hidden' }}>
                <PanelHead right={<span style={{ color: C.faint }}>drag to orbit / scroll to zoom</span>}>
                  3D SCENARIO -- HIFI REPLAY (assumed single bearing)
                </PanelHead>
                <div style={{ position: 'relative', height: 470, background: '#05080d' }}>
                  <Scene3DHiFi frame={frame} identity={identity} />
                  <div style={{
                    position: 'absolute', left: 10, bottom: 10, background: 'rgba(7,11,16,0.82)',
                    border: `1px solid ${C.line}`, borderRadius: 3, padding: '6px 9px',
                    fontSize: 8.5, color: C.dim, lineHeight: 1.65,
                  }}>
                    <div>Range cell: <span style={{ color: C.txt }}>{identity.rangeCellM?.value.toFixed(1)} m</span> <Dot p={identity.rangeCellM?.provenance} /></div>
                    <div>Unambig: <span style={{ color: C.txt }}>{(identity.unambigRangeM?.value / 1000).toFixed(2)} km</span> <Dot p={identity.unambigRangeM?.provenance} /></div>
                    <div>Silver drone = phantom truth &nbsp; Diamond = radar track belief</div>
                  </div>
                  <CompassHUD />
                </div>
              </div>

              <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4 }}>
                <PanelHead>SIGNAL CHAIN (phase-driven, decorative)</PanelHead>
                <div style={{ padding: '2px 8px' }}><BlockChain phase={frame.phase} /></div>
              </div>
            </div>

            <div style={{ width: 300, flexShrink: 0, display: 'flex', flexDirection: 'column', gap: 6 }}>
              <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4 }}>
                <PanelHead>RADAR IDENTITY</PanelHead>
                <div style={{ padding: 8 }}>
                  <TRow k="fs" v={(identity.fs?.value / 1e6).toFixed(2)} u="MHz" p={identity.fs?.provenance} />
                  <TRow k="PRI" v={identity.priUs?.value.toFixed(1)} u="us" p={identity.priUs?.provenance} />
                  <TRow k="Range cell" v={identity.rangeCellM?.value.toFixed(2)} u="m" p={identity.rangeCellM?.provenance} />
                  <TRow k="Unambig range" v={identity.unambigRangeM?.value.toFixed(0)} u="m" p={identity.unambigRangeM?.provenance} />
                  <TRow k="CFAR type" v={frame.radar.detection.cfarType} u="" p={undefined} />
                  <TRow k="Design Pfa" v={frame.radar.detection.designPfa?.value.toExponential(1)} u="" p={frame.radar.detection.designPfa?.provenance} />
                  <TRow k="Detections" v={frame.radar.detection.detectionsThisFrame} u="" p={undefined} />
                  <TRow k="Tracker" v={frame.radar.tracker.filter} u="" p={undefined} />
                  <TRow k="Confirm M/N" v={`${frame.radar.tracker.confirmMofN?.[0]}/${frame.radar.tracker.confirmMofN?.[1]}`} u="" p={undefined} />
                  <TRow k="Delete M/N" v={`${frame.radar.tracker.deleteMofN?.[0]}/${frame.radar.tracker.deleteMofN?.[1]}`} u="" p={undefined} />
                </div>
              </div>

              <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4 }}>
                <PanelHead right={<Dot p="ASSUMED" />}>RANGE PROFILE</PanelHead>
                <div style={{ display: 'flex', gap: 12, padding: '6px 10px 0', fontSize: 8.5 }}>
                  <Lg c={C.silver} t="Phantom" hollow /><Lg c={C.green} t="Confirmed" /><Lg c={C.amber} t="Coasting" />
                </div>
                <RangeProfile frame={frame} identity={identity} />
              </div>

              <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4, flex: 1, overflow: 'auto' }}>
                <PanelHead>TRACK TABLE</PanelHead>
                <div style={{ padding: '4px 8px' }}>
                  <div style={{ display: 'flex', fontSize: 8, color: C.faint, letterSpacing: 0.4, padding: '3px 0', borderBottom: `1px solid ${C.line}` }}>
                    <span style={{ width: 34 }}>ID</span><span style={{ flex: 1 }}>STATE</span>
                    <span style={{ width: 50, textAlign: 'right' }}>RANGE</span><span style={{ width: 60, textAlign: 'right' }}>ECCM</span>
                  </div>
                  {frame.radar.tracks.map((t) => (
                    <div key={t.id} style={{
                      display: 'flex', alignItems: 'center', fontSize: 9, padding: '3px 0',
                      borderBottom: `1px solid ${C.lineSoft}`,
                      textDecoration: t.state === 'DELETED' ? 'line-through' : 'none',
                      color: STATE_COLOR[t.state] || C.txt,
                      opacity: t.state === 'DELETED' ? 0.5 : 1,
                    }}>
                      <span style={{ width: 34 }}>{t.id}</span>
                      <span style={{ flex: 1 }}>
                        {t.state}{t.state === 'COASTING' && Number.isFinite(t.misses) &&
                          ` ${t.misses}/${frame.radar.tracker.deleteMofN?.[0]}`}
                      </span>
                      <span style={{ width: 50, textAlign: 'right' }}>{Number.isFinite(t.rangeEst) ? t.rangeEst.toFixed(0) : '--'}</span>
                      <span style={{ width: 60, textAlign: 'right', fontSize: 8 }}>{t.eccmVerdict}</span>
                    </div>
                  ))}
                  {frame.radar.tracks.length === 0 && (
                    <div style={{ color: C.faint, fontSize: 9, padding: '6px 0' }}>no tracks this frame</div>
                  )}
                </div>
              </div>

              <div style={{ background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4 }}>
                <PanelHead>SCOREBOARD</PanelHead>
                <div style={{ padding: 8 }}>
                  <TRow k="Confirmed false tracks" v={frame.radar.scoreboard.confirmedFalseTracks?.value}
                    u="" p={frame.radar.scoreboard.confirmedFalseTracks?.provenance} />
                  <TRow k="Deception rate" v={frame.radar.scoreboard.deceptionRate?.value?.toFixed(2)}
                    u="" p={frame.radar.scoreboard.deceptionRate?.provenance} />
                </div>
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', gap: 6, padding: '0 6px 6px', background: C.void }}>
            <div style={{ flex: 1, background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4 }}>
              <PanelHead right={<Dot p="MEASURED" />}>CONFIRMED TRACK COUNT vs. TIME</PanelHead>
              <div style={{ padding: '6px 8px 2px' }}>
                <LineChart yMin={0} yMax={Math.max(1, ...confirmedSeries.map((p) => p.v))} height={92}
                  series={[{ data: confirmedSeries, color: C.green, w: 1.5 }]} />
              </div>
            </div>
            <div style={{ flex: 1, background: C.panel, border: `1px solid ${C.line}`, borderRadius: 4 }}>
              <PanelHead right={<Dot p="MEASURED" />}>TRACK RANGE ESTIMATE vs. TIME</PanelHead>
              <div style={{ padding: '6px 8px 2px' }}>
                <LineChart yMin={0} yMax={Math.max(1, identity.rangeCellM?.value * 512 || 1)} height={92}
                  series={[...rangeSeries.entries()].map(([id, data], i) => ({
                    data, color: TRACK_SERIES_COLORS[i % TRACK_SERIES_COLORS.length], w: 1.2,
                  }))} />
              </div>
            </div>
          </div>

          <div style={{
            display: 'flex', alignItems: 'center', gap: 22, padding: '5px 14px',
            background: C.ribbon, borderTop: `1px solid ${C.line}`, fontSize: 8.5, color: C.dim,
          }}>
            <span style={{ color: playing ? C.green : C.dim }}>{playing ? 'Playing' : 'Paused'}</span>
            <div style={{ flex: 1 }} />
            <span style={{ color: C.faint }}>Log replay only -- this client computes zero detections/tracks itself.</span>
          </div>
        </>
      )}
    </div>
  );
}
