import React, { useState } from 'react';
import { C, MONO, PV } from '../theme.js';

// Small presentational primitives, adapted from the reference instrument-
// panel UI. Purely visual -- no scenario logic lives here.

export function Dot({ p }) {
  const pv = PV[p] || PV.ASSUMED;
  return (
    <span title={pv.t} style={{
      display: 'inline-block', width: 5, height: 5, borderRadius: '50%',
      background: pv.c, marginLeft: 5, verticalAlign: 'middle', opacity: 0.85,
    }} />
  );
}

export function PanelHead({ children, right }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '5px 9px', background: C.panelHead, borderBottom: `1px solid ${C.line}`,
      fontSize: 9.5, letterSpacing: 1.1, color: C.dim, fontWeight: 600,
    }}>
      <span>{children}</span>{right}
    </div>
  );
}

export function RibbonBtn({ icon: Icon, label, onClick, active, accent, wide, disabled }) {
  const [h, setH] = useState(false);
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      onMouseEnter={() => setH(true)} onMouseLeave={() => setH(false)}
      style={{
        display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
        minWidth: wide ? 54 : 42, padding: '5px 6px', border: 'none', borderRadius: 3,
        background: active || h ? C.ribbonHi : 'transparent', cursor: disabled ? 'default' : 'pointer',
        opacity: disabled ? 0.4 : 1,
        color: accent || (active ? C.green : C.txt), fontFamily: MONO, fontSize: 8.5,
        letterSpacing: 0.2, transition: 'background 120ms',
      }}>
      <Icon size={17} strokeWidth={1.6} />
      <span style={{ color: C.dim, whiteSpace: 'nowrap' }}>{label}</span>
    </button>
  );
}

export const Sep = () => <div style={{ width: 1, alignSelf: 'stretch', background: C.line, margin: '4px 6px' }} />;

// Two call styles on purpose: k/v for plain label-value pairs (MissionReplay,
// MissionSimulatorHiFi), children when the row needs its own markup -- Console
// puts a <Prov> tag inside the value. Console was written against the children
// form while this only read props, so its rows rendered as two empty spans:
// the JUDGE VERDICT panel was present in the DOM and blank on screen.
export function Row({ k, v, vc, children }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 14 }}>
      {children ?? (
        <>
          <span style={{ color: C.dim }}>{k}</span>
          <span style={{ color: vc || C.txt }}>{v}</span>
        </>
      )}
    </div>
  );
}

export function TRow({ k, v, u, p, c }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', padding: '3.5px 0', fontSize: 9.5, borderBottom: `1px solid ${C.lineSoft}` }}>
      <span style={{ flex: 1, color: C.dim }}>{k}</span>
      <span style={{ width: 64, textAlign: 'right', color: c || C.txt, fontWeight: 600 }}>{v}</span>
      <span style={{ width: 28, textAlign: 'right', color: C.faint, fontSize: 8.5 }}>{u}</span>
      {p && <Dot p={p} />}
    </div>
  );
}

export function Big({ n, l, c }) {
  return (
    <div style={{ flex: 1, textAlign: 'center' }}>
      <div style={{ fontSize: 21, fontWeight: 700, color: c, lineHeight: 1 }}>{n}</div>
      <div style={{ fontSize: 8, color: C.dim, marginTop: 4, lineHeight: 1.35 }}>
        {l.map((x) => <div key={x}>{x}</div>)}
      </div>
    </div>
  );
}

// ---- control widgets ----------------------------------------------------
// `disabled` is used for controls the ENGINE owns (D3QN mode) or that the
// planner decides for itself. A greyed control that still reaches the backend
// would be a lie about who is driving.

export function Slider({ label, value, min, max, step, onChange, unit, disabled, note }) {
  return (
    <div style={{ marginBottom: 9, opacity: disabled ? 0.5 : 1 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 9, color: C.dim, marginBottom: 3 }}>
        <span>{label}</span>
        <span style={{ color: disabled ? C.faint : C.green, fontWeight: 600 }}>{value}{unit}</span>
      </div>
      <input type="range" min={min} max={max} step={step} value={value} disabled={disabled}
        onChange={(e) => onChange(+e.target.value)}
        style={{ width: '100%', accentColor: C.green, height: 3, cursor: disabled ? 'not-allowed' : 'pointer' }} />
      {note && <div style={{ fontSize: 7.5, color: C.faint, marginTop: 2 }}>{note}</div>}
    </div>
  );
}

export function Segmented({ label, value, options, onChange, disabled }) {
  return (
    <div style={{ marginBottom: 9, opacity: disabled ? 0.5 : 1 }}>
      <div style={{ fontSize: 9, color: C.dim, marginBottom: 3 }}>{label}</div>
      <div style={{ display: 'flex', gap: 3 }}>
        {options.map((o) => (
          <button key={o} onClick={() => !disabled && onChange(o)} disabled={disabled}
            style={{ flex: 1, padding: '3px 2px', fontSize: 8, fontFamily: MONO, borderRadius: 2,
              cursor: disabled ? 'not-allowed' : 'pointer', textTransform: 'capitalize',
              background: value === o ? 'rgba(46,224,106,0.16)' : C.app,
              border: `1px solid ${value === o ? C.green : C.line}`,
              color: value === o ? C.green : C.dim }}>
            {o}
          </button>
        ))}
      </div>
    </div>
  );
}

export function Toggle({ label, value, onChange, note, disabled }) {
  return (
    <div style={{ marginBottom: 9, opacity: disabled ? 0.5 : 1 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span style={{ fontSize: 9, color: C.dim }}>{label}</span>
        <button onClick={() => !disabled && onChange(!value)} disabled={disabled}
          style={{ width: 30, height: 16, borderRadius: 8, border: `1px solid ${value ? C.green : C.line}`,
            background: value ? 'rgba(46,224,106,0.2)' : C.app, position: 'relative',
            cursor: disabled ? 'not-allowed' : 'pointer', padding: 0 }}>
          <span style={{ position: 'absolute', top: 1, left: value ? 15 : 1, width: 12, height: 12,
            borderRadius: '50%', background: value ? C.green : C.dim, transition: 'left 140ms' }} />
        </button>
      </div>
      {note && <div style={{ fontSize: 7.5, color: C.faint, marginTop: 2 }}>{note}</div>}
    </div>
  );
}

export function Lg({ c, t, hollow }) {
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, color: C.dim }}>
      <span style={{
        width: 7, height: 7, borderRadius: '50%',
        background: hollow ? 'transparent' : c, border: `1.3px solid ${c}`,
      }} />{t}
    </span>
  );
}
