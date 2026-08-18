classdef test_phase_controllability < matlab.unittest.TestCase
%TEST_PHASE_CONTROLLABILITY  What a transmitted phase can and cannot move.
%
%   THE CLAIM. Of the three phases in this system, the adversary owns two and
%   the radar owns one:
%
%     FAST-TIME  (within a pulse)      -> range        adversary-owned
%     SLOW-TIME  (pulse to pulse)      -> range-rate   adversary-owned
%     SPATIAL    (across subapertures) -> azimuth      NOT IN THE SIGNAL
%
%   The third is not a harder version of the first two. It is not carried by
%   the transmitted waveform at all -- it is manufactured at the receiver by
%   the path-length difference between two subapertures. +generator/render.m
%   builds Delta as Sigma times ONE common scalar, so in the ratio the radar
%   actually measures, every amplitude, phase and delay the adversary chose
%   cancels identically.
%
%   WHY "IDENTICALLY" NEEDS A TEST AND NOT AN ARGUMENT. The algebra is one
%   line, but a measured azimuth does still wobble when the adversary changes
%   its signal -- because a different range trajectory lands in a different
%   range bin, and the two channels carry independent noise. Those look like
%   weak control if you only read the numbers. The test that separates them is
%   to SCALE THE NOISE: receiver noise shrinks with the noise floor, control
%   does not. That is the falsifiable form of the claim and it is what
%   test_the_residual_is_noise_and_scales_like_noise asserts.

    methods (Test)

        function test_no_transmitted_phase_reaches_the_angle_channel(tc)
            % Three phantoms at three ranges, three amplitudes, three phase
            % trajectories. If ANY of them influenced the angle measurement,
            % Delta/Sigma would vary across the samples that carry them.
            out = experiments.phaseControllability();

            tc.verifyLessThan(out.ratio_spread, 1e-8, ...
                'Delta/Sigma is not one constant: some transmitted term survived');
            tc.verifyLessThan(out.az_error_rad, 1e-12, ...
                'the recovered azimuth is not the source''s own geometry');
        end

        function test_the_adversary_owns_range_and_range_rate(tc)
            % The positive half. A rule that says "the adversary controls
            % nothing" would be just as wrong as one that says it controls
            % everything.
            out = experiments.phaseControllability();
            r = out.rows;

            % Fast-time delay moves range, and nothing else meaningfully.
            tc.verifyGreaterThan(abs(r(2).range - r(1).range), 1000, ...
                'the delay knob did not move the measured range');
            tc.verifyEqual(r(2).rate, r(1).rate, 'AbsTol', 4, ...
                'changing range should not have changed range-rate');

            % Slow-time phase moves range-rate, in the commanded direction.
            tc.verifyLessThan(r(3).rate, -30, 'closing phase did not read as closing');
            tc.verifyGreaterThan(r(4).rate, 10, 'opening phase did not read as opening');
        end

        function test_but_it_owns_none_of_the_azimuth(tc)
            % The negative half, stated as a ratio so it cannot be satisfied
            % by simply making everything small. Six settings spanning both
            % adversary-owned phases and the amplitude move the measured
            % bearing far less than physically moving the drone does.
            out = experiments.phaseControllability();
            tc.verifyGreaterThan(out.az_spread_geometry_rad, ...
                                 10 * out.az_spread_signal_rad, ...
                ['the signal knobs moved the bearing comparably to moving the ' ...
                 'transmitter, which would contradict the cancellation']);
        end

        function test_the_residual_is_noise_and_scales_like_noise(tc)
            % THE LOAD-BEARING TEST. Same range trajectory, carrier phase
            % negated, so ONLY phase differs -- swept against the noise floor.
            % Receiver noise shrinks with the floor; control would not.
            out = experiments.phaseControllability();
            n = out.noise_amps(:); d = out.az_diff_vs_noise(:);
            tc.assertTrue(all(isfinite(d)), 'a sweep point failed to confirm a track');

            % Linear in the noise amplitude: the ratio of successive
            % differences must track the ratio of successive noise amplitudes.
            % 25% covers the draw-to-draw variation without admitting a
            % constant (control) or a quadratic term.
            for i = 2:numel(n)
                tc.verifyEqual(d(i-1)/d(i), n(i-1)/n(i), 'RelTol', 0.25, ...
                    'the phase-induced azimuth difference does not scale with noise');
            end

            % ...and it must genuinely collapse, not merely trend.
            tc.verifyLessThan(d(end) / d(1), 5e-3, ...
                'a floor remained as noise fell, which would indicate real control');
        end

        function test_the_reachable_set_is_a_ray(tc)
            % The summary the whole file exists to support: one degree of
            % freedom out of three.
            out = experiments.phaseControllability();
            C = physics.Constants();
            tc.verifyEqual(out.reachable_range_m(2), C.R_unambiguous, 'RelTol', 1e-12);
            tc.verifyGreaterThanOrEqual(out.reachable_range_m(1), C.blind_range * 0 + 2000, ...
                'the causality floor must be at least the emitter''s own range');
            % Azimuth is a single value, not an interval. Asserted as scalar
            % rather than as a width, because a width of zero could also mean
            % the sweep simply was not run.
            tc.verifySize(out.reachable_az_rad, [1 1]);
        end

    end
end
