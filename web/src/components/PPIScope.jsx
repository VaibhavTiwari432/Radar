import React, { useEffect, useState } from 'react';
import { C, MONO } from '../theme.js';

// PPI scope for the LIVE console.
//
// THIS COMPONENT COMPUTES NO GEOMETRY. It plots the positions the 3D scene
// reports, converted to (range, bearing) there and handed over every ~90 ms.
// An earlier version derived its own layout, which meant the scope and the
// 3D view could disagree about where the same object was mid-spawn. The 3D
// scene is authoritative; this is a projection of it, so the two cannot drift.
//
// WHAT EACH AXIS IS WORTH, because they are not worth the same:
//
//   RANGE is real. Every phantom radius is the planner's own range_m, and
//   every track caret is the mean of that track's MEASURED range series.
//
//   BEARING IS NOT A RADAR MEASUREMENT. This export path reports
//   `angle_source: 'none'` -- the monopulse difference channel exists in
//   +engine/+entity/render.m and runJudge consumes it, but
//   cogengine.matlab_judge.export_scene_for_judge still emits the sum channel
//   only, so no azimuth reaches this client. The bearings drawn here are the
//   SCENE's layout: the mother drone's illustrative transit, and the single
//   shared axis this project places phantoms on. That axis is not arbitrary --
//   one jammer makes every phantom, so they genuinely do share its instantaneous
//   bearing (CLAUDE.md Honest Limits), which is exactly the property an angle
//   channel exploits to flag the whole group in one look. It is still a scene
//   convention rather than a reading, and the footer says so on every frame.
//
// When the delta-channel export lands, `measuredAz` goes true and the footer
// flips to MEASURED. Nothing else about this component needs to change.

const STATUS_COL = { confirmed: C.green, flagged: C.amber, undetected: C.faint };

export default function PPIScope({
  targets = [], tracks = [], mother = null, scaleKm = 'auto',
  unambigKm = 0, ceilKm = 0, measuredAz = false,
}) {
  const S = 268, cx = S / 2, cy = S / 2, R = 108;
  const [t, setT] = useState(0);

  // Own rAF for the sweep, so the phosphor turns without the parent
  // re-rendering the whole console at frame rate.
  useEffect(() => {
    let raf; const t0 = performance.now();
    const tick = (now) => { raf = requestAnimationFrame(tick); setT((now - t0) / 1000); };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, []);

  const sweep = (t * 34) % 360;                       // ~10.6 s/rev
  const far = Math.max(
    0.6,
    ...targets.map((p) => p.rangeM / 1000),
    ...tracks.map((t) => t.rangeM / 1000),
    mother ? mother.rangeM / 1000 : 0,
  );
  // AUTO keeps every reported object on the scope. A fixed scale that dropped
  // the mother drone off the edge would break the "same positions" contract
  // this component exists to keep.
  const span = scaleKm === 'auto' ? far * 1.18 : scaleKm;

  const toXY = (km, azDeg) => {
    const r = Math.min(km / span, 1) * R;
    const a = ((azDeg - 90) * Math.PI) / 180;
    return [cx + r * Math.cos(a), cy + r * Math.sin(a)];
  };
  const persist = (az) => {
    const da = (((sweep - az) % 360) + 360) % 360;
    return Math.max(0.15, 1 - da / 150);
  };

  const ringKm = [0.25, 0.5, 0.75, 1].map((f) => span * f);

  return (
    <div>
      <svg width="100%" viewBox={`0 0 ${S} ${S}`} style={{ display: 'block' }}>
        <defs>
          <radialGradient id="ppiSweepGrad">
            <stop offset="0%" stopColor={C.green} stopOpacity="0.30" />
            <stop offset="100%" stopColor={C.green} stopOpacity="0" />
          </radialGradient>
        </defs>

        <circle cx={cx} cy={cy} r={R} fill="#03130a" stroke={C.line} strokeWidth={0.8} />

        {ringKm.map((km, i) => (
          <g key={i}>
            <circle cx={cx} cy={cy} r={(km / span) * R} fill="none" stroke={C.lineSoft} strokeWidth={0.7} />
            <text x={cx + 3} y={cy - (km / span) * R + 10} fontSize={7.5} fill={C.faint} fontFamily={MONO}>
              {km < 10 ? km.toFixed(1) : Math.round(km)} km
            </text>
          </g>
        ))}

        {unambigKm > 0 && unambigKm < span && (
          <circle cx={cx} cy={cy} r={(unambigKm / span) * R} fill="none"
            stroke={C.amber} strokeWidth={0.9} strokeDasharray="3 3" opacity={0.6} />
        )}
        {ceilKm > 0 && ceilKm < span && (
          <circle cx={cx} cy={cy} r={(ceilKm / span) * R} fill="none"
            stroke={C.red} strokeWidth={0.8} strokeDasharray="2 4" opacity={0.4} />
        )}

        {Array.from({ length: 12 }).map((_, i) => {
          const deg = i * 30, a = ((deg - 90) * Math.PI) / 180;
          const lx = cx + (R + 13) * Math.cos(a), ly = cy + (R + 13) * Math.sin(a);
          return (
            <g key={i}>
              <line x1={cx} y1={cy} x2={cx + R * Math.cos(a)} y2={cy + R * Math.sin(a)}
                stroke={C.lineSoft} strokeWidth={0.5} opacity={0.55} />
              <text x={lx} y={ly + 3} fontSize={7} fill={C.dim} textAnchor="middle" fontFamily={MONO}>{deg}°</text>
            </g>
          );
        })}

        <g transform={`rotate(${sweep} ${cx} ${cy})`}>
          <path d={`M ${cx} ${cy} L ${cx} ${cy - R} A ${R} ${R} 0 0 1 ${cx + R * Math.sin(0.85)} ${cy - R * Math.cos(0.85)} Z`}
            fill="url(#ppiSweepGrad)" />
          <line x1={cx} y1={cy} x2={cx} y2={cy - R} stroke={C.green} strokeWidth={1.1} opacity={0.85} />
        </g>

        {/* Emission leaders: mother -> each phantom, the repeater's own
            geometry. Drawn faintly so the co-bearing stack is readable. */}
        {mother && targets.map((p) => {
          const [mx, my] = toXY(mother.rangeM / 1000, mother.azDeg);
          const [px, py] = toXY(p.rangeM / 1000, p.azDeg);
          return <line key={`l${p.id}`} x1={mx} y1={my} x2={px} y2={py}
            stroke={C.green} strokeWidth={0.5} strokeDasharray="2 3" opacity={0.18} />;
        })}

        {/* Phantoms, at exactly the positions the 3D scene holds. */}
        {targets.map((p, i) => {
          const [x, y] = toXY(p.rangeM / 1000, p.azDeg);
          const col = STATUS_COL[p.status] ?? C.silver;
          const op = 0.32 + 0.68 * persist(p.azDeg);
          // Labels alternate side to side: on a shared bearing the blips stack
          // on one radial, so stacked labels would be unreadable.
          const side = i % 2 ? 1 : -1;
          return (
            <g key={p.id} opacity={op}>
              <circle cx={x} cy={y} r={3.6} fill="none" stroke={col} strokeWidth={1.5} />
              <circle cx={x} cy={y} r={1.3} fill={col} />
              <text x={x + side * 8} y={y + 3} fontSize={7.5} fill={col} fontFamily={MONO}
                textAnchor={side > 0 ? 'start' : 'end'}>{p.id}</text>
            </g>
          );
        })}

        {/* TRACKS -- what the tracker actually holds, at the range it
            MEASURED. Drawn as an open caret so it never reads as one of the
            truth blips above: those are where the jammer aimed a phantom,
            these are where the radar believes something is. The two sit apart
            by the range-cell quantisation, which is the point of showing both.
            A track only appears on the frames it was actually detected on --
            the 3D scene hides it otherwise and this plots what that reports. */}
        {tracks.map((t) => {
          const [x, y] = toXY(t.rangeM / 1000, t.azDeg);
          const op = 0.3 + 0.7 * persist(t.azDeg);
          return (
            <g key={`tk${t.id}`} opacity={op}>
              <path d={`M ${x - 4.5} ${y + 4.5} L ${x} ${y - 3} L ${x + 4.5} ${y + 4.5}`}
                fill="none" stroke={C.silver} strokeWidth={1.2} strokeLinejoin="round" />
              <text x={x} y={y + 12} fontSize={6.5} fill={C.silver} fontFamily={MONO}
                textAnchor="middle">{t.id}</text>
            </g>
          );
        })}

        {/* Mother drone. Hollow, never a solid contact: the jammer has no
            position in this project's model, so this is where the SCENE puts
            it, not where the radar found it. */}
        {mother && (() => {
          const [x, y] = toXY(mother.rangeM / 1000, mother.azDeg);
          const op = 0.35 + 0.65 * persist(mother.azDeg);
          return (
            <g opacity={op}>
              <circle cx={x} cy={y} r={8} fill="none" stroke={C.green} strokeWidth={0.7}
                strokeDasharray="2 2" opacity={0.6} />
              <circle cx={x} cy={y} r={4} fill="none" stroke={C.green} strokeWidth={1.7} />
              <text x={x} y={y - 11} fontSize={7.5} fill={C.green} fontFamily={MONO}
                textAnchor="middle" fontWeight={700}>MOTHER</text>
            </g>
          );
        })()}

        <circle cx={cx} cy={cy} r={2.5} fill="none" stroke={C.dim} strokeWidth={1} />
      </svg>

      <div style={{ fontSize: 7.5, color: C.dim, marginTop: 5, lineHeight: 1.45 }}>
        <span style={{ color: C.green }}>○</span> phantom (scene truth) ·{' '}
        <span style={{ color: C.silver }}>∧</span> track (radar’s own range) ·{' '}
        <span style={{ color: C.green }}>◎</span> mother, illustrative
      </div>
      <div style={{ fontSize: 7.5, color: measuredAz ? C.dim : C.amber, marginTop: 3, lineHeight: 1.45 }}>
        {measuredAz
          ? 'Range MEASURED · bearing MEASURED (monopulse azimuth per track).'
          : 'Range MEASURED · bearing is the SCENE’s layout, not a reading — this export path carries the sum channel only, so angle_source is none. Phantoms stack on one radial because one jammer made them all, which is the property an angle channel exploits.'}
      </div>
    </div>
  );
}
