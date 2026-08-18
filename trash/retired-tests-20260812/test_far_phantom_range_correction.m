classdef test_far_phantom_range_correction < matlab.unittest.TestCase
%TEST_FAR_PHANTOM_RANGE_CORRECTION  Follow-up to Task 3's "survivor count
%   vs N" investigation (PHASE2_COMPLETION_POA.md): CEM's N=1 search
%   (population/iterations properly scaled per plan_multi's own sizing
%   guidance) converged to range=5708.1m, v=-16.7 m/s, amp_scale=3.0 (the
%   full 60W budget) -- and the REAL judge flickered real/decoy/decoy/
%   decoy/decoy across 5 noise seeds on the IDENTICAL, deterministic range
%   history each time (verified: quantization-dominated, amplitude-noise-
%   decided outcome, not a range-trend difference).
%
%   Root cause: range_m and power_w were sampled independently in
%   cogengine/planner_cem.py's search space, so a phantom could end up far
%   enough that even its FULL budget share produces a barely-detectable
%   signal -- amplitude_law's 1/R^2 law means the same amp_scale that is
%   rock-solid at REFERENCE_RANGE_M (1800m) is noise-dominated far out.
%   Fixed: _enforce_max_range_for_power pulls the phantom's range in
%   (never power up past the hard budget ceiling -- an earlier version of
%   the fix tried that and was a no-op, see planner_cem.py's own comment)
%   to whatever its ACTUAL, post-budget power can reliably support.
%
%   This test proves the SAME failing scene (same seed) now confirms
%   reliably instead of flickering.

    methods (TestClassSetup)
        function requirePython(tc)
            tc.assumeTrue(localPythonReady(), ...
                'cogengine not importable from this MATLAB''s Python environment (pyenv).');
        end
    end

    methods (Test)

        function test_n1_scene_no_longer_flickers(tc)
            mod = py.importlib.import_module('cogengine.planner_cem');
            radarState = engine.sceneContract().radarState;
            rs = py.cogengine.schema.RadarState.from_json(jsonencode(radarState));
            twinConfig = py.cogengine.radar_twin.TwinConfig(pyargs('intercept_noise_amplitude', 2.0));
            cemConfig = mod.CEMConfig(pyargs('population_size', int64(36), 'iterations', int64(8)));

            % SAME seed that originally produced the flickering range=5708m scene.
            planRng = py.numpy.random.default_rng(int64(5001));
            tup = mod.plan_multi(rs, twinConfig, cemConfig, int64(1), planRng, pyargs( ...
                'avg_budget_w', 60.0, 'peak_budget_w', 200.0));
            scenePy = tup{1};
            scene = jsondecode(char(scenePy.to_json()));
            p = scene.phantoms(1);
            fprintf('planned phantom (post-fix): range=%.1f v=%.1f amp_scale=%.3f\n', ...
                p.range_m, p.radial_vel_mps, p.amp_scale);

            tc.verifyLessThan(p.range_m, 5000, ...
                'The far, under-powered range this seed originally converged to should now be pulled in.');

            here = fileparts(mfilename('fullpath'));
            N = 5;
            labels = strings(1, N);
            for s = 1:N
                tmpMat = fullfile(here, sprintf('_tmp_farphantom_%d.mat', s));
                cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>
                renderRng = py.numpy.random.default_rng(int64(6000 + 1*100 + s));
                py.cogengine.matlab_judge.export_scene_for_judge(scenePy, rs, twinConfig, renderRng, tmpMat);
                fb = engine.runJudge(tmpMat);
                if fb.confirmed_tracks >= 1
                    labels(s) = string(fb.track_label{1});
                else
                    labels(s) = "none";
                end
            end
            fprintf('labels across %d seeds: %s\n', N, strjoin(labels, ','));

            realCount = nnz(labels == "real");
            tc.verifyGreaterThanOrEqual(realCount, 4, ...
                sprintf('Expected reliable (>=4/%d) real confirmation after the range fix, got %d/%d: %s', ...
                    N, realCount, N, strjoin(labels, ',')));
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
