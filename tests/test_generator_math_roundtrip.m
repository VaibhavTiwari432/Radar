classdef test_generator_math_roundtrip < matlab.unittest.TestCase
%TEST_GENERATOR_MATH_ROUNDTRIP  The USP, stated as a falsifiable round-trip.
%
%   THE CLAIM. The engine computes closed-form numerics -- a range
%   trajectory, the amplitude that trajectory implies, and the carrier phase
%   that trajectory implies -- and those numerics are what make a radar read
%   the resulting signal as a real target. This file tests the MATHEMATICS,
%   not the signal: it asks whether each quantity the generator DERIVES comes
%   back out of an independent measurement as the quantity it intended.
%
%   WHY THIS IS NOT CIRCULAR, WHICH IS THE ONLY REASON IT IS WORTH RUNNING.
%   The writer and the reader share no code (CLAUDE.md Rule 2, enforced by
%   test_package_separation.m and GOVERNANCE.md's one-way rule):
%
%     WRITER  generator/physics_projection.py -- amplitude_trajectory,
%             phase_progression_rad, cv_trajectory. Pure Python, closed form.
%     READER  +engine/runJudge.m -- matched filter, CA-CFAR, trackerGNN,
%             and a slow-time FFT (+radar/rangeDoppler.m) that recovers
%             range-rate from the Doppler bin. Pure MATLAB, and it has never
%             heard of the generator.
%
%   The reader does not receive range-rate or amplitude-law parameters. It
%   receives complex samples. Everything it reports about them it re-derived
%   from the waveform. So agreement is a genuine cross-validation of the
%   physics, and the tolerances below are the INSTRUMENT'S OWN resolution --
%   a range cell, a velocity bin -- not fitted numbers.
%
%   THE FOUR LAWS UNDER TEST, each with its derivation:
%     1. delay      tau = 2R/c            -> range cell c/(2*fs) = 46.84 m
%     2. Doppler    f_d = -2*Rdot/lambda  -> velocity bin lambda*PRF/(2*N)
%     3. amplitude  A ~ sqrt(sigma)/R^2   (two-way radar equation is 1/R^4 in
%                                          POWER; amplitude ~ sqrt(power))
%     4. vetoes     blind = c*PW/2, R_ua = c/(2*PRF), causality R >= R_mother
%
%   THE SIGN IN LAW 2 IS LOAD-BEARING AND HAS ALREADY BEEN WRONG ONCE.
%   phase_progression_rad's sign was originally the Blueprint's illustrative
%   convention, the OPPOSITE of runJudge's f_d = -2*Rdot/lambda, and a
%   genuine phantom scored `decoy` until Gate A caught it. A test that only
%   checked |Rdot| would have passed throughout. Both signs are therefore
%   asserted separately, and test_the_sign_convention_can_fail plants the
%   wrong sign to prove this file can detect it.

    properties (Constant)
        N_FRAMES = 24      % long lever arm: the amplitude slope needs one
        N_PULSES = 32
        R0_M     = 6000    % clear of blind range for the whole run
        V_MPS    = -50     % inside v_ua = 59.958 m/s
    end

    methods (Test)

        % ---------- law 0: the two constant sources are one source ----------

        function test_the_two_constant_tables_agree_exactly(tc)
        % Rule 1 shared physics: c, fs, PRF are FACTS, not model parameters
        % either side may choose. If these ever diverge, every round-trip
        % below is comparing two different radars and means nothing.
            C = physics.Constants();
            P = py.importlib.import_module('common.constants').C;
            names = {'c', 'fs', 'PRF', 'pulse_width', 'bandwidth', 'carrier'};
            for k = 1:numel(names)
                tc.verifyEqual(double(P.(names{k})), C.(names{k}), 'RelTol', 1e-12, ...
                    sprintf('%s differs between +physics/Constants.m and common/constants.py', ...
                            names{k}));
            end
            tc.verifyEqual(double(P.range_per_sample), C.range_per_sample, 'RelTol', 1e-12);
            tc.verifyEqual(double(P.lambda_m), C.c / C.carrier, 'RelTol', 1e-12);
        end

        % ---------- laws 1-3: the round trip, through the real judge ----------

        function test_range_and_rate_and_amplitude_all_survive_the_round_trip(tc)
            [fb, truth] = tc.roundTrip(tc.V_MPS, 3);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1, 'Nothing confirmed to measure.');
            tc.assertEqual(fb.doppler_source, 'measured', ...
                'No slow-time axis reached the judge; law 2 is untested.');

            C = physics.Constants();
            R = fb.track_range_m{1}(:);
            A = fb.track_amp{1}(:);
            D = fb.track_range_rate_mps{1}(:);
            t = fb.track_time_s{1}(:);

            % --- law 1: delay -> range, to within one range cell ---
            rTrue = interp1(truth.times_s, truth.range_m(1, :), t);
            rErr = max(abs(R - rTrue));
            cell_m = C.range_per_sample;
            fprintf('\n[USP law 1] range      max err %6.2f m   | one range cell   %6.2f m\n', ...
                rErr, cell_m);
            tc.verifyLessThan(rErr, cell_m, ...
                'Measured range is more than one range cell from the intended trajectory.');

            % --- law 2: phase -> Doppler -> range-rate, to within one bin ---
            velBin = (C.c / C.carrier) * C.PRF / (2 * tc.N_PULSES);
            rateErr = abs(mean(D) - tc.V_MPS);
            fprintf('[USP law 2] range-rate  %+7.3f m/s vs intended %+d | one bin %.3f m/s\n', ...
                mean(D), tc.V_MPS, velBin);
            tc.verifyLessThan(rateErr, velBin, ...
                'Measured range-rate is more than one velocity bin from the intended one.');
            tc.verifyEqual(sign(mean(D)), sign(tc.V_MPS), ...
                'SIGN INVERTED: the phase convention disagrees with f_d = -2*Rdot/lambda.');

            % --- law 3: A ~ sqrt(sigma)/R^2, i.e. a log-log slope of -2 ---
            slope = polyfit(log(R), log(A), 1);
            fprintf('[USP law 3] amplitude   fitted log-log slope %.4f | physical -2\n', slope(1));
            tc.verifyEqual(slope(1), -2, 'AbsTol', 0.25, ...
                ['The received amplitude does not follow the two-way radar equation. ' ...
                 'Tolerance is the fit noise at this lever arm, not a free parameter.']);
        end

        function test_the_rate_round_trip_holds_in_BOTH_directions(tc)
        % Closing and opening. A magnitude-only check would pass with the
        % phase sign inverted, which is exactly the bug that once shipped.
            C = physics.Constants();
            velBin = (C.c / C.carrier) * C.PRF / (2 * tc.N_PULSES);
            for v = [-50, 50]
                fb = tc.roundTrip(v, 3);
                tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1);
                measured = mean(fb.track_range_rate_mps{1});
                fprintf('[USP law 2] intended %+d m/s -> measured %+7.3f m/s\n', v, measured);
                tc.verifyLessThan(abs(measured - v), velBin);
                tc.verifyEqual(sign(measured), sign(v), ...
                    sprintf('A %+d m/s target was measured as %+.1f m/s.', v, measured));
            end
        end

        function test_the_sign_convention_can_fail(tc)
        % THE NEGATIVE CONTROL. Everything above is only worth reading if it
        % could have come out otherwise. Build the SAME trajectory with the
        % phase deliberately conjugated -- the wrong-sign convention that
        % shipped once -- and confirm the judge reports the OPPOSITE
        % range-rate. If this test ever passes trivially, the round trip
        % above has stopped measuring the phase at all.
        % HOW THE FLIP IS APPLIED, because the obvious way is wrong. The
        % first version of this control conjugated rx_frames, which flips
        % f_d -- and also turns the up-chirp into a down-chirp, costing the
        % matched filter 14.2 dB (see tests/test_generator_agility.m) and
        % losing the target entirely: confirmed_tracks went to 0, so there
        % was nothing left to measure. The flip has to happen BEFORE render,
        % on the PRE-RENDER plan, so only phase_progression_rad's output
        % changes and the waveform does not. That is also exactly the shape
        % of the bug that shipped.
            [jm, ~] = tc.render(tc.V_MPS, 3, 'sign_ok');
            fbGood = engine.runJudge(jm);

            pre = fullfile(tempdir, 'mathrt_sign_ok_plan.mat');
            P = load(pre);
            P.phantom_phase_rad = -P.phantom_phase_rad;    % the wrong convention
            flippedPre = fullfile(tempdir, 'mathrt_signflip_plan.mat');
            save(flippedPre, '-struct', 'P');
            flipped = fullfile(tempdir, 'mathrt_signflip_judge.mat');
            rng(3, 'twister');
            generator.render(flippedPre, flipped);
            fbBad = engine.runJudge(flipped);

            tc.assertGreaterThanOrEqual(fbGood.confirmed_tracks, 1);
            tc.assertGreaterThanOrEqual(fbBad.confirmed_tracks, 1);
            good = mean(fbGood.track_range_rate_mps{1});
            bad  = mean(fbBad.track_range_rate_mps{1});
            fprintf('[control]   correct phase %+7.3f m/s | conjugated %+7.3f m/s\n', good, bad);
            tc.verifyEqual(sign(bad), -sign(good), ...
                ['Conjugating the phase did not flip the measured range-rate. The ' ...
                 'judge is not actually reading phase, so law 2 above proves nothing.']);
        end

        % ---------- law 4: the vetoes are arithmetic, not opinion ----------

        function test_veto_thresholds_match_their_closed_forms(tc)
            C = physics.Constants();
            pp = py.importlib.import_module('generator.physics_projection');

            blind = double(pp.blind_range_m(C.pulse_width));
            rua = double(pp.unambiguous_range_m(C.PRF));
            fprintf('[USP law 4] blind range %8.2f m (c*PW/2)   | R_ua %9.2f m (c/(2*PRF))\n', ...
                blind, rua);
            tc.verifyEqual(blind, C.c * C.pulse_width / 2, 'RelTol', 1e-12, ...
                'Blind range is not c*PW/2 -- the receiver-deaf window is mis-derived.');
            tc.verifyEqual(rua, C.c / (2 * C.PRF), 'RelTol', 1e-12, ...
                'R_ua is not c/(2*PRF) -- the range-fold threshold is mis-derived.');
        end

        function test_the_vetoes_actually_refuse_and_are_not_decorative(tc)
        % Each veto is exercised from the ILLEGAL side. A constraint that
        % never fires is indistinguishable from one that is not wired.
            C = physics.Constants();
            blind = C.c * C.pulse_width / 2;
            rua = C.c / (2 * C.PRF);

            tc.verifyError(@() renderPhantomScene(blind - 100, 0, 'Tag', 'veto_eclipse'), ...
                'MATLAB:Python:PyException', 'A phantom inside the blind range was allowed.');
            tc.verifyError(@() renderPhantomScene(rua + 1000, 0, 'Tag', 'veto_ambig'), ...
                'MATLAB:Python:PyException', 'A phantom beyond R_ua was allowed.');
            % Causality: a phantom NEARER than the mother platform cannot be
            % produced by repeating a pulse the mother has not received yet.
            tc.verifyError(@() renderPhantomScene(2400, 0, 'MotherRangeM', 5000, ...
                    'Tag', 'veto_causal'), ...
                'MATLAB:Python:PyException', ...
                'A phantom closer than the jammer was allowed -- causality is not enforced.');
            fprintf('[USP law 4] eclipse, ambiguity and causality vetoes all refuse\n');
        end

        function test_amplitude_scales_as_sqrt_rcs_exactly(tc)
        % Law 3's other half, checked where it is EXACT rather than through
        % the noisy pipeline: quadrupling RCS must raise amplitude by
        % exactly 2x (+6.02 dB), because A ~ sqrt(sigma).
            pp = py.importlib.import_module('generator.physics_projection');
            r = py.numpy.array([3000.0, 3000.0]);
            a1 = double(pp.amplitude_trajectory(r, pyargs('rcs_m2', 1.0)));
            a4 = double(pp.amplitude_trajectory(r, pyargs('rcs_m2', 4.0)));
            ratio = a4(1) / a1(1);
            fprintf('[USP law 3] RCS x4 -> amplitude x%.6f (sqrt law predicts 2)\n', ratio);
            tc.verifyEqual(ratio, 2, 'RelTol', 1e-12, ...
                'Amplitude does not scale as sqrt(RCS); the radar equation is mis-applied.');
        end

    end

    methods (Access = private)

        function [jm, truth] = render(tc, v, seed, tag)
            rng(seed, 'twister');
            [jm, truth] = renderPhantomScene(tc.R0_M, v, ...
                'NumFrames', tc.N_FRAMES, 'NumPulses', tc.N_PULSES, ...
                'Tag', sprintf('mathrt_%s', tag));
        end

        function [fb, truth] = roundTrip(tc, v, seed)
            [jm, truth] = tc.render(v, seed, sprintf('v%+d', v));
            fb = engine.runJudge(jm);
        end
    end
end
