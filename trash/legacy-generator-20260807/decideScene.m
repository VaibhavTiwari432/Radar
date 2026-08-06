function [scene, bestScore] = decideScene(radarState, opts)
%DECIDESCENE  The integration seam: MATLAB radarState -> live Python
%   cognitive engine (CEM planner) -> Scene. Build-order step 6 (design doc
%   Part 6 / CLAUDE.md Rule 4).
%
%   [scene, bestScore] = engine.decideScene(radarState)
%   [scene, bestScore] = engine.decideScene(radarState, opts)
%       radarState : struct shaped like engine.sceneContract().radarState
%                    (mode, prf_hz, pri_s, carrier_hz, range_gate_m,
%                    vel_gate_mps, scan_phase, doubt_cue).
%       opts.interceptNoiseAmplitude (default 2.0) : forwarded to
%                    cogengine.radar_twin.TwinConfig. 2.0 is not a fresh
%                    magic number -- it's the SAME level already validated
%                    (+features/synthesizeTxPulse.m, +agent/buildEnvWithFeatures.m)
%                    as where feature-matched synthesis actually changes the
%                    CFAR/tracker decision, not just the signal-level peak.
%       opts.seed    (default 1) : seeds numpy's default_rng for the CEM
%                    search and the twin's noise draws -- reproducible, not
%                    wall-clock random (this project never uses Date.now()-
%                    style nondeterminism for anything that gets reported).
%       scene      : struct shaped like engine.sceneContract().scene
%                    (phantoms, maneuver, eirp_budget_dbw, t0_s, duration_s).
%       bestScore  : the CEM search's own internal score for the returned
%                    scene (planner_cem.score_scene's units) -- NOT a
%                    judge-verified deception metric; see the Golden Rule
%                    note below.
%
%   ONLY Path B (live pyenv co-simulation, design doc Part 6) is implemented
%   here, not a 3-way ONNX/pyenv/pure-MATLAB switch like the
%   cognitive_engine/ reference stub. Reason: this project's planner
%   (cogengine.planner_cem.plan, Rung 0 of the algorithm ladder) is a live
%   CEM SEARCH over the twin, not a trained network -- there is no policy.onnx
%   to import (Path A only becomes applicable if build-order step 7's
%   OPTIONAL distillation, cogengine/policy.py, is ever built). Path B is
%   therefore not a stylistic choice, it's the only path that matches what
%   this project actually built.
%
%   Marshaling uses jsonencode/jsondecode against schema.py's OWN
%   to_json/from_json methods (verified interactively: a MATLAB radarState
%   struct round-trips through py.cogengine.schema.RadarState.from_json and
%   a returned Scene's py.*.to_json() round-trips back through jsondecode)
%   rather than hand-building py.cogengine.schema.RadarState(pyargs(...))
%   field-by-field the way the cognitive_engine/ reference stub does -- that
%   stub's field names (n_pulses, doubt_cue-only-arg, ...) predate and don't
%   match this project's actual, evolved RadarState/Scene dataclasses
%   (mode/prf_hz/pri_s/carrier_hz/range_gate_m/vel_gate_mps/scan_phase/
%   doubt_cue). Reusing the dataclasses' own JSON methods means this seam
%   can't silently drift out of sync with schema.py the way a second,
%   hand-written field list could.
%
%   GOLDEN RULE (CLAUDE.md Rule 2): bestScore and everything CEM saw during
%   its search are the twin's imagination. This function returns a Scene,
%   not a verdict -- callers MUST still run the returned scene through the
%   INDEPENDENT judge (cogengine.matlab_judge.export_scene_for_judge ->
%   engine.runJudge) before reporting any deception-performance number.
%   tests/test_decideScene.m does exactly this, once, to prove the seam
%   reaches a real Feedback, not just a Scene-shaped struct. When handing
%   the returned scene back to Python for that (Scene.from_json), use
%   engine.sceneStructToJson(scene), NOT plain jsonencode(scene) -- a
%   one-phantom scene (this project's canonical case) collapses under plain
%   jsonencode in a way that breaks Scene.from_dict; see that function's
%   header for the verified failure.

    if nargin < 2 || isempty(opts); opts = struct(); end
    if ~isfield(opts, 'interceptNoiseAmplitude'); opts.interceptNoiseAmplitude = 2.0; end
    if ~isfield(opts, 'seed'); opts.seed = 1; end

    py.importlib.import_module('cogengine');

    rs = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
    twinConfig = py.cogengine.radar_twin.TwinConfig( ...
        pyargs('intercept_noise_amplitude', opts.interceptNoiseAmplitude));
    cemConfig = py.cogengine.planner_cem.CEMConfig();
    rng = py.numpy.random.default_rng(int64(opts.seed));

    tup = py.cogengine.planner_cem.plan(rs, twinConfig, cemConfig, rng);
    scenePy  = tup{1};
    bestScore = double(tup{2});

    scene = jsondecode(char(scenePy.to_json()));
end
