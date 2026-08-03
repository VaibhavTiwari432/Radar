classdef test_range_ambiguity < matlab.unittest.TestCase
%TEST_RANGE_AMBIGUITY  Phase C1: the planner and the judge must agree about
%   where a phantom IS -- including when it is past the radar's unambiguous
%   range and the radar therefore cannot see it where it was put.
%
%   Before C1: physics.Constants derived R_unambiguous and
%   +experiments/demoSwarmFlood.m even drew the ring, but NOTHING folded a
%   beyond-R_ua return, while cogengine/planner_cem.py's DEFAULT_BOUNDS_MULTI
%   searched to 6000 m. A phantom planned at 5000 m was rendered at 5000 m,
%   measured at 5000 m and scored at 5000 m -- at 50 kHz PRF it would really
%   have appeared at 2002.1 m. Planner and judge agreed only by both being
%   wrong in the same way.
%
%   PHASE 4.1 UPDATE. The PRF has since been resolved to its self-consistent
%   8 kHz value (R_ua = 18737 m), so the specific numbers below moved: 5000 m
%   no longer folds at all. The FOLD ITSELF is still real physics and is still
%   tested here, now at a range that genuinely exceeds the corrected R_ua. The
%   PRF/window contradiction this file used to assert is now asserted in the
%   OPPOSITE direction, and its full three-way check lives in
%   tests/test_prf_consistency.m.
%
%   RESOLUTION CHOSEN: (a) clamp the planner to R_ua, with the fold
%   implemented and tested as physics (physics.apparentRange,
%   radar_params.apparent_range_m) for describing beyond-R_ua returns
%   wherever they still occur. Justification, and the cost, in
%   PHASE3_RESULTS.md C1 -- the short version is that folding a 5000 m
%   INTENT to 2002 m silently gives the planner a phantom it did not ask
%   for and the ambiguity order is unrecoverable downstream, whereas
%   clamping keeps intent and physical reality the same number.

    properties (Constant)
        PRF_HZ  = physics.Constants().PRF
        FS_HZ   = 3.2e6
        NFAST   = 400
    end

    methods (Test)

        function test_fold_is_arithmetically_right(tc)
            C = physics.Constants();
            [~, ~, Rua] = physics.apparentRange(0, tc.PRF_HZ);
            tc.verifyEqual(Rua, C.c/(2*tc.PRF_HZ), 'RelTol', 1e-12);
            fprintf('\n[C1] R_ua at %.0f kHz PRF = %.2f m\n', tc.PRF_HZ/1e3, Rua);

            % Inside R_ua: unchanged, order 0.
            [r, n] = physics.apparentRange(1800, tc.PRF_HZ);
            tc.verifyEqual(r, 1800, 'RelTol', 1e-12);
            tc.verifyEqual(n, 0);

            % 5000 m was the worked example at the OLD 50 kHz PRF, where it
            % folded to 2002.1 m. At the corrected 8 kHz it is comfortably
            % INSIDE R_ua and does not fold at all -- assert that, because it
            % is precisely what resolving the PRF bought.
            [r5, n5] = physics.apparentRange(5000, tc.PRF_HZ);
            fprintf('[C1] 5000 m -> %.1f m (order %d) -- UNFOLDED at the corrected PRF\n', r5, n5);
            tc.verifyEqual(n5, 0);
            tc.verifyEqual(r5, 5000, 'RelTol', 1e-12);

            % A range that DOES fold at 8 kHz, so the machinery stays tested.
            RFOLD = 25000;
            [rf, nf] = physics.apparentRange(RFOLD, tc.PRF_HZ);
            fprintf('[C1] %d m appears at %.1f m (ambiguity order %d)\n', RFOLD, rf, nf);
            tc.verifyEqual(nf, 1);
            tc.verifyEqual(rf, RFOLD - Rua, 'RelTol', 1e-9);
            tc.verifyEqual(rf, 6263.0, 'AbsTol', 0.1);

            % Higher orders, at the corrected R_ua.
            R3 = 3*Rua + 1234;
            [r9, n9] = physics.apparentRange(R3, tc.PRF_HZ);
            fprintf('[C1] %.0f m -> %.1f m (order %d; 3*R_ua = %.1f m)\n', R3, r9, n9, 3*Rua);
            tc.verifyEqual(n9, 3);
            tc.verifyEqual(r9, R3 - 3*Rua, 'RelTol', 1e-9);
            tc.verifyGreaterThanOrEqual(r9, 0);
            tc.verifyLessThan(r9, Rua);

            % Exhaustive: the fold must land inside [0, R_ua) everywhere.
            Rs = linspace(0, 8*Rua, 500);
            [rr, nn] = arrayfun(@(x) physics.apparentRange(x, tc.PRF_HZ), Rs);
            tc.verifyTrue(all(rr >= 0 & rr < Rua));
            tc.verifyEqual(rr, Rs - nn*Rua, 'RelTol', 1e-9);
        end

        function test_matlab_and_python_fold_identically(tc)
            tc.assumeTrue(localPythonReady(), 'cogengine not importable from pyenv');
            for R = [600 1800 2997 3000 5000 9000 12000]
                m = physics.apparentRange(R, tc.PRF_HZ);
                p = double(py.cogengine.radar_params.apparent_range_m(R, tc.PRF_HZ));
                tc.verifyEqual(p, m, 'RelTol', 1e-9, ...
                    sprintf('MATLAB and Python disagree about R=%g', R));
            end
        end

        function test_planner_no_longer_searches_past_r_ua(tc)
            % THE FIX. DEFAULT_BOUNDS_MULTI used to reach 6000 m.
            tc.assumeTrue(localPythonReady(), 'cogengine not importable from pyenv');
            bounds = py.cogengine.planner_cem.DEFAULT_BOUNDS_MULTI;
            b = bounds{'range_m'};
            hi = double(b{2});
            [~, ~, Rua] = physics.apparentRange(0, tc.PRF_HZ);
            fprintf('[C1] planner range upper bound = %.2f m (R_ua %.2f m)\n', hi, Rua);
            tc.verifyLessThanOrEqual(hi, Rua, ...
                'The planner is still searching outside the radar''s unambiguous range.');
        end

        function test_correction_pipeline_cannot_walk_past_r_ua(tc)
            % Bounds alone are not enough: _enforce_min_separation cascades
            % ranges UPWARD, so it can push a phantom past R_ua even from
            % bounds that respect it.
            tc.assumeTrue(localPythonReady(), 'cogengine not importable from pyenv');
            [~, ~, Rua] = physics.apparentRange(0, tc.PRF_HZ);
            raw = py.numpy.array([2500.0, -60.0, 15.0, 2900.0, -60.0, 15.0, 2950.0, -60.0, 15.0]);
            % py.<module>._name is a MATLAB parse error (a leading underscore
            % is not a valid MATLAB identifier), so reach it via getattr.
            mod = py.importlib.import_module('cogengine.planner_cem');
            correctFn = py.getattr(mod, '_correct_params_multi');
            out = double(correctFn(raw, int32(3), ...
                py.cogengine.radar_twin.TwinConfig(), 60.0, 200.0, tc.PRF_HZ));
            ranges = out(1:3:end);
            fprintf('[C1] 3 phantoms forced to separate: %s\n', mat2str(round(ranges,1)));
            tc.verifyLessThanOrEqual(max(ranges), Rua, ...
                'Separation cascade walked a phantom past R_ua.');
        end

        function test_planner_intent_and_judge_measurement_agree_beyond_r_ua(tc)
        % THE TEST PHASE 3's BRIEF ASKED FOR, re-pointed in Phase 4.1. Place a
        % phantom BEYOND the unambiguous range and assert the planner-intended
        % apparent range and the judge-MEASURED apparent range agree. They
        % agree because the fold is correctly applied to BOTH: the intent is
        % folded by physics.apparentRange, and the signal is rendered at that
        % folded range because that is where a real receiver would have put it.
        %
        % The requested range moved from 5000 m to 25000 m: at the corrected
        % 8 kHz PRF, 5000 m no longer folds, so it would no longer have
        % exercised the fold at all. 25000 m -> 6263 m, order 1.
            C = physics.Constants();
            REQUESTED = 25000;
            intended = physics.apparentRange(REQUESTED, tc.PRF_HZ);

            % Render the entity where the RECEIVER would see it.
            F = 8; nPulses = 32; v = -40;
            fb = tc.judgeAtRange(REQUESTED, v, F, nPulses, 4242);

            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1, ...
                'Nothing confirmed -- the comparison would be vacuous.');

            % COMPARE AT THE TRACK'S OWN TIMESTAMPS, not element-by-element.
            % A confirmed track's reconstructed history does NOT start at
            % frame 1 -- trackerGNN needs 3 hits to confirm, so the first
            % entry here is typically t = 2 s. Comparing track_range_m{1}(1)
            % against the frame-1 intent looks like a 2.7-bin range bias and
            % is really just a 2-frame time offset; measured directly, there
            % is no bias at all.
            measured = fb.track_range_m{1}(:).';
            tHit     = fb.track_time_s{1}(:).';
            intendedAtHit = arrayfun( ...
                @(t) physics.apparentRange(REQUESTED + v*t, tc.PRF_HZ), tHit);

            fprintf('\n[C1] requested TRUE range at t=0  : %.1f m\n', REQUESTED);
            fprintf('[C1] planner-INTENDED apparent    : %.1f m (order %d)\n', ...
                intended, 1);
            fprintf('[C1] track hit times [s]          : %s\n', mat2str(tHit));
            fprintf('[C1] intended apparent at those t : %s\n', mat2str(round(intendedAtHit,1)));
            fprintf('[C1] judge-MEASURED at those t    : %s\n', mat2str(round(measured,1)));
            resid = measured - intendedAtHit;
            fprintf('[C1] residual [m]                 : %s\n', mat2str(round(resid,1)));
            fprintf('[C1] max |residual| = %.1f m = %.2f range bins\n', ...
                max(abs(resid)), max(abs(resid))/C.range_per_sample);

            % Half a range bin is the best any bin-quantising radar can do.
            tc.verifyLessThanOrEqual(max(abs(resid)), C.range_per_sample/2 + 1e-6, ...
                ['Planner intent and judge measurement disagree by more than the ' ...
                 'range quantisation -- the fold is not being applied consistently.']);

            % CONTROL: a phantom whose TRUE range is already the folded value
            % must be measured identically. This is what "the fold is
            % correctly applied" means operationally -- the radar cannot tell
            % a 5000 m target from a 2002 m one, and neither can this test.
            fbCtl = tc.judgeAtRange(intended, v, F, nPulses, 4242);
            tc.verifyEqual(fbCtl.track_range_m{1}, fb.track_range_m{1}, ...
                'AbsTol', 1e-9, ...
                ['A phantom at TRUE 2002.1 m and one at TRUE 5000 m must be ' ...
                 'indistinguishable to this radar. If they differ, the fold is ' ...
                 'not being applied at the receive path.']);
            fprintf('[C1] control at TRUE %.1f m measures IDENTICALLY -- fold confirmed\n', intended);

            % And the judge reports the envelope, so no caller can quote this
            % track without knowing the radar could not have placed it at 5000 m.
            tc.verifyEqual(fb.unambiguous_range_m, C.c/(2*tc.PRF_HZ), 'RelTol', 1e-12);
            % FLIPPED IN PHASE 4.1: the 400-sample window IS consistent with
            % the corrected 8 kHz PRF. This assertion used to read verifyFalse.
            tc.verifyTrue(fb.prf_window_consistent, ...
                ['The receive window and the declared PRF disagree again. At ' ...
                 '8 kHz / 400 samples they must agree -- see test_prf_consistency.m.']);
        end

        function test_the_prf_window_contradiction_is_now_RESOLVED(tc)
        % WAS: test_the_prf_window_contradiction_is_detected_and_reported.
        %
        % Phase 3 (C1) found this project taking the range-Doppler ambiguity
        % trade both ways at once: a declared 50 kHz PRF (PRI = 64 samples)
        % used for Doppler unambiguity, alongside a 400-sample listening
        % window used for range coverage -- an 8 kHz radar's window. This test
        % asserted that contradiction EXISTED. Phase 4.1 resolved it in favour
        % of 8 kHz, so the assertions are inverted here, and the three-way
        % check that decided it lives in tests/test_prf_consistency.m.
            C = physics.Constants();
            info = physics.assertPrfWindowConsistent(C.PRF, C.fast_time_samples, 'Mode', 'silent');

            fprintf('\n[1.1] declared PRF %.0f Hz -> PRI %.0f samples -> R_ua %.0f m\n', ...
                info.prf_hz, info.pri_samples, info.unambiguous_range_m);
            fprintf('[1.1] receive window %d samples -> spans %.0f m = %.2f PRIs\n', ...
                info.fast_time_samples, info.window_span_m, info.window_pri_ratio);
            fprintf('[1.1] unambiguous velocity now %+.0f m/s (was +-375 at 50 kHz)\n', ...
                C.v_unambiguous);

            tc.verifyTrue(info.consistent, ...
                'The radar is inconsistent again -- see tests/test_prf_consistency.m.');
            tc.verifyEqual(info.pri_samples, 400, 'RelTol', 1e-12);
            tc.verifyEqual(info.window_pri_ratio, 1.0, 'RelTol', 1e-12);
            tc.verifyEqual(info.implied_prf_hz, C.PRF, 'RelTol', 1e-12, ...
                'The window-implied PRF must now EQUAL the declared PRF.');

            % The checker itself must still work in both directions, or this
            % test proves nothing: silent on the consistent radar, loud on a
            % deliberately inconsistent one (the old 50 kHz reading).
            tc.verifyWarningFree(@() physics.assertPrfWindowConsistent(C.PRF, C.fast_time_samples));
            tc.verifyWarning(@() physics.assertPrfWindowConsistent(50e3, 400), ... % PRF-LITERAL-OK
                'physics:assertPrfWindowConsistent:windowExceedsPri');
        end
    end

    methods (Access = private)
        function fb = judgeAtRange(tc, R0, v, F, nPulses, seed)
        %JUDGEATRANGE  Render one entity whose TRUE range is R0 (folded at
        %   the receive path, as physics dictates) and score it.
            C = physics.Constants();
            rs = RandStream('mt19937ar', 'Seed', seed);
            cube = complex(zeros(tc.NFAST, nPulses, F));
            for k = 1:F
                Rapp = physics.apparentRange(R0 + v*(k-1), tc.PRF_HZ);
                st = engine.entity.EntityState('range_m', Rapp, ...
                        'range_rate_mps', v, 'class', "drone");
                cube(:,:,k) = engine.entity.render(st, 'NumPulses', nPulses, ...
                    'FastTimeSamples', tc.NFAST, 'PulseWidth', 12e-6, ...
                    'Bandwidth', 2e6, 'CarrierHz', 10e9, 'PrfHz', tc.PRF_HZ, ...
                    'AmpScale', 3.0, 'RandStream', rs) ...
                    + 0.05*(randn(rs,tc.NFAST,nPulses)+1i*randn(rs,tc.NFAST,nPulses))/sqrt(2);
            end
            f = [tempname '.mat'];
            S = struct('rx_frames', cube, 'fs', C.fs, 'pulse_width_s', 12e-6, ...
                'bandwidth_hz', 2e6, 'prf_hz', tc.PRF_HZ, 'carrier_hz', 10e9, ...
                'frame_interval_s', 1.0);
            save(f, '-struct', 'S');
            cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
            fb = engine.runJudge(f);
        end
    end
end

function ok = localPythonReady()
    ok = false;
    try
        py.importlib.import_module('cogengine.planner_cem');
        ok = true;
    catch
    end
end
