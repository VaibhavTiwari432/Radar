classdef test_mixed_swarm_naive_decoy < matlab.unittest.TestCase
%TEST_MIXED_SWARM_NAIVE_DECOY  Is the swarm's 100% "confirmed+real" result
%   (tests/test_four_phantom_swarm.m, test_four_phantom_swarm_seeds.m)
%   because the ECCM discriminator actually screens signatures, or because
%   it's a rubber stamp that would wave through anything? Same 4-phantom
%   swarm, SAME ranges/power, except phantom 4 is swapped for a textbook
%   naive decoy (Stage5_Test.m's own recipe: radial_vel_mps=0 -> zero
%   Doppler, unchanging range -> constant amplitude, no natural
%   scintillation). track.discriminator.m only screens amplitude-range
%   slope and Doppler/range-rate sign -- no class-based or micro-Doppler
%   check, so this isolates exactly the two physical signatures the real
%   judge actually uses.
%
%   Expected, falsifiable: the 3 consistent phantoms still confirm+real;
%   the naive one still gets caught. If the naive one ALSO comes back
%   "real", the earlier 100% result would be suspect (radar not actually
%   discriminating) -- this test exists to rule that out, not to assume it.

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_naive_phantom_still_flagged_inside_swarm(tc)
            C = physics.Constants();
            radarState = engine.sceneContract().radarState;
            ranges = [1800.0, 3000.0, 4200.0, 5400.0];
            refRange = 1800.0; refGain = 3.0;

            phantoms = repmat(engine.sceneContract().phantom, 1, numel(ranges));
            for i = 1:numel(ranges)
                phantoms(i).range_m = ranges(i);
                phantoms(i).radial_vel_mps = -60.0;   % consistent mover, default
                phantoms(i).accel_mps2 = 0.0;
                phantoms(i).rcs_dbsm = 0.0;
                phantoms(i).swerling = 0;
                phantoms(i).amp_scale = refGain * (ranges(i) / refRange)^2;
                phantoms(i).micro = struct('type', "rotor", 'n_blades', 4, ...
                                            'rpm', 3000.0, 'blade_len_m', 0.25);
            end
            % Phantom 4 (farthest, 5400 m): textbook naive decoy -- static
            % range, zero Doppler, constant amplitude. Everything else about
            % it (class, power level) is unchanged so ONLY the kinematic
            % signature differs from its 3 swarm-mates.
            phantoms(4).radial_vel_mps = 0.0;

            scene = struct();
            scene.phantoms = phantoms;
            scene.maneuver = "swarm";
            scene.eirp_budget_dbw = 20.0;
            scene.t0_s = 0.0;
            scene.duration_s = 8.0;

            scenePy = py.cogengine.schema.Scene.from_json(engine.sceneStructToJson(scene));
            rsPy = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
            twinConfig = py.cogengine.radar_twin.TwinConfig(pyargs('intercept_noise_amplitude', 2.0));

            here = fileparts(mfilename('fullpath'));
            tmpMat = fullfile(here, '_tmp_mixed_swarm_naive.mat');
            cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>

            renderRng = py.numpy.random.default_rng(int64(60001));
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

            % Phantom 4's true final range never moves (static): ~5400 m.
            naiveIdx = find(abs(distinctRanges - 5400) < 200, 1);
            moverIdx = find(abs(distinctRanges - 5400) >= 200);

            fprintf(['\n=== Mixed swarm: 3 consistent movers + 1 naive static decoy ===\n' ...
                'distinct phantoms=%d  labels=%s  ranges=%s\n'], ...
                numel(distinctRanges), strjoin(distinctLabels, ','), mat2str(distinctRanges, 6));

            tc.verifyNotEmpty(naiveIdx, 'The static phantom should still show up at ~5400 m.');
            if ~isempty(naiveIdx)
                fprintf('naive static phantom (~5400 m): label=%s\n', distinctLabels(naiveIdx));
                tc.verifyEqual(distinctLabels(naiveIdx), "decoy", ...
                    'The naive static/zero-Doppler phantom should be flagged, not waved through.');
            end
            tc.verifyEqual(numel(moverIdx), 3, 'The 3 consistent movers should still all be present.');
            if numel(moverIdx) == 3
                fprintf('consistent movers: labels=%s\n', strjoin(distinctLabels(moverIdx), ','));
                tc.verifyTrue(all(distinctLabels(moverIdx) == "real"), ...
                    'The 3 consistent movers should still confirm as real.');
            end
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
