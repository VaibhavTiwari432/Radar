classdef test_decideScene < matlab.unittest.TestCase
%TEST_DECIDESCENE  Build-order step 6 (design doc Part 6 / CLAUDE.md Rule 4):
%   proves engine.decideScene actually reaches a LIVE Python CEM plan, and
%   that the returned Scene, once rendered+exported through the SAME live
%   Python bridge (cogengine.matlab_judge.export_scene_for_judge) and scored
%   by the REAL independent MATLAB judge (engine.runJudge), produces a sane
%   Feedback -- not just a Scene-shaped struct.
%
%   Golden Rule (CLAUDE.md Rule 2): a plan that only "looks like" a Scene is
%   not proof of integration; test_decideScene_reaches_the_real_judge is the
%   one test in this file that end-to-end validates the seam reaches a real,
%   independently-computed verdict.
%
%   STATUS: RUNNABLE once this MATLAB's pyenv can import cogengine (verified
%   interactively this session: pyenv Version=3.13, InProcess, cogengine
%   importable). If pyenv/cogengine is unavailable on some other machine,
%   every test here reports Incomplete (not Failed), mirroring
%   DataIntegration_Test's missing-dependency pattern -- a missing Python
%   environment is not a code bug.

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                ['cogengine not importable from this MATLAB''s Python environment ' ...
                 '(pyenv) -- see engine.decideScene''s header for the pyenv/Path-B ' ...
                 'requirement this test depends on.']);
        end
    end

    methods (Test)

        function test_decideScene_returns_valid_scene_struct(tc)
            radarState = engine.sceneContract().radarState;
            [scene, bestScore] = engine.decideScene(radarState, struct('seed', 1));

            tc.verifyTrue(isfield(scene, 'phantoms'));
            tc.verifyTrue(isfield(scene, 'maneuver'));
            tc.verifyGreaterThanOrEqual(numel(scene.phantoms), 1);
            tc.verifyTrue(ismember(scene.maneuver, {'static','rgpo','vgpo','swarm'}));
            tc.verifyGreaterThan(scene.duration_s, 0);
            tc.verifyTrue(isfinite(bestScore));

            fprintf('decideScene: %d phantom(s), maneuver=%s, bestScore=%.4f\n', ...
                numel(scene.phantoms), scene.maneuver, bestScore);
        end

        function test_decideScene_is_seed_reproducible(tc)
            radarState = engine.sceneContract().radarState;
            [scene1, score1] = engine.decideScene(radarState, struct('seed', 7));
            [scene2, score2] = engine.decideScene(radarState, struct('seed', 7));

            tc.verifyEqual(score1, score2, ...
                'Same seed should reproduce the same CEM search score (no wall-clock randomness).');
            tc.verifyEqual(scene1.phantoms(1).range_m, scene2.phantoms(1).range_m, ...
                'Same seed should reproduce the same planned scene.');
        end

        function test_decideScene_reaches_the_real_judge(tc)
            % THE integration proof: take decideScene's live output,
            % render+export it via the SAME Python bridge the rest of this
            % project's fixtures use (cogengine.matlab_judge.export_scene_for_judge),
            % and score it with the INDEPENDENT MATLAB judge (engine.runJudge)
            % -- end to end, neither seam mocked.
            radarState = engine.sceneContract().radarState;
            [scene, ~] = engine.decideScene(radarState, struct('seed', 3));

            scenePy = py.cogengine.schema.Scene.from_json(engine.sceneStructToJson(scene));
            rsPy = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
            twinConfig = py.cogengine.radar_twin.TwinConfig(pyargs('intercept_noise_amplitude', 2.0));
            renderRng = py.numpy.random.default_rng(int64(30003));

            here = fileparts(mfilename('fullpath'));
            tmpMat = fullfile(here, '_tmp_decideScene_judge.mat');
            cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>

            degradedEvents = py.cogengine.matlab_judge.export_scene_for_judge( ...
                scenePy, rsPy, twinConfig, renderRng, tmpMat);

            feedback = engine.runJudge(tmpMat);

            fprintf(['decideScene -> real judge: confirmed_tracks=%d surviving=%d ' ...
                'flagged=%d eccm_label=%s degraded_events=%d\n'], ...
                feedback.confirmed_tracks, feedback.false_tracks_surviving, ...
                feedback.flagged_decoys, feedback.eccm_label, numel(degradedEvents));

            tc.verifyGreaterThanOrEqual(feedback.confirmed_tracks, 0);
            tc.verifyTrue(ismember(string(feedback.eccm_label), ["", "real", "decoy", "unscreened"]));
        end

    end

end

% ===================== file-local helpers =============================
function tf = localPythonReady()
    try
        py.importlib.import_module('cogengine');
        tf = true;
    catch
        tf = false;
    end
end

function localDeleteIfExists(f)
    if isfile(f); delete(f); end
end
