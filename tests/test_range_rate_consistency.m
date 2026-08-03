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
