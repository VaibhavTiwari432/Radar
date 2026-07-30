import React from 'react';
import { C, MONO } from '../theme.js';

// Decorative architecture diagram (mirrors AI_Cognitive_Engine_Detailed_
// Design.md's own signal-chain description). "active" is driven by the
// current frame's phase string, already computed by buildFrameLog.m --
// this component performs no phase derivation itself.
const BLOCKS = [
  { t: ['Mother Drone', 'Input'], f: '#1d3b16', s: '#4a8c2a' },
  { t: ['Hallucination', 'Engine'], f: '#3f3510', s: '#b08a1e' },
  { t: ['Swarm Decoy', 'Generator'], f: '#132c46', s: '#2f6fa8' },
  { t: ['Radar Signature', 'Model'], f: '#2b1f42', s: '#7a5fbd' },
  { t: ['Radar Response', '(judge)'], f: '#0f3535', s: '#2f9a9a' },
];

const ACTIVE_BY_PHASE = {
  ACQUISITION: [0],
  ENGINE_ACTIVE: [0, 1, 2, 3],
  DECEPTION_HOLDING: [0, 1, 2, 3, 4],
  INGRESS: [0],
  EGRESS: [0],
};

export default function BlockChain({ phase }) {
  const active = ACTIVE_BY_PHASE[phase] || [0];
  const W = 700, BW = 108, BH = 46, GAP = 32, y = 20;
  return (
    <svg viewBox={`0 0 ${W} 78`} style={{ width: '100%', height: 78 }}>
      {BLOCKS.map((b, i) => {
        const x = 26 + i * (BW + GAP);
        const on = active.includes(i);
        return (
          <g key={i}>
            <rect x={x} y={y} width={BW} height={BH} rx={5} fill={b.f}
              stroke={on ? b.s : C.line} strokeWidth={on ? 1.4 : 1} opacity={on ? 1 : 0.5} />
            {b.t.map((line, li) => (
              <text key={li} x={x + BW / 2} y={y + 20 + li * 12} fontSize={9.5} fill={on ? C.txt : C.dim}
                textAnchor="middle" fontFamily={MONO}>{line}</text>
            ))}
            {i < BLOCKS.length - 1 && (
              <g stroke={active.includes(i + 1) ? b.s : C.faint} strokeWidth={1.2} fill="none">
                <line x1={x + BW} y1={y + BH / 2} x2={x + BW + GAP - 7} y2={y + BH / 2} />
                <path d={`M${x + BW + GAP - 7} ${y + BH / 2 - 3.4}L${x + BW + GAP} ${y + BH / 2}L${x + BW + GAP - 7} ${y + BH / 2 + 3.4}Z`}
                  fill={active.includes(i + 1) ? b.s : C.faint} stroke="none" />
              </g>
            )}
          </g>
        );
      })}
    </svg>
  );
}
