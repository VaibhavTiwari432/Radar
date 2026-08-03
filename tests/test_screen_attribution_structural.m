classdef test_screen_attribution_structural < matlab.unittest.TestCase
%TEST_SCREEN_ATTRIBUTION_STRUCTURAL  Standing assertions for
%   experiments.screenAttribution -- which ECCM screen actually rejects the
%   structural CV-coherent generator.
%
%   ONE RUN, SEVERAL ASSERTIONS, ON PURPOSE. Every row of the attribution
%   table is re-scored from the SAME judged episodes (only the screen mask
%   moves), so running the experiment once per assertion would not add
%   independence -- it would just re-roll the noise and cost six times the
%   runtime. nEp is small here (the headline table is the 100-episode run,
%   results/screen_attribution.log); this file guards the ORDERING and the
%   two structural facts, which are stable at this sample size.
%
%   THE RE-SCORING IS VERIFIED INSIDE THE EXPERIMENT, not here:
%   screenAttribution asserts, episode by episode, that its re-scored
%   baseline label equals engine.runJudge's own eccm_label. If that ever
%   drifts, this test errors rather than quietly attributing loss with a
%   discriminator that is no longer the judge's.

    properties (Constant)
        NEP = 20;
        SEED = 7;
    end

    properties
        out
    end

    methods (TestClassSetup)
        function runOnce(tc)
            tc.out = experiments.screenAttribution(tc.NEP, tc.SEED, 1);  % Swerling I
        end
    end

    methods (Test)

        function test_amplitude_slope_is_the_dominant_screen(tc)
            % THE FINDING, as a falsifiable assertion. Removing the
            % log(A)-vs-log(R) slope screen must recover far more of the
            % generator's real-rate than removing the Doppler sign screen.
            % If this ever fails, the attribution has changed and the
            % report's "the amplitude screen is what rejects it" language
            % must be revisited.
            amp = tc.lossOf('no amplitude');
            dop = tc.lossOf('no doppler');
            fprintf('\n[attr] loss recovered: -amplitude %+.1f pp | -doppler %+.1f pp\n', amp, dop);
            tc.verifyGreaterThan(amp, dop + 15, ...
                ['the amplitude slope screen is no longer the dominant ' ...
                 'rejector -- re-run the 100-episode table before quoting it']);
        end

        function test_disabling_every_screen_does_not_give_a_free_pass(tc)
            % NOT a tautology, and NOT the brief's assumed 100% upper bound.
            % track/discriminator.m scores an all-uninformative track 0.5 and
            % the verdict is score > 0.5, so "no evidence" leans SUSPICIOUS
            % by design. The real ceiling on this arm is the CONFIRMATION
            % rate, not an all-screens-off rate.
            none = tc.rateOf('no screens at all');
            base = tc.rateOf('all (baseline)');
            ceil_ = tc.rateOf('confirmed at all (ceiling)');
            fprintf('[attr] none %.1f%% | baseline %.1f%% | confirmed ceiling %.1f%%\n', ...
                100*none, 100*base, 100*ceil_);
            tc.verifyLessThanOrEqual(none, base, ...
                'disabling every screen RAISED the real rate -- the 0.5 tie-break has changed');
            tc.verifyGreaterThanOrEqual(ceil_, base, ...
                'more episodes were labelled real than were confirmed at all');
        end

        function test_monopulse_is_reported_inapplicable_not_measured(tc)
            % The brief asks for a monopulse ablation. This arm cannot supply
            % one: runJudge's co-bearing screen needs >= 2 confirmed tracks
            % and buildEnvEntity keeps the sum channel only. Asserted so the
            % experiment can never start reporting a monopulse number it did
            % not measure.
            tc.verifySubstring(tc.out.monopulse, 'inapplicable');
        end
    end

    methods (Access = private)
        function v = lossOf(tc, name)
            v = tc.rowOf(name).lossPp;
        end
        function v = rateOf(tc, name)
            v = tc.rowOf(name).real;
        end
        function r = rowOf(tc, name)
            i = find(strcmp({tc.out.rows.name}, name), 1);
            tc.assertNotEmpty(i, sprintf('no attribution row named "%s"', name));
            r = tc.out.rows(i);
        end
    end
end
