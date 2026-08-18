classdef test_emitter_attribution < matlab.unittest.TestCase
%TEST_EMITTER_ATTRIBUTION  Which positions are real, which were radiated, and
%   which fakes the radar could not identify.
%
%   THE RULE UNDER TEST (+track/emitterAttribution.m). A repeater transmits
%   from one aperture, so every phantom it radiates sweeps at that platform's
%   angular rate while claiming a range of its own. Tracks at different ranges
%   sharing one angular rate were therefore radiated from one place, and
%   causality (R_phantom >= R_emitter) makes only the NEAREST of them a
%   possible source. Independent aircraft cannot produce a shared rate:
%   omega = v_cross/R and neither term is shared.
%
%   BOTH DIRECTIONS ARE TESTED, and the negative ones carry more weight. A
%   rule that names everything fake is worthless, and this project has already
%   withdrawn one screen (innovation whiteness) that turned out to measure
%   target speed rather than authenticity.
%
%   THE FAILURE IS ASSERTED, NOT OMITTED. With the drone hidden inside the
%   blind range it has no skin return, so the nearest PHANTOM becomes the
%   nearest member of the shared-rate group and is returned "source-or-real" --
%   correctly, since the real emitter is invisible and causality cannot
%   exclude it. That is a fake the radar did not identify, and the last test
%   here pins it so it can neither vanish nor grow silently.
%
%   The scenario is not chosen here: generator/engagement.py owns it and
%   validates it against every bound the radar imposes before anything is
%   rendered.

    properties (Constant)
        SEED = 21
    end

    methods (Test)

        function test_the_standard_engagement_names_every_phantom(tc)
            out = experiments.standardEngagementMap('Seed', tc.SEED);
            v = out.verdict;

            tc.assertEqual(double(out.feedback.confirmed_tracks), 4, ...
                'expected the drone plus three phantoms');
            % Nearest is the drone's own skin echo: this test cannot condemn
            % it and must not pretend to.
            tc.verifyEqual(v(1), "source-or-real");
            % Every other track was radiated by it.
            tc.verifyEqual(nnz(v == "radiated-fake"), 3, ...
                'not every phantom was identified as radiated');
            tc.verifyEqual(out.n_missed, 0, ...
                'a phantom escaped identification on the standard engagement');
        end

        function test_the_verdicts_are_backed_by_a_shared_angular_rate(tc)
            % The mechanism, not just the outcome. One group, one rate, and
            % implied cross speeds in proportion to the claimed ranges.
            out = experiments.standardEngagementMap('Seed', tc.SEED);
            d = out.diag;

            tc.verifyEqual(numel(unique([d.group])), 1, ...
                'the tracks were not attributed to a single emitter');

            w = [d.omega_rad_s];
            tc.verifyTrue(all(isfinite(w)));
            tc.verifyLessThan(max(w) - min(w), 5e-4, ...
                'the angular rates are not actually shared');

            % Implied cross speed rises with claimed range, strictly. This is
            % the deception made legible: the further a phantom claims to be,
            % the faster it must appear to fly sideways.
            R = [d.mean_range_m]; V = [d.implied_cross_speed_mps];
            [~, ord] = sort(R);
            tc.verifyEqual(V(ord), sort(V(ord)), 'AbsTol', 1e-9, ...
                'implied cross speed is not monotone in claimed range');
            tc.verifyGreaterThan(V(ord(end)) / V(ord(1)), 3, ...
                'the farthest phantom should imply a grossly inflated speed');
        end

        function test_the_drone_is_mapped_where_it_actually_is(tc)
            out = experiments.standardEngagementMap('Seed', tc.SEED);
            C = physics.Constants();
            err = min(vecnorm(out.feedback.emitter_position_xyz_m - ...
                              out.truth.mother_position_xyz_m, 2, 1));
            tc.verifyLessThan(err, C.range_per_sample, ...
                'the mapped emitter is more than one range cell from the drone');
        end

        function test_a_hidden_drone_costs_the_radar_one_unidentified_fake(tc)
            % THE HONEST FAILURE. Inside c*PW/2 = 1798.75 m the receiver is
            % deaf while transmitting, so the drone has no skin return. The
            % nearest phantom then takes its place as the only causally
            % possible source and is NOT named fake.
            out = experiments.standardEngagementMap('Engagement', 'hidden-drone', ...
                                                     'Seed', tc.SEED);
            tc.verifyEqual(out.n_phantoms_true, 3);
            tc.verifyEqual(out.n_missed, 1, ...
                ['exactly one phantom should escape when the drone is hidden: ' ...
                 'the nearest, which causality cannot exclude as the source']);
            tc.verifyEqual(nnz(out.verdict == "source-or-real"), 1);

            % The radar is not blind here, it is BOUNDED: the bearing is still
            % exact and the range is still a valid causality bound. Losing the
            % skin return costs the fix, never the bearing.
            tc.verifyEqual(out.feedback.emitter_az_rad, ...
                mean(out.truth.source_azimuth_rad), 'AbsTol', 3e-3);
            tc.verifyGreaterThanOrEqual(out.feedback.emitter_range_max_m, ...
                min(out.truth.mother_range_m), ...
                'the causality bound excludes the drone that made the scene');
        end

        function test_a_lone_genuine_target_is_not_accused(tc)
            % The false-positive control, and the reason it matters: with one
            % track there is no second rate to compare against, so the rule
            % falls back to screen 2c. A genuine closing target whose bearing
            % curves with its own range must NOT come back "radiated-fake".
            R0 = 2300; rate = -50; nF = 8;
            t = (0:nF-1);
            % theta linear in 1/R: what straight-line constant-velocity motion
            % forces, since R^2*dtheta/dt is conserved. Built from the target's
            % OWN geometry, not from a platform's.
            Rt = R0 + rate * t;
            az = 0.02 * (1/R0 - 1./Rt) * R0;      % small, inside the sector
            rng(31, 'twister');
            m = renderPhantomScene(R0, rate, 'NumFrames', nF, ...
                'SourceAzimuthRad', az, 'MotherRangeM', 900, 'Tag', 'attr_gen');
            fb = engine.runJudge(m);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1);
            v = track.emitterAttribution(fb);
            tc.verifyNotEqual(v(1), "radiated-fake", ...
                'a genuine constant-velocity target was accused of being radiated');
        end

        function test_no_confirmed_tracks_yields_no_verdicts(tc)
            % Degenerate input must return empty rather than erroring: a
            % caller sweeping seeds will hit a no-detection frame eventually.
            fb = struct('confirmed_tracks', 0);
            [v, d] = track.emitterAttribution(fb);
            tc.verifyEmpty(v);
            tc.verifyEmpty(d);
        end

    end
end
