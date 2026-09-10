classdef test_range_rate_consistency < matlab.unittest.TestCase
%TEST_RANGE_RATE_CONSISTENCY  Tier 1.2 -- the explicit RGPO/VGPO magnitude
%   detector, and the hole in the existing sign-only screen that motivates it.

    methods (Test)

        function test_sign_screen_is_blind_to_a_magnitude_mismatch(tc)
            % THE MOTIVATING HOLE, asserted so it cannot be argued about.
            % A repeater walking range at -50 m/s while transmitting only
            % -5 m/s of Doppler passes discriminator screen 2 outright,
            % because that screen compares SIGNS.
            C = physics.Constants();
            t = (0:7)';
            R = 1800 - 50*t;
            D = -5 * ones(size(t));           % magnitude wildly wrong, sign right
            A = 3.0 * (1800 ./ R).^2;         % amplitude law kept correct, so
                                              % screen 1 cannot carry the verdict
            lbl = track.discriminator(struct('range', R, 'amplitude', A, ...
                        'doppler', D, 'dopplerMeasured', true), C);
            fprintf('\n[1.2] sign-only screen on a 10x Doppler mismatch -> "%s"\n', lbl);
            tc.verifyEqual(char(lbl), 'real', ...
                'if this now says decoy, screen 2 has gained a magnitude test');

            out = track.rangeRateConsistency(R, t, D, C);
            fprintf(['[1.2] magnitude check   : range-derived %+.2f m/s, doppler %+.2f m/s, ' ...
                     'mismatch %.2f m/s, threshold %.2f m/s -> pass %d\n'], ...
                out.rangeDerivedMps, out.dopplerMps, out.mismatchMps, ...
                out.thresholdMps, out.pass);
            tc.verifyFalse(out.pass, 'the magnitude check must catch what the sign check misses');
        end

        function test_consistent_track_passes(tc)
            C = physics.Constants();
            t = (0:7)';
            R = round((1800 - 50*t) / C.range_per_sample) * C.range_per_sample;
            D = -50 * ones(size(t));
            out = track.rangeRateConsistency(R, t, D, C);
            fprintf('[1.2] consistent CV     : mismatch %.3f m/s vs threshold %.2f m/s -> pass %d\n', ...
                out.mismatchMps, out.thresholdMps, out.pass);
            tc.verifyTrue(out.pass);
            tc.verifyTrue(out.informative);
        end

        function test_threshold_is_derived_and_range_dominated(tc)
            % Rule 1: the tolerance must come from the two quantisers, not
            % from what separates the arms. Check both terms explicitly and
            % check which one dominates -- the brief assumed Doppler.
            C = physics.Constants();
            T = 7; nP = 32;
            lambda = C.c / 10e9;
            sigmaR = C.range_per_sample / (sqrt(6) * T);
            sigmaD = (lambda * (C.PRF/nP) / 2) / sqrt(12);
            expected = 3 * sqrt(sigmaR^2 + sigmaD^2);

            t = (0:7)'; R = 1800 - 50*t; D = -50*ones(size(t));
            out = track.rangeRateConsistency(R, t, D, C);
            fprintf('[1.2] threshold         : sigmaR %.3f m/s, sigmaD %.3f m/s -> %.3f m/s (range/doppler = %.2fx)\n', ...
                sigmaR, sigmaD, out.thresholdMps, sigmaR/sigmaD);
            tc.verifyEqual(out.thresholdMps, expected, 'RelTol', 1e-9);
            tc.verifyGreaterThan(sigmaR, sigmaD, ...
                'the RANGE term should dominate -- if not, the doc comment is wrong');
        end

        function test_tightens_as_the_track_lengthens(tc)
            C = physics.Constants();
            short = track.rangeRateConsistency((1800-50*(0:3))', (0:3)', -50*ones(4,1), C);
            long  = track.rangeRateConsistency((1800-50*(0:15))', (0:15)', -50*ones(16,1), C);
            fprintf('[1.2] lever arm        : threshold %.2f m/s (4 hits) -> %.2f m/s (16 hits)\n', ...
                short.thresholdMps, long.thresholdMps);
            tc.verifyLessThan(long.thresholdMps, short.thresholdMps);
        end

        % ---- screen 2d: the same detector, now wired into the verdict ----
        % Added 21 Aug 2026. Everything above tests the FUNCTION; these test
        % its integration as a discriminator veto, which is a separate claim:
        % a detector that measures correctly and is never consulted changes no
        % label. This file opens by asserting the hole exists, so it is the
        % right place to assert it closes.

        function test_the_new_screen_closes_the_hole_this_file_opens_with(tc)
            [ts, C] = localMismatchTrack();
            ts.screensEnabled = {'amplitude', 'doppler', 'micro', 'rangerate'};
            lbl = track.discriminator(ts, C);
            tc.verifyEqual(lbl, "decoy", ...
                'screen 2d did not catch a 10x range-rate magnitude mismatch');
        end

        function test_the_screen_is_off_by_default(tc)
            % Every screen postdating the published numbers is opt-in, or a
            % result measured last month silently changes meaning this month.
            [ts, C] = localMismatchTrack();
            tc.verifyEqual(track.discriminator(ts, C), "real", ...
                'the default screen set has changed; published labels have moved');
        end

        function test_the_veto_cannot_be_diluted(tc)
            % THE REASON IT IS A VETO. This track passes screens 1 and 2 (the
            % amplitude law is exact and the Doppler sign is right), so as a
            % VOTE a failing 2d would score mean([1 1 0]) = 0.67 -> `real` and
            % the catch would be thrown away -- the same arithmetic that
            % discarded screen 2c's measured 0.968-vs-0.068 separation
            % (DECEPTION_MAP_RESULTS.md section 6).
            [ts, C] = localMismatchTrack();
            ts.screensEnabled = {'amplitude', 'doppler'};
            tc.verifyEqual(track.discriminator(ts, C), "real", ...
                'precondition: the other screens must PASS this track');
            ts.screensEnabled = {'amplitude', 'doppler', 'rangerate'};
            tc.verifyEqual(track.discriminator(ts, C), "decoy");
        end

        function test_a_genuine_track_is_not_condemned(tc)
            % The negative control. A screen that flags everything is
            % worthless, and this project has already withdrawn one screen
            % that turned out to measure target speed rather than authenticity.
            C = physics.Constants();
            t = (0:7)';
            R = 1800 - 50*t;
            ts = struct('range', R, 'amplitude', 3.0*(1800./R).^2, ...
                        'doppler', -50*ones(size(t)), 'dopplerMeasured', true, ...
                        'time', t, 'carrierHz', 10e9, 'prfHz', C.PRF, ...
                        'numPulses', 32, ...
                        'screensEnabled', {{'amplitude', 'doppler', 'rangerate'}});
            tc.verifyEqual(track.discriminator(ts, C), "real", ...
                'screen 2d condemned a track whose range and Doppler agree');
        end

        function test_veto_requires_a_MEASURED_doppler(tc)
            % "Absent vs missing evidence": on the legacy 2-D export the
            % Doppler series is an all-zero placeholder, and vetoing a track
            % for disagreeing with a number nobody measured is the error this
            % project already had to remove from screen 2 once.
            [ts, C] = localMismatchTrack();
            ts.dopplerMeasured = false;
            ts.screensEnabled = {'amplitude', 'doppler', 'rangerate'};
            tc.verifyEqual(track.discriminator(ts, C), "real", ...
                'screen 2d fired on a Doppler that was never measured');
        end

        function test_stationary_consistent_track_is_not_accused(tc)
            % Range flat AND Doppler flat is a physically possible object
            % (a hover). Accusing it here would duplicate -- and contradict --
            % discriminator.m's "missing vs absent evidence" reasoning.
            C = physics.Constants();
            t = (0:7)';
            out = track.rangeRateConsistency(1800*ones(8,1), t, zeros(8,1), C);
            tc.verifyFalse(out.informative);
            tc.verifyTrue(out.pass);
        end
    end
end

% ======================= file-local helpers ===========================

function [ts, C] = localMismatchTrack()
%LOCALMISMATCHTRACK  The track this file opens with: range walking at
%   -50 m/s while the Doppler says -5 m/s. Signs agree, so screen 2 passes;
%   the amplitude law is exact, so screen 1 passes. Only a MAGNITUDE test can
%   catch it. Built once here so every screen-2d case below argues about the
%   same track rather than five slightly different ones.
    C = physics.Constants();
    t = (0:7)';
    R = 1800 - 50*t;
    ts = struct('range', R, 'amplitude', 3.0*(1800./R).^2, ...
                'doppler', -5*ones(size(t)), 'dopplerMeasured', true, ...
                'time', t, 'carrierHz', 10e9, 'prfHz', C.PRF, 'numPulses', 32);
end
