// Instrument-panel chrome shared by every component. Colours are purely
// presentational -- none of this file computes anything about the scenario.
export const C = {
  void: '#05080b',
  app: '#0a0f15',
  ribbon: '#141b24',
  ribbonHi: '#1a2029',
  panel: '#0d131a',
  panelHead: '#111820',
  line: '#1e2933',
  lineSoft: '#161f27',
  txt: '#c6d5e0',
  dim: '#63798a',
  faint: '#3d4d5b',
  green: '#2ee06a',
  greenDim: '#187a3c',
  red: '#ff4a4a',
  redDim: '#7d1f1f',
  amber: '#ffab2e',
  silver: '#b8c2cc',
  cyan: '#49c8e0',
  violet: '#9a7ad1',
};

export const MONO = "'IBM Plex Mono','JetBrains Mono','SF Mono',ui-monospace,Menlo,monospace";

// MISSION_SIMULATOR_UI_SPEC.md Section 8: any {value, ...} object must carry
// a provenance tag. This is the same four-way vocabulary the MATLAB side
// (missionsim.validateFrame) enforces -- the web client only ever displays
// values the log already tagged, it never assigns provenance itself.
export const PV = {
  MEASURED: { c: C.green, t: 'MEASURED' },
  DERIVED: { c: C.cyan, t: 'DERIVED' },
  ASSUMED: { c: C.amber, t: 'ASSUMED' },
  UNVALIDATED: { c: C.red, t: 'UNVALIDATED' },
};

// Track lifecycle colours, matching MISSION_SIMULATOR_UI_SPEC.md Section 7
// and +missionsim/MissionSimulatorApp.m's TrackMarkerOpacities convention.
export const STATE_COLOR = {
  TENTATIVE: C.faint,
  CONFIRMED: C.txt,
  COASTING: C.amber,
  DELETED: C.red,
};
