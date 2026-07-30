# Live Mission Console — bridge

Turns a browser control into real execution: Python cognitive engine plans,
MATLAB judge scores, UI renders. Nothing on screen is animated independently of
a real plan+score cycle.

## Run

```bash
python -m pip install "E:/MATLAB/extern/engines/python"   # once, matlab.engine 26.1
python -m uvicorn server.app:app --reload --port 8000     # from E:\Radar
cd web && npm run dev                                      # separate shell
```

`GET /health` → `{judge_online, judge_error}`. If `judge_online` is false the
UI must show **JUDGE OFFLINE**; `/score` and `/run` return 503 and never
fabricate a verdict (CLAUDE.md guardrail 4, AC-6).

## Endpoints

| | body | runs | returns |
|---|---|---|---|
| `POST /plan` | `{radarState, opts}` | `cogengine.planner_cem` (Python) | `{scene}` — **never `bestScore`** |
| `POST /score` | `{scene, radarState, opts}` | `engine.runJudge` (MATLAB) | `{feedback}` |
| `POST /run` | `{radarState, opts}` | plan → score | `{scene, feedback, attribution, truth_track}` |

`/run` alone carries `truth_track`: every phantom's range at every frame the
judge scored, replayed through `cogengine.radar_twin.advance_phantom` — the
same propagation `render_scene_to_mat` used to build the cube. It is DERIVED,
not measured, and it exists so the console has a time axis. Without it the 3D
view drew each phantom at its t=0 range and parked it there for the whole
engagement. `/run` also forwards `track_time_s`, which is what the MEASURED
side is sampled against: a track has one hit per *detected* frame, so a coast
is a real gap and must not be closed by assuming a uniform grid.

## MEASURED latency — the planner is the bottleneck, not the judge

The build spec anticipated the MATLAB judge being hammered by slider drags and
prescribed a 200–400 ms debounce. Measured on this machine, that is the wrong
worry:

| stage | time |
|---|---|
| MATLAB engine cold start | 12–68 s (once, at boot) |
| `engine.runJudge` per call | **~0.75 s** warm |
| `/score` end-to-end (export + judge) | ~10 s |
| **`/plan` (CEM, N=2, pop 72 × 8 iters)** | **~66 s** |
| `/run` total | ~76 s |

**A 400 ms debounce cannot rescue a 66 s planner.** The judge is cheap; the CEM
search over the twin is what costs. Consequences for the UI:

* Slider drags must NOT trigger `/run`. Use an explicit **RUN** button, with the
  controls staying live and a visible "planning…" state.
* `/plan` and `/score` are usefully separate: re-scoring an existing scene at a
  new seed or new gate costs ~10 s, not ~76 s. The console should call `/score`
  alone whenever only `radarState` changed.
* An interactive CEM budget (`population_size`, `iterations`) is a real
  quality/latency trade. `plan_multi`'s own sizing guidance (36·N population,
  8 iterations) exists because under-resourcing it produced a *wrong published
  result* once already — see CLAUDE.md Task 1's follow-up. **Do not quietly
  shrink it to make the UI feel fast**; if an interactive preset is added it
  must be labelled as such on screen.

## Known gap: `angle_source` is `none` on this path

`/run` currently reports `angle_source: 'none'` because
`cogengine.matlab_judge.export_scene_for_judge` emits only the SUM channel.
The monopulse difference channel exists (`engine.entity.render`, third output)
and the judge consumes it (`rx_frames_delta`), but the Python export path has
not been extended yet.

**Until it is, the PPI cannot draw real azimuth** — and drawing a fake one is
exactly what this project refused to do before the angle channel existed
(`MISSION_SIMULATOR_UI_SPEC.md` §11: a polar scope "would imply azimuth data
this project has never had"). The PPI is therefore blocked on that export
change, not on UI work.
