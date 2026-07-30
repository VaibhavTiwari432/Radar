classdef test_missionsim_stream < matlab.unittest.TestCase
%TEST_MISSIONSIM_STREAM  Live-streaming bridge: missionsim.buildFrameLog's
%   new onFrame callback, and missionsim.streamManualSceneToFile built on
%   top of it -- the backend half of watching a mission unfold live in the
%   web client instead of loading a finished log.

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_onFrame_callback_fires_once_per_frame_in_order(tc)
            controls.n = 2; controls.amplitudeProfile = 'uniform'; controls.phaseProfile = 'coherent';
            phantoms = missionsim.buildSceneFromControls(controls);
            C = physics.Constants();
            radarState = engine.sceneContract().radarState;
            scene = struct('phantoms', phantoms, 'maneuver', "swarm", ...
                            'eirp_budget_dbw', 20.0, 't0_s', 0.0, 'duration_s', 8.0);
            scenePy = py.cogengine.schema.Scene.from_json(engine.sceneStructToJson(scene));
            rsPy = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
            twinConfig = py.cogengine.radar_twin.TwinConfig(pyargs('intercept_noise_amplitude', 2.0));
            renderRng = py.numpy.random.default_rng(int64(20261166));

            tmpMat = [tempname(), '.mat'];
            cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>
            py.cogengine.matlab_judge.export_scene_for_judge(scenePy, rsPy, twinConfig, renderRng, tmpMat);
            feedback = engine.runJudge(tmpMat);
            S = load(tmpMat);

            % containers.Map is a HANDLE class -- safe to mutate from inside
            % an anonymous function's body (plain structs/arrays captured by
            % an anonymous function are captured BY VALUE and can't be
            % mutated from outside), the same reasoning already used for
            % MissionSimulatorApp's own TrackMarkerOpacities.
            collector = containers.Map('KeyType', 'double', 'ValueType', 'any');
            onFrame = @(f) localStash(collector, f);
            frameLog = missionsim.buildFrameLog(phantoms, S, feedback, C, onFrame);

            tc.verifyEqual(double(collector.Count), numel(frameLog), 'onFrame should fire exactly once per frame.');
            for k = 1:numel(frameLog)
                tc.verifyTrue(isKey(collector, k), sprintf('onFrame never fired for frame %d', k));
                tc.verifyEqual(collector(k).frame, k);
            end
        end

        function test_stream_to_file_produces_valid_ndjson_with_end_marker(tc)
            controls.n = 3; controls.amplitudeProfile = 'decaying'; controls.phaseProfile = 'random';
            here = fileparts(mfilename('fullpath'));
            outFile = fullfile(here, '_tmp_stream_test.jsonl');
            cleanupObj = onCleanup(@() localDeleteIfExists(outFile)); %#ok<NASGU>

            missionsim.streamManualSceneToFile(controls, outFile, struct('paced', false));

            tc.verifyTrue(isfile(outFile));
            raw = fileread(outFile);
            lines = strsplit(strtrim(raw), newline);
            tc.verifyGreaterThan(numel(lines), 1, 'Expected multiple frame lines plus an end marker.');

            lastLine = jsondecode(lines{end});
            tc.verifyEqual(lastLine.marker, '__end__');

            frameLines = lines(1:end-1);
            for i = 1:numel(frameLines)
                f = jsondecode(frameLines{i});
                [valid, errors] = missionsim.validateFrame(f);
                tc.verifyTrue(valid, sprintf('line %d fails schema: %s', i, strjoin(errors, '; ')));
                tc.verifyEqual(f.frame, i);
            end
        end

        function test_stream_to_file_truncates_a_stale_prior_run(tc)
            here = fileparts(mfilename('fullpath'));
            outFile = fullfile(here, '_tmp_stream_stale_test.jsonl');
            cleanupObj = onCleanup(@() localDeleteIfExists(outFile)); %#ok<NASGU>

            fid = fopen(outFile, 'w');
            fprintf(fid, 'stale garbage from a previous mission\n');
            fclose(fid);

            controls.n = 1; controls.amplitudeProfile = 'uniform'; controls.phaseProfile = 'coherent';
            missionsim.streamManualSceneToFile(controls, outFile, struct('paced', false));

            raw = fileread(outFile);
            tc.verifyFalse(contains(raw, 'stale garbage'), ...
                'A fresh stream must truncate stale content from a previous run.');
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

function localStash(collector, f)
    collector(f.frame) = f;
end
