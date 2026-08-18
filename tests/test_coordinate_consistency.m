classdef test_coordinate_consistency < matlab.unittest.TestCase
%TEST_COORDINATE_CONSISTENCY  The drone's position against its signals' claims.
%
%   THE CHECK, STATED AS A PHYSICAL FACT RATHER THAN A SCREEN. A repeater
%   transmits from one aperture, so every phantom it radiates leaves that
%   aperture at the platform's own bearing and sweeps at the platform's own
%   angular rate. Each phantom nonetheless reports a range of its choosing.
%   The tangential speed that pairing implies,
%
%       v_cross(i) = R(i) * dtheta/dt,
%
%   is therefore the PLATFORM's real cross-range speed scaled by
%   R(i)/R_platform -- and with several phantoms at several ranges, their
%   implied speeds stand in exact proportion to their ranges, all produced by
%   ONE angular rate.
%
%   THAT IS THE CONSISTENCY THE RADAR CATCHES, and it is caught in
%   coordinates: no screen score, no threshold, just two measurements that
%   cannot both be true of independent objects. Real aircraft have
%   omega = v_cross/R with neither term shared, so a genuine formation
%   produces as many angular rates as it has members.
%
%   WHAT IS ASSERTED HERE AND WHAT IS NOT. This file asserts the MEASUREMENT:
%   that the radar recovers one shared angular rate, that it equals the
%   drone's real one, that the implied cross-range speeds track the range
%   ratios, and that the emitter lands where the drone actually is. It does
%   NOT assert a label -- +track/discriminator.m's verdict is a separate
%   question with its own known weaknesses, and folding the two together
%   would make a failure here impossible to attribute.
%
%   RULE 2 HOLDS THROUGHOUT: the platform's truth is returned to the test by
%   tests/renderPhantomScene.m and never written into the .mat the judge
%   reads. Every "measured" quantity below comes out of complex samples.

    properties (Constant)
        % Ranges are spaced beyond the CA-CFAR's own train+guard width
        % (34 cells = 1592.6 m) INCLUDING against the platform at 2000 m, so
        % every return owns its own training window. Closer and they merge
        % into one local max, which is the detector working correctly on a
        % scene that asked too much of it.
        RANGES   = [3600 5200 6800]
        RATE     = -50
        MOTHER_R = 2000     % outside the 1798.75 m blind range: detectable
        MOTHER_V = 3        % cross-range [m/s]
        NFRAMES  = 8
    end

    methods (Test)

        function test_every_phantom_shares_the_drones_angular_rate(tc)
            % The signature. One transmitter, one angular rate, however many
            % ranges are claimed.
            out = experiments.coordinateConsistency('Ranges', tc.RANGES, ...
                'Rate', tc.RATE, 'MotherRangeM', tc.MOTHER_R, ...
                'MotherCrossMps', tc.MOTHER_V, 'NumFrames', tc.NFRAMES, 'Seed', 21);
            w = out.omega_measured_rad_s;
            w = w(isfinite(w));
            tc.assertGreaterThanOrEqual(numel(w), 3, ...
                'need at least three tracks to say anything about a shared rate');

            % Against the drone's own true rate. The bar is the measurement's
            % own resolution: 0.0726 deg (1.27 mrad) worst-case within-track
            % azimuth scatter (tests/test_monopulse_snr_boundary.m) over an
            % 8 s dwell is ~0.16 mrad/s of slope error.
            tc.verifyEqual(mean(w), out.omega_true_rad_s, 'AbsTol', 2e-4, ...
                'the pooled angular rate is not the drone''s own');

            % ...and they agree with EACH OTHER, which is the part no
            % formation of independent aircraft reproduces.
            tc.verifyLessThan(max(w) - min(w), 5e-4, ...
                'the tracks do not share one angular rate');
        end

        function test_implied_cross_speed_scales_with_claimed_range(tc)
            % The same fact in metres per second: the further the phantom
            % claims to be, the faster it must appear to fly sideways, in
            % exact proportion. This is what makes the deception legible
            % without any reference to a threshold.
            out = experiments.coordinateConsistency('Ranges', tc.RANGES, ...
                'Rate', tc.RATE, 'MotherRangeM', tc.MOTHER_R, ...
                'MotherCrossMps', tc.MOTHER_V, 'NumFrames', tc.NFRAMES, 'Seed', 21);

            v = out.implied_cross_mps(:)';
            ratio = out.range_ratio(:)';
            ok = isfinite(v) & isfinite(ratio);
            tc.assertGreaterThanOrEqual(nnz(ok), 3);

            % Monotone in range, strictly.
            [~, order] = sort(ratio(ok));
            vs = v(ok); vs = vs(order);
            tc.verifyEqual(vs, sort(vs), 'AbsTol', 1e-9, ...
                'implied cross-range speed is not monotone in claimed range');

            % ...and quantitatively: v_implied / v_drone should equal the
            % range ratio. 15% covers the slope-fit scatter at the far end
            % without being loose enough to accept an unrelated trend.
            tc.verifyEqual(v(ok) / tc.MOTHER_V, ratio(ok), 'RelTol', 0.15, ...
                'implied speeds do not stand in proportion to the claimed ranges');

            % The nearest return is the DRONE ITSELF (its skin echo), and it
            % is the one track whose implied speed is its REAL speed. That
            % contrast is the whole comparison in one line.
            tc.verifyEqual(v(1), tc.MOTHER_V, 'AbsTol', 0.5, ...
                'the drone''s own return should imply its own true speed');
            tc.verifyGreaterThan(v(end), 3 * tc.MOTHER_V, ...
                'the farthest phantom should imply a grossly inflated speed');
        end

        function test_the_drone_is_found_where_it_actually_is(tc)
            % Closing the loop: the radar puts the emitter in coordinates and
            % it matches the platform that really flew.
            out = experiments.coordinateConsistency('Ranges', tc.RANGES, ...
                'Rate', tc.RATE, 'MotherRangeM', tc.MOTHER_R, ...
                'MotherCrossMps', tc.MOTHER_V, 'NumFrames', tc.NFRAMES, 'Seed', 21);
            C = physics.Constants();
            err = min(vecnorm(out.feedback.emitter_position_xyz_m - ...
                              out.truth.mother_position_xyz_m, 2, 1));
            tc.verifyLessThan(err, C.range_per_sample, ...
                'the backtracked emitter is more than one range cell from the drone');
        end

        function test_without_a_skin_return_the_range_is_only_bounded(tc)
            % The honest limit, asserted so it cannot quietly become a claim.
            % With no detectable platform the emitter's range is an upper
            % bound from causality, not a fix -- and the bound must contain
            % the truth.
            out = experiments.coordinateConsistency('Ranges', tc.RANGES, ...
                'Rate', tc.RATE, 'MotherRangeM', tc.MOTHER_R, ...
                'MotherCrossMps', tc.MOTHER_V, 'NumFrames', tc.NFRAMES, ...
                'Seed', 22, 'SkinReturn', false);
            tc.verifyGreaterThanOrEqual(out.feedback.emitter_range_max_m, ...
                min(out.truth.mother_range_m), ...
                'the causality bound excludes the drone that made the scene');
            % The bearing is still exact, which is the point: losing the skin
            % return costs the range, never the bearing.
            tc.verifyEqual(out.feedback.emitter_az_rad, ...
                mean(out.truth.source_azimuth_rad), 'AbsTol', 2e-3);
        end

    end
end
