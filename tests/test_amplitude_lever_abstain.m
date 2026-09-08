classdef test_amplitude_lever_abstain < matlab.unittest.TestCase
%TEST_AMPLITUDE_LEVER_ABSTAIN  Screen 1 must know when it could not look.
%
%   Guards the two abstain conditions added to +track/discriminator.m on
%   8 September 2026. Before them the screen fitted a log(A)-vs-log(R) slope
%   whenever the range varied by more than 1e-9 m -- one nanometre -- and
%   committed to a verdict on it. Over a short lever arm that fit is noise, so
%   the screen CONDEMNED targets whose amplitude was 1/R^2 by construction
%   while reporting full confidence.
%
%   MEASURED evidence that this was real, not theoretical
%   (STAGE_F_PHASE0p5_RESULTS.md 3.5): on a bench-configuration walk, screen 1
%   returned `decoy` for the honest phantom AND for a constant-amplitude decoy,
%   at both walk directions -- it separated nothing, while its near-zero score
%   still dragged the composite mean.
%
%   THE TEST THAT MATTERS MOST HERE IS test_flat_amplitude_short_lever_is_still
%   _caught. An abstain removes a screen from the average, and +track/
%   discriminator.m's own "MISSING vs ABSENT" doctrine records that letting a
%   target suppress evidence rewards declining to produce it. The dead-flat
%   branch is what stops that: a decoy that sits still cannot buy an abstain,
%   because sitting still with a flat amplitude is itself the giveaway. If that
%   test ever fails, the guards have opened the hole the doctrine warns about.

    properties
        C
        Cell3          % 3 range cells, the Guard A threshold
    end

    methods (TestClassSetup)
        function setup(tc)
            tc.C = physics.Constants();
            tc.Cell3 = 3 * tc.C.range_per_sample;
        end
    end

    methods (Access = private)
        function [label, conf, d] = screen1(tc, R, A)
            % Screen 1 alone, so nothing else can mask what it did.
            ts = struct('range', R, 'amplitude', A, ...
                        'doppler', -ones(size(R)), 'dopplerMeasured', true, ...
                        'screensEnabled', {{'amplitude'}});
            [label, conf, d] = track.discriminator(ts, tc.C);
        end
    end

    methods (Test)

        function test_honest_long_lever_still_scores_real(tc)
            % The screen must not have become useless: a genuine 1/R^2 return
            % over a real lever arm still scores, and still scores REAL.
            R = linspace(2000, 3000, 12);
            [label, ~, d] = tc.screen1(R, (2000 ./ R) .^ 2);
            tc.verifyEqual(label, "real");
            tc.verifyEqual(d.numScores, 1, 'screen 1 must have scored');
            tc.verifyEqual(d.amplitudeSkipReason, "");
        end

        function test_constant_amplitude_long_lever_still_caught(tc)
            % The decoy this screen exists for. Unchanged behaviour.
            R = linspace(2000, 3000, 12);
            [label, conf, d] = tc.screen1(R, ones(1, 12));
            tc.verifyEqual(label, "decoy");
            tc.verifyEqual(d.numScores, 1, 'screen 1 must have scored');
            tc.verifyGreaterThan(conf, 0.9, 'a flat slope is an unambiguous catch');
        end

        function test_honest_short_lever_abstains_instead_of_condemning(tc)
            % THE BUG. Half a Guard-A threshold of range change, amplitude
            % exactly 1/R^2. The screen must decline, not condemn.
            R = linspace(2000, 2000 + 0.5 * tc.Cell3, 12);
            [~, conf, d] = tc.screen1(R, (2000 ./ R) .^ 2);
            tc.verifyEqual(d.numScores, 0, 'screen 1 should have abstained');
            tc.verifyEqual(conf, 0, 'an abstain must carry no confidence');
            tc.verifySubstring(char(d.amplitudeSkipReason), 'range cells');
        end

        function test_flat_amplitude_short_lever_is_still_caught(tc)
            % THE ANTI-EXPLOIT GUARD -- see the class header. A decoy must not
            % be able to buy an abstain by refusing to move: range flat AND
            % amplitude flat is the absence of natural scintillation, and that
            % still scores 0 rather than abstaining.
            R = linspace(2000, 2000 + 0.5 * tc.Cell3, 12);
            [label, ~, d] = tc.screen1(R, ones(1, 12));
            tc.verifyEqual(d.numScores, 1, ...
                'a dead-flat decoy must NOT be allowed to abstain');
            tc.verifyEqual(label, "decoy");
        end

        function test_unestimable_slope_abstains(tc)
            % Guard B. A long lever arm but amplitude scatter big enough that
            % the slope's standard error covers the screen's whole scoring
            % band. Verified against the standard error, not against the seed:
            % the assertion is that whatever it returned, it declined.
            rng(7);
            R = linspace(2000, 4000, 12);
            A = (2000 ./ R) .^ 2 .* exp(2.0 * randn(1, 12));
            [~, conf, d] = tc.screen1(R, A);
            tc.verifyEqual(d.numScores, 0, 'an unestimable slope must abstain');
            tc.verifyEqual(conf, 0);
            tc.verifySubstring(char(d.amplitudeSkipReason), 'standard error');
        end

        function test_two_point_track_abstains(tc)
            % A line through two points has zero residual and therefore no
            % estimable error -- it is not evidence, however clean it looks.
            [~, ~, d] = tc.screen1([2000 3000], [1 0.44]);
            tc.verifyEqual(d.numScores, 0);
        end

        function test_guard_scales_with_the_signals_own_range_cell(tc)
            % The guard is "3 range cells", and a cell is c/(2*fs) of the
            % SIGNAL being judged. +engine/runJudge.m now supplies that as
            % .rangeResolutionM. A span that clears 3 cells at this project's
            % 3.2 MHz (140.5 m) does NOT clear them at the 1 MHz bench
            % (449.7 m), and the guard has to notice.
            benchCellM = 149.8962290;                 % c/(2*1e6)
            R = linspace(2000, 2000 + 200, 12);        % 200 m span
            A = (2000 ./ R) .^ 2;

            % Default cell size (this project's radar): 200 m > 140.5 m, scores.
            ts = struct('range', R, 'amplitude', A, 'doppler', -ones(1, 12), ...
                        'dopplerMeasured', true, 'screensEnabled', {{'amplitude'}});
            [~, ~, dSim] = track.discriminator(ts, tc.C);
            tc.verifyEqual(dSim.numScores, 1, ...
                '200 m clears 3 cells at 3.2 MHz and must be scored');

            % Same track declared as a 1 MHz signal: 200 m < 449.7 m, abstains.
            ts.rangeResolutionM = benchCellM;
            [~, ~, dBench] = track.discriminator(ts, tc.C);
            tc.verifyEqual(dBench.numScores, 0, ...
                '200 m is under 3 cells at 1 MHz and must abstain');
            tc.verifySubstring(char(dBench.amplitudeSkipReason), '449.7');
        end

        function test_two_output_call_is_unchanged(tc)
            % Every existing caller uses [label, confidence]. Adding a third
            % output must not disturb them.
            R = linspace(2000, 3000, 12);
            ts = struct('range', R, 'amplitude', (2000 ./ R) .^ 2, ...
                        'doppler', -ones(1, 12), 'dopplerMeasured', true);
            [label, conf] = track.discriminator(ts, tc.C);
            tc.verifyClass(label, 'string');
            tc.verifyGreaterThanOrEqual(conf, 0);
            tc.verifyLessThanOrEqual(conf, 1);
        end

    end
end
