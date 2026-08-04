classdef test_missionsim_frame_builder < matlab.unittest.TestCase
%TEST_MISSIONSIM_FRAME_BUILDER  Mission Simulator's bridge from the real,
%   already-validated backend to the UI frame schema
%   (missionsim.buildFrameLog): runs this project's own canonical 4-phantom
%   swarm (tests/test_four_phantom_swarm.m's recipe) through the REAL
%   judge, builds a frame log from the result, and checks it against both
%   the schema (missionsim.validateFrame, enforced internally by
%   buildFrameLog itself) and known facts about that scene (4 phantoms
%   confirm real by the end, per that test's own already-established
%   result: confirmed=4 surviving_real=4 flagged_decoy=0).
%
%   Also the regression test for a real MATLAB gotcha found while building
%   this: union()'s output orientation is not guaranteed row, and
%   `for id = column_vector` iterates ONCE with id bound to the WHOLE
%   column, not once per element -- caused a real crash
%   ("logical indices...outside of the array bounds"), fixed with an
%   explicit seenIDs(:)' transpose in buildFrameLog.m.

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_builds_valid_frame_log_from_real_judge_run(tc)
            C = physics.Constants();
            radarState = engine.sceneContract().radarState;
            ranges = [1800.0, 3000.0, 4200.0, 5400.0];
            refRange = 1800.0; refGain = 3.0;
            phantoms = repmat(engine.sceneContract().phantom, 1, numel(ranges));
            for i = 1:numel(ranges)
                phantoms(i).range_m = ranges(i);
                % Velocity inherited from engine.sceneContract (was a stale
                % restated -60.0, past v_ua -> folded -> decoy).
                phantoms(i).accel_mps2 = 0.0;
                phantoms(i).rcs_dbsm = 0.0;
                phantoms(i).swerling = 0;
                phantoms(i).amp_scale = refGain * (ranges(i) / refRange)^2;
                phantoms(i).micro = struct('type', "rotor", 'n_blades', 4, ...
                                            'rpm', 3000.0, 'blade_len_m', 0.25);
            end
            scene = struct('phantoms', phantoms, 'maneuver', "swarm", ...
                            'eirp_budget_dbw', 20.0, 't0_s', 0.0, 'duration_s', 8.0);
            scenePy = py.cogengine.schema.Scene.from_json(engine.sceneStructToJson(scene));
            rsPy = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
            twinConfig = py.cogengine.radar_twin.TwinConfig(pyargs('intercept_noise_amplitude', 2.0));

            here = fileparts(mfilename('fullpath'));
            tmpMat = fullfile(here, '_tmp_missionsim_framebuilder.mat');
            cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>
            renderRng = py.numpy.random.default_rng(int64(40002));
            py.cogengine.matlab_judge.export_scene_for_judge(scenePy, rsPy, twinConfig, renderRng, tmpMat);

            feedback = engine.runJudge(tmpMat);
            tc.assumeGreaterThanOrEqual(feedback.confirmed_tracks, 4, ...
                'This test depends on the canonical scene''s known 4/4 result.');

            S = load(tmpMat);
            frameLog = missionsim.buildFrameLog(phantoms, S, feedback, C);

            tc.verifyEqual(numel(frameLog), feedback.num_frames);
            for k = 1:numel(frameLog)
                [valid, errors] = missionsim.validateFrame(frameLog{k});
                tc.verifyTrue(valid, sprintf('frame %d failed schema: %s', k, strjoin(errors, '; ')));
            end

            lastFrame = frameLog{end};
            tc.verifyEqual(lastFrame.phase, 'DECEPTION_HOLDING', ...
                '>=2 confirmed tracks by the final frame should hold DECEPTION_HOLDING.');
            tc.verifyEqual(numel(lastFrame.radar.tracks), 4);
            verdicts = {lastFrame.radar.tracks.eccmVerdict};
            tc.verifyEqual(verdicts, repmat({'REAL'}, 1, 4), ...
                'Known result (test_four_phantom_swarm.m): all 4 phantoms confirm real.');
            states = {lastFrame.radar.tracks.state};
            tc.verifyEqual(states, repmat({'CONFIRMED'}, 1, 4));

            % Ground truth (synth/truth blocks) present and physically sane.
            tc.verifyEqual(numel(frameLog{1}.synth.phantoms), 4);
            tc.verifyEqual(numel(frameLog{1}.truth.phantoms), 4);
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
