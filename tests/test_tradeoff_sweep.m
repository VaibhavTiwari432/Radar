classdef test_tradeoff_sweep < matlab.unittest.TestCase
%TEST_TRADEOFF_SWEEP  Task 3 (PHASE2_COMPLETION_POA.md): the headline
%   trade-off table, built from PLANNER-FOUND scenes (cogengine.planner_cem.
%   plan_multi, Task 1), not hand-placed ones -- otherwise this would report
%   the performance of a person's scene design, not the cognitive engine's.
%
%   Two swept axes from a common baseline (N=4, nominal 60 W budget) rather
%   than a full N x budget cross-product (6 CEM searches instead of 12,
%   each axis still independently characterized):
%     1. Phantom count N in {1,2,4,8} at the nominal 60 W shared budget --
%        "EIRP-per-phantom" falls as N rises for a FIXED total budget.
%     2. Shared average power budget in {30,60,120} W at fixed N=4 --
%        decouples "how much power is available" from "how many phantoms".
%   ECCM on/off is read from the SAME judge run, no extra searches needed:
%     ECCM-off survival = confirmed_tracks (anything the tracker confirms)
%     ECCM-on  survival = false_tracks_surviving (confirmed AND labeled real)
%   Each cell: 5 render-noise seeds, mean +/- standard error reported (this
%   project's own established CI style, CLAUDE.md Rule 3's own example:
%   "P(detect)=[...] (+-0.8%, N=5 seeds)").
%
%   ============ PHASE E: WHICH TABLE IS CANONICAL ============
%   Two files in this repo publish an N-sweep at 60 W and they do NOT agree
%   (N=4/60W: 2.00 here vs 1.00 there; N=1: 0.00 here vs 1.00 there). Neither
%   was identified as authoritative, so both were quotable and the pair was
%   self-contradicting. Resolved:
%
%     THIS FILE IS THE CANONICAL TASK 3 TABLE. It is the one Task 3's
%     definition of done ("the radar wins at least one cell") is evaluated
%     against, and it uses CEMConfig's DEFAULT resourcing
%     (population_size=48, iterations=4) uniformly across every cell.
%
%     tests/test_survivor_count_vs_n_resourced.m is NOT a competing table.
%     It is a deliberate CONFOUND CHECK on this one: the same N-axis re-run
%     with population/iterations scaled to each N's dimensionality
%     (population_size = 36*N), to separate "the shared budget is a real
%     physical ceiling" from "the search was starved at high N". Its numbers
%     answer that question and must be quoted WITH the resourcing label
%     attached; they are not a replacement for the cells below.
%
%   Quote either table only with its resourcing stated. They differ because
%   the search budget differs, which is the whole point of having both.
%
%   Golden Rule (CLAUDE.md Rule 2): every cell is CEM's own plan, but scored
%   ONLY by the real, independent judge -- never the twin.

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_tradeoff_table(tc)
            mod = py.importlib.import_module('cogengine.planner_cem');
            radarState = engine.sceneContract().radarState;
            rs = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
            twinConfig = py.cogengine.radar_twin.TwinConfig(pyargs('intercept_noise_amplitude', 2.0));
            cemConfig = mod.CEMConfig();
            nominalBudget = double(mod.GAN_AVG_POWER_W);   % 60 W

            % [n_phantoms, budget_w] per cell -- N-sweep at nominal budget,
            % then budget-sweep at fixed N=4 (60W point already covered).
            cells = [1, nominalBudget; 2, nominalBudget; 4, nominalBudget; 8, nominalBudget; ...
                     4, 30.0; 4, 120.0];

            here = fileparts(mfilename('fullpath'));
            N_SEEDS = 5;
            rowsN = []; rowsOff = []; rowsOn = []; rowsOffSE = []; rowsOnSE = [];

            for ci = 1:size(cells,1)
                nPh = int64(cells(ci,1));
                budget = cells(ci,2);

                planRng = py.numpy.random.default_rng(int64(1000 + ci));
                tic;
                tup = mod.plan_multi(rs, twinConfig, cemConfig, nPh, planRng, pyargs( ...
                    'avg_budget_w', budget, 'peak_budget_w', double(mod.GAN_PEAK_POWER_W)));
                planTime = toc;
                scenePy = tup{1};

                offCounts = zeros(1, N_SEEDS); onCounts = zeros(1, N_SEEDS);
                for s = 1:N_SEEDS
                    tmpMat = fullfile(here, sprintf('_tmp_sweep_%d_%d.mat', ci, s));
                    cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>
                    renderRng = py.numpy.random.default_rng(int64(2000 + ci*100 + s));
                    py.cogengine.matlab_judge.export_scene_for_judge(scenePy, rs, twinConfig, renderRng, tmpMat);
                    fb = engine.runJudge(tmpMat);
                    offCounts(s) = fb.confirmed_tracks;          % ECCM off: anything confirmed
                    onCounts(s)  = fb.false_tracks_surviving;    % ECCM on: confirmed AND real
                end

                rowsN(end+1) = double(nPh); %#ok<AGROW>
                rowsOff(end+1) = mean(offCounts); %#ok<AGROW>
                rowsOn(end+1) = mean(onCounts); %#ok<AGROW>
                rowsOffSE(end+1) = std(offCounts)/sqrt(N_SEEDS); %#ok<AGROW>
                rowsOnSE(end+1) = std(onCounts)/sqrt(N_SEEDS); %#ok<AGROW>

                fprintf('N=%d budget=%.0fW (plan %.1fs): ECCM-off=%.2f+-%.2f  ECCM-on=%.2f+-%.2f  (raw off=%s on=%s)\n', ...
                    cells(ci,1), budget, planTime, rowsOff(end), rowsOffSE(end), rowsOn(end), rowsOnSE(end), ...
                    mat2str(offCounts), mat2str(onCounts));
            end

            fprintf('\n=== Task 3 trade-off table (planner-found scenes, N=%d seeds/cell) ===\n', N_SEEDS);
            fprintf('%-4s %-8s %-20s %-20s\n', 'N', 'Budget', 'ECCM-off survivors', 'ECCM-on survivors');
            for ci = 1:size(cells,1)
                fprintf('%-4d %-7.0fW %5.2f +/- %4.2f          %5.2f +/- %4.2f\n', ...
                    cells(ci,1), cells(ci,2), rowsOff(ci), rowsOffSE(ci), rowsOn(ci), rowsOnSE(ci));
            end

            radarWins = any(rowsOn < 0.5);
            fprintf('\nAt least one cell where the radar effectively wins (ECCM-on survivors < 0.5): %d\n', radarWins);

            tc.verifyTrue(all(rowsOff >= 0));
            tc.verifyTrue(all(rowsOn >= 0));
            tc.verifyTrue(all(rowsOn <= rowsOff + 1e-9), ...
                'ECCM-on survivors should never exceed ECCM-off (ECCM only screens confirmed tracks down, never up).');
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
