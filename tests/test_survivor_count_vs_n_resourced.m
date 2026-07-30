classdef test_survivor_count_vs_n_resourced < matlab.unittest.TestCase
%TEST_SURVIVOR_COUNT_VS_N_RESOURCED  Follow-up to Task 3's trade-off sweep
%   (PHASE2_COMPLETION_POA.md): the sweep's N-axis (N=1,2,4,8 at 60 W) used
%   CEMConfig's bare default (population_size=48, iterations=4) for EVERY
%   cell, including N=8 -- a 24-dimensional search, twice the dimensionality
%   of the N=4 case that was directly PROVEN under-resourced this same
%   session (plan_multi's own docstring: the default found 1.00/4 real vs.
%   a properly-resourced 150/8 config's 2.20/4, same scene, same budget).
%
%   That means the sweep's own "survivors plateau at ~1 regardless of N"
%   finding is confounded: it might be a genuine budget-limited physical
%   ceiling, or it might just be every N>1 cell being search-starved. This
%   test re-runs the SAME N-sweep with population/iterations scaled to each
%   N's actual dimensionality (population_size ~= 36*n_phantoms per
%   plan_multi's own sizing guidance, iterations=8 throughout) and reports
%   the corrected numbers -- whatever they turn out to be, not a predicted
%   or hoped-for direction.

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_n_sweep_properly_resourced(tc)
            mod = py.importlib.import_module('cogengine.planner_cem');
            radarState = engine.sceneContract().radarState;
            rs = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
            twinConfig = py.cogengine.radar_twin.TwinConfig(pyargs('intercept_noise_amplitude', 2.0));
            nominalBudget = double(mod.GAN_AVG_POWER_W);

            Ns = [1, 2, 4, 8];
            here = fileparts(mfilename('fullpath'));
            N_SEEDS = 5;

            offMean = zeros(1, numel(Ns)); onMean = zeros(1, numel(Ns));
            offSE = zeros(1, numel(Ns)); onSE = zeros(1, numel(Ns));
            planTimes = zeros(1, numel(Ns));

            for ni = 1:numel(Ns)
                nPh = Ns(ni);
                popSize = int64(36 * nPh);   % plan_multi's own sizing guidance
                cemConfig = mod.CEMConfig(pyargs('population_size', popSize, 'iterations', int64(8)));

                planRng = py.numpy.random.default_rng(int64(5000 + ni));
                tic;
                tup = mod.plan_multi(rs, twinConfig, cemConfig, int64(nPh), planRng, pyargs( ...
                    'avg_budget_w', nominalBudget, 'peak_budget_w', double(mod.GAN_PEAK_POWER_W)));
                planTimes(ni) = toc;
                scenePy = tup{1};

                offCounts = zeros(1, N_SEEDS); onCounts = zeros(1, N_SEEDS);
                for s = 1:N_SEEDS
                    tmpMat = fullfile(here, sprintf('_tmp_nres_%d_%d.mat', ni, s));
                    cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>
                    renderRng = py.numpy.random.default_rng(int64(6000 + ni*100 + s));
                    py.cogengine.matlab_judge.export_scene_for_judge(scenePy, rs, twinConfig, renderRng, tmpMat);
                    fb = engine.runJudge(tmpMat);
                    offCounts(s) = fb.confirmed_tracks;
                    onCounts(s) = fb.false_tracks_surviving;
                end

                offMean(ni) = mean(offCounts); onMean(ni) = mean(onCounts);
                offSE(ni) = std(offCounts)/sqrt(N_SEEDS); onSE(ni) = std(onCounts)/sqrt(N_SEEDS);

                fprintf('N=%d (pop=%d, plan %.1fs): ECCM-off=%.2f+-%.2f  ECCM-on=%.2f+-%.2f  (raw off=%s on=%s)\n', ...
                    nPh, popSize, planTimes(ni), offMean(ni), offSE(ni), onMean(ni), onSE(ni), ...
                    mat2str(offCounts), mat2str(onCounts));
            end

            fprintf('\n=== N-sweep, PROPERLY RESOURCED (pop=36*N, iters=8) vs Task 3''s ORIGINAL (pop=48,iters=4) ===\n');
            fprintf('%-4s %-22s %-22s %-22s\n', 'N', 'ECCM-on (resourced)', 'ECCM-on (original)', 'Delta');
            originalOn = [0.00, 1.20, 1.20, 1.00];   % Task 3's own recorded numbers, for direct comparison
            for ni = 1:numel(Ns)
                fprintf('%-4d %5.2f +/- %4.2f          %5.2f                   %+.2f\n', ...
                    Ns(ni), onMean(ni), onSE(ni), originalOn(ni), onMean(ni)-originalOn(ni));
            end

            tc.verifyTrue(all(onMean >= 0));
            tc.verifyTrue(all(onMean <= offMean + 1e-9));
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
