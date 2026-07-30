import React from 'react';
import { C, MONO } from '../theme.js';

// Hand-built SVG line chart -- renders {t, v} series handed to it. Does not
// compute any of the values it plots.
export default function LineChart({ series, yMin, yMax, height = 92, threshold, xMax }) {
  const W = 300, H = height, PL = 34, PB = 15, PT = 6, PR = 6;
  const iw = W - PL - PR, ih = H - PT - PB;
  const tMax = xMax ?? Math.max(1, ...series.flatMap((s) => s.data.map((p) => p.t)));
  const px = (t) => PL + (t / tMax) * iw;
  const py = (v) => PT + ih - ((v - yMin) / (yMax - yMin || 1)) * ih;
  const ticks = 4;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height, display: 'block' }} preserveAspectRatio="none">
      {Array.from({ length: ticks + 1 }).map((_, i) => {
        const v = yMin + ((yMax - yMin) * i) / ticks;
        return (
          <g key={i}>
            <line x1={PL} y1={py(v)} x2={W - PR} y2={py(v)} stroke={C.lineSoft} strokeWidth={0.6} />
            <text x={PL - 4} y={py(v) + 3} fontSize={7} fill={C.faint} textAnchor="end" fontFamily={MONO}>
              {Math.abs(yMax) < 2 ? v.toFixed(1) : Math.round(v)}
            </text>
          </g>
        );
      })}
      {threshold !== undefined && (
        <>
          <line x1={PL} y1={py(threshold)} x2={W - PR} y2={py(threshold)}
            stroke={C.amber} strokeWidth={0.9} strokeDasharray="4 3" />
        </>
      )}
      {series.map((s, si) => {
        if (!s.data.length) return null;
        const d = s.data.map((p, i) => `${i ? 'L' : 'M'}${px(p.t).toFixed(1)} ${py(p.v).toFixed(1)}`).join(' ');
        return <path key={si} d={d} fill="none" stroke={s.color} strokeWidth={s.w || 1.3}
          strokeDasharray={s.dash || 'none'} opacity={s.op ?? 1} />;
      })}
      <line x1={PL} y1={PT + ih} x2={W - PR} y2={PT + ih} stroke={C.line} strokeWidth={0.8} />
      <line x1={PL} y1={PT} x2={PL} y2={PT + ih} stroke={C.line} strokeWidth={0.8} />
    </svg>
  );
}
