# Retired web clients — 15 August 2026

**Status:** RETIRED — not built, not served, do not import.

`web/` now has ONE page: `console.html` → `src/main-console.jsx` →
`src/Console.jsx` (the Live Mission Console, which drives real plan+score
cycles over the FastAPI bridge). The two log-replay pages were removed
because they replay a bundled fixture rather than run anything.

Moved with `git mv`, so `git log --follow` still finds the history.

## What's here
- `index.html`, `src/main.jsx`, `src/MissionReplay.jsx` — the log-replay
  client (MISSION_SIMULATOR_UI_SPEC.md step 11) plus its "Watch Live"
  NDJSON tail mode
- `hifi.html`, `src/main-hifi.jsx`, `src/MissionSimulatorHiFi.jsx` — the
  visually richer sibling of the same replay client
- `src/components/{LineChart,RangeProfile,Scene3D}.jsx`,
  `src/lib/{frameLog,liveFrameLog}.js` — orphaned once the two pages went;
  nothing under `web/src/` imports them any more
- `public/{sample_run,sample_lifecycle_run}.json` — fixtures only those two
  pages ever fetched (real `missionsim.exportFrameLog` output; the
  lifecycle one is a hand-built CONFIRMED→COASTING→DELETED sequence)

## Still live and untouched
`web/src/Console.jsx`, `theme.js`, `components/{Chrome,BlockChain,PPIScope,
Scene3DHiFi}.jsx`, `lib/{bridge,consoleFrame}.js`, all three
`web/scripts/*.mjs`, and the MATLAB side (`+missionsim/`, including
`exportFrameLog`/`streamManualSceneToFile`, which write NDJSON to a
caller-supplied path and never referenced `web/public/`).

Sections of `CLAUDE.md`, `PROJECT_INVENTORY.md` and
`ANNEXURE_TECHNICAL_INVENTORY.md` describing three entry points are history
now, not a description of the tree (Rule 5 — superseded text stays visible).
