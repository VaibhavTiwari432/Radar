import React from 'react';
import { C, MONO, STATE_COLOR } from '../theme.js';

// A full PPI polar scope would imply bearing/angle data this project's
// schema does not have (see Scene3D.jsx's header). Rather than fabricate
// angles, this renders the same information a real single-bearing range
// profile shows: everything at its measured range along the one ASSUMED
// shared bearing this project's phantoms are placed on.
export default function RangeProfile({ frame, identity }) {
  const rangeCellM = identity?.rangeCellM?.value ?? 0;
  const unambigM = identity?.unambigRangeM?.value ?? 0;
  const ceilM = rangeCellM * 512;
  const W = 268, H = 78, PL = 10, PR = 10, y0 = 40;
  const px = (r) => PL + (ceilM > 0 ? (r / ceilM) : 0) * (W - PL - PR);

  return (
    <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: H, display: 'block' }}>
      <line x1={PL} y1={y0} x2={W - PR} y2={y0} stroke={C.line} strokeWidth={1} />
      {unambigM > 0 && (
        <line x1={px(unambigM)} y1={y0 - 18} x2={px(unambigM)} y2={y0 + 18}
          stroke={C.amber} strokeWidth={1} strokeDasharray="3 2" opacity={0.8} />
      )}
      <line x1={px(ceilM)} y1={y0 - 10} x2={px(ceilM)} y2={y0 + 10} stroke={C.red} strokeWidth={1} opacity={0.5} />
      <circle cx={PL} cy={y0} r={4} fill={C.green} />
      {frame?.truth.phantoms.map((p) => {
        const r = Array.isArray(p.pos) ? p.pos[0] : 0;
        return (
          <circle key={p.id} cx={px(r)} cy={y0} r={4} fill="none" stroke={C.silver} strokeWidth={1.3} />
        );
      })}
      {frame?.radar.tracks.filter((t) => t.state !== 'DELETED').map((t) => (
        Number.isFinite(t.rangeEst) && (
          <path key={t.id}
            d={`M${px(t.rangeEst)} ${y0 - 22} l3 5 l-6 0 z`}
            fill={STATE_COLOR[t.state] || C.txt} opacity={0.9} />
        )
      ))}
      <text x={PL} y={H - 4} fontSize={7} fill={C.faint} fontFamily={MONO}>0 m</text>
      <text x={W - PR} y={H - 4} fontSize={7} fill={C.faint} fontFamily={MONO} textAnchor="end">
        {ceilM ? `${(ceilM / 1000).toFixed(1)} km` : '--'}
      </text>
    </svg>
  );
}
