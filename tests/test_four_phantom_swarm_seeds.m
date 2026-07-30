classdef test_four_phantom_swarm_seeds < matlab.unittest.TestCase
%TEST_FOUR_PHANTOM_SWARM_SEEDS  N-seed statistic for the 4-phantom mother-
%   drone swarm (tests/test_four_phantom_swarm.m proved the mechanism once;
%   CLAUDE.md Rule 5 wants value +/- N trials, not a single run, and
%   Integration_Report.md's own Recommendation section says exactly this:
%   "widen to more seeds"). Same scene recipe every trial (drone, v=-60 m/s
%   closing, rotor micro-motion, power-equalized across ranges
%   1800/3000/4200/5400 m) -- only the render RNG seed (intercept noise +
%   receiver noise draws) varies, so this measures ROBUSTNESS to noise, not
%   a different scenario each time.

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_deception_rate_over_seeds(tc)
            C = physics.Constants();
            radarState = engine.sceneContract().radarState;
            ranges = [1800.0, 3000.0, 4200.0, 5400.0];
            refRange = 1800.0; refGain = 3.0;

            N = 8;
            allFourReal = false(1, N);
            distinctCount = zeros(1, N);
            realCount = zeros(1, N);
            decoyCount = zeros(1, N);

            here = fileparts(mfilename('fullpath'));

            for s = 1:N
                phantoms = repmat(engine.sceneContract().phantom, 1, numel(ranges));
                for i = 1:numel(ranges)
                    phantoms(i).range_m = ranges(i);
                    phantoms(i).radial_vel_mps = -60.0;
                    phantoms(i).accel_mps2 = 0.0;
                    phantoms(i).rcs_dbsm = 0.0;
                    phantoms(i).swerling = 0;
                    phantoms(i).amp_scale = refGain * (ranges(i) / refRange)^2;
                    phantoms(i).micro = struct('type', "rotor", 'n_blades', 4, ...
                                                'rpm', 3000.0, 'blade_len_m', 0.25);
                end
                scene = struct('phantoms', {phantoms}, 'maneuver', "swarm", ...
                                'eirp_budget_dbw', 20.0, 't0_s', 0.0, 'duration_s', 8.0);

                scenePy = py.cogengine.schema.Scene.from_json(engine.sceneStructToJson(scene));
                rsPy = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
                twinConfig = py.cogengine.radar_twin.TwinConfig(pyargs('intercept_noise_amplitude', 2.0));

                tmpMat = fullfile(here, sprintf('_tmp_swarm_seed_%d.mat', s));
                cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>

                renderRng = py.numpy.random.default_rng(int64(50000 + s));
                py.cogengine.matlab_judge.export_scene_for_judge(scenePy, rsPy, twinConfig, renderRng, tmpMat);

                feedback = engine.runJudge(tmpMat);

                lastRanges = nan(1, numel(feedback.track_range_m));
                for i = 1:numel(feedback.track_range_m)
                    r = feedback.track_range_m{i};
                    if ~isempty(r); lastRanges(i) = r(end); end
                end
                distinctRanges = []; distinctLabels = strings(0);
                for i = 1:numel(lastRanges)
                    r = lastRanges(i);
                    if isnan(r); continue; end
                    if isempty(distinctRanges) || all(abs(distinctRanges - r) > 3 * C.range_per_sample)
                        distinctRanges(end+1) = r; %#ok<AGROW>
                        distinctLabels(end+1) = string(feedback.track_label{i}); %#ok<AGROW>
                    end
                end

                distinctCount(s) = numel(distinctRanges);
                realCount(s) = nnz(distinctLabels == "real");
                decoyCount(s) = nnz(distinctLabels == "decoy");
                allFourReal(s) = (realCount(s) == numel(ranges)) && (decoyCount(s) == 0);

                fprintf('seed %d: distinct_phantoms=%d real=%d decoy=%d confirmed_tracks(raw)=%d\n', ...
                    s, distinctCount(s), realCount(s), decoyCount(s), feedback.confirmed_tracks);
            end

            rate = mean(allFourReal);
            phantomRealRate = sum(realCount) / (numel(ranges) * N);
            fprintf(['\n=== 4-phantom swarm deception rate, N=%d seeds ===\n' ...
                'All 4 confirmed+real, 0 flagged: %d/%d trials (%.0f%%)\n' ...
                'Per-phantom real rate: %d/%d (%.1f%%)\n'], ...
                N, nnz(allFourReal), N, 100*rate, sum(realCount), numel(ranges)*N, 100*phantomRealRate);

            tc.verifyGreaterThanOrEqual(rate, 0);
            tc.verifyLessThanOrEqual(rate, 1);
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
