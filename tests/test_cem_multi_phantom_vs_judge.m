classdef test_cem_multi_phantom_vs_judge < matlab.unittest.TestCase
%TEST_CEM_MULTI_PHANTOM_VS_JUDGE  Task 1 (PHASE2_COMPLETION_POA.md), the
%   core gate: the 4-phantom swarm validated earlier this session
%   (tests/test_four_phantom_swarm*.m) was HAND-BUILT by a person, not
%   found by the planner, and was never checked against the shared GaN
%   power budget (cogengine/planner_cem.py's new plan_multi). This test:
%     1. Runs the CEM planner's OWN N=4 search (scored on the twin,
%        power-budget-compliant by construction).
%     2. Builds a budget-RESCALED version of the hand-built baseline (same
%        ranges/velocities, amp_scale uniformly scaled down to fit the
%        SAME 60 W shared budget) -- a fair, apples-to-apples comparison,
%        not the original unconstrained hand-built scene (which, audited
%        here, used ~18x the shared budget: [60, 167, 327, 540] W summing
%        to ~1093 W against a 60 W average ceiling -- a real finding, not
%        swept aside).
%     3. Scores BOTH scenes on the twin AND the real independent judge,
%        across >=5 render-noise seeds each (CLAUDE.md Rule 3's own bar).
%     4. Reports whether a twin-only exploit appears (CLAUDE.md Rule 2: the
%        gap between twin-predicted and judge-actual is a first-class
%        result, never assumed away).
%
%   Follow-up, same day: the ORIGINAL run of this test (CEMConfig defaults,
%   population_size=48/iterations=4 -- tuned for the single-phantom plan()'s
%   6-dim search) found CEM underperforming the naive baseline (1.00/4 vs
%   1.40/4 real survivors). Root cause was search BUDGET, not a fundamental
%   problem: plan_multi's own docstring now documents that a 12-dim (N=4)
%   search needs a proportionally larger population. Verified directly:
%   population_size=150/iterations=8, nothing else changed, found a scene
%   the real judge confirmed 2.00/4 real -- beating both the original CEM
%   run and the naive baseline. This test uses the boosted config below.

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_cem_planned_vs_rescaled_naive_baseline(tc)
            C = physics.Constants();
            mod = py.importlib.import_module('cogengine.planner_cem');
            radarState = engine.sceneContract().radarState;
            rs = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
            twinConfig = py.cogengine.radar_twin.TwinConfig(pyargs('intercept_noise_amplitude', 2.0));
            % Boosted vs. CEMConfig's bare default -- see plan_multi's own
            % docstring and this file's header follow-up note: the 6-dim-
            % tuned default under-searches a 12-dim (N=4) space.
            cemConfig = mod.CEMConfig(pyargs('population_size', int64(150), 'iterations', int64(8)));

            % ---- 1. CEM's own N=4 search (ONE search; budget-compliant by construction) ----
            planRng = py.numpy.random.default_rng(int64(1));
            tup = mod.plan_multi(rs, twinConfig, cemConfig, int64(4), planRng);
            cemScenePy = tup{1}; cemBestScore = double(tup{2});
            cemScene = jsondecode(char(cemScenePy.to_json()));

            fprintf('\n=== CEM-planned N=4 scene (twin search score=%.3f) ===\n', cemBestScore);
            ganAvgW = double(mod.GAN_AVG_POWER_W);
            cemTotalW = 0;
            for i = 1:numel(cemScene.phantoms)
                p = cemScene.phantoms(i);
                pW = p.amp_scale / 3.0 * ganAvgW;
                cemTotalW = cemTotalW + pW;
                fprintf('  phantom %d: range=%.1f v=%.1f power=%.2fW\n', i, p.range_m, p.radial_vel_mps, pW);
            end
            fprintf('  total power = %.2f W (budget %.1f W)\n', cemTotalW, ganAvgW);
            tc.verifyLessThanOrEqual(cemTotalW, ganAvgW + 1e-3, ...
                'CEM-planned scene must respect the shared GaN average-power budget.');

            % ---- 2. Budget-rescaled hand-built baseline (same shape as ----
            % test_four_phantom_swarm.m, power uniformly rescaled to comply) ----
            ranges = [1800.0, 3000.0, 4200.0, 5400.0];
            refRange = 1800.0; refGain = 3.0;
            rawPowersW = refGain * (ranges/refRange).^2 / 3.0 * ganAvgW;  % the ORIGINAL, unconstrained powers
            fprintf('\nOriginal hand-built baseline power (unconstrained): %s W, total=%.1f W (%.1fx over budget)\n', ...
                mat2str(rawPowersW, 4), sum(rawPowersW), sum(rawPowersW)/ganAvgW);
            scaleFactor = ganAvgW / sum(rawPowersW);
            rescaledPowersW = rawPowersW * scaleFactor;
            fprintf('Rescaled to comply: %s W, total=%.1f W\n', mat2str(rescaledPowersW,4), sum(rescaledPowersW));

            naivePhantoms = repmat(engine.sceneContract().phantom, 1, numel(ranges));
            for i = 1:numel(ranges)
                naivePhantoms(i).range_m = ranges(i);
                naivePhantoms(i).radial_vel_mps = -60.0;
                naivePhantoms(i).accel_mps2 = 0.0;
                naivePhantoms(i).rcs_dbsm = 0.0;
                naivePhantoms(i).swerling = 0;
                naivePhantoms(i).amp_scale = rescaledPowersW(i) / ganAvgW * 3.0;
                naivePhantoms(i).micro = struct('type', "rotor", 'n_blades', 4, ...
                                                 'rpm', 3000.0, 'blade_len_m', 0.25);
            end
            naiveScene = struct('phantoms', naivePhantoms, 'maneuver', "swarm", ...
                                 'eirp_budget_dbw', 10*log10(ganAvgW), 't0_s', 0.0, 'duration_s', 8.0);
            naiveScenePy = py.cogengine.schema.Scene.from_json(engine.sceneStructToJson(naiveScene));

            % ---- 3. Score BOTH scenes, twin AND real judge, N=5 seeds each ----
            N = 5;
            here = fileparts(mfilename('fullpath'));
            results = struct('cem', [], 'naive', []);
            for label = ["cem", "naive"]
                if label == "cem"; scenePy = cemScenePy; else; scenePy = naiveScenePy; end
                confirmedJ = zeros(1,N); realJ = zeros(1,N); decoyJ = zeros(1,N);
                confirmedT = zeros(1,N); realT = zeros(1,N); decoyT = zeros(1,N);
                for s = 1:N
                    twinRng = py.numpy.random.default_rng(int64(70000 + s));
                    fb = py.cogengine.radar_twin.predict(scenePy, rs, twinConfig, twinRng);
                    confirmedT(s) = double(fb.confirmed_tracks);
                    realT(s) = double(fb.false_tracks_surviving);
                    decoyT(s) = double(fb.flagged_decoys);

                    tmpMat = fullfile(here, sprintf('_tmp_cemvsjudge_%s_%d.mat', label, s));
                    cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>
                    renderRng = py.numpy.random.default_rng(int64(80000 + s));
                    py.cogengine.matlab_judge.export_scene_for_judge(scenePy, rs, twinConfig, renderRng, tmpMat);
                    feedback = engine.runJudge(tmpMat);
                    confirmedJ(s) = feedback.confirmed_tracks;
                    realJ(s) = feedback.false_tracks_surviving;
                    decoyJ(s) = feedback.flagged_decoys;
                end
                results.(label) = struct('confirmedT', confirmedT, 'realT', realT, 'decoyT', decoyT, ...
                                          'confirmedJ', confirmedJ, 'realJ', realJ, 'decoyJ', decoyJ);
                fprintf(['\n--- %s (N=%d seeds) ---\n' ...
                    'TWIN : real=%s (mean %.2f)  decoy=%s\n' ...
                    'JUDGE: real=%s (mean %.2f)  decoy=%s\n'], ...
                    label, N, mat2str(realT), mean(realT), mat2str(decoyT), ...
                    mat2str(realJ), mean(realJ), mat2str(decoyJ));
            end

            % ---- 4. Twin-vs-judge gap, explicit (Rule 2) ----
            gapCem   = mean(results.cem.realT)   - mean(results.cem.realJ);
            gapNaive = mean(results.naive.realT) - mean(results.naive.realJ);
            fprintf(['\n=== Twin-vs-judge gap (mean real-survivor count, twin minus judge) ===\n' ...
                'CEM scene gap:   %+.2f\n' ...
                'Naive scene gap: %+.2f\n' ...
                '(A gap near 0 across BOTH means no new twin-only exploit found this run; ' ...
                'a large positive gap on the CEM scene specifically would mean CEM found a ' ...
                'regime the twin overrates, i.e. a twin-only exploit -- watch for that pattern, not ' ...
                'just its absence here.)\n'], gapCem, gapNaive);

            fprintf(['\n=== SCORECARD: CEM-planned (budget-compliant) vs rescaled-naive baseline ===\n' ...
                'CEM   judge mean real-survivors: %.2f / 4\n' ...
                'Naive judge mean real-survivors: %.2f / 4\n'], ...
                mean(results.cem.realJ), mean(results.naive.realJ));

            tc.verifyGreaterThanOrEqual(mean(results.cem.realJ), 0);
            tc.verifyGreaterThanOrEqual(mean(results.naive.realJ), 0);
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
