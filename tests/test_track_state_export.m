classdef test_track_state_export < matlab.unittest.TestCase
%TEST_TRACK_STATE_EXPORT  What the radar RECORDS about what it received.
%
%   THE GAP THIS CLOSES. +engine/runJudge.m already MEASURES everything a
%   coordinate is made of -- range from the matched-filter delay, azimuth and
%   elevation from the monopulse difference channels, range-rate from the
%   slow-time Doppler -- but it exported them as separate scalar series and
%   never assembled them. Anyone wanting the target's actual POSITION had to
%   recompute R*sin(az) themselves, and tests/test_cartesian_measurement.m
%   does exactly that in test code. A derivation performed in a test is not a
%   measurement recorded at the radar.
%
%   So this file asks the question that phrasing hides: after the mother
%   drone's signal has been through the aperture, the matched filter, CFAR and
%   the tracker, can the radar state WHERE each phantom is, HOW FAST it is
%   going, and where the EMITTER that made them is -- from the signal alone?
%
%   NOTHING HERE IS HANDED THE ANSWER. The judge is never told the
%   trajectory, the bearing series or the mother's range; it is handed complex
%   samples. Every quantity below is re-derived from those samples and then
%   compared against what the generator actually built. Writer and reader
%   share no code (CLAUDE.md Rule 2, GOVERNANCE.md's one-way rule).
%
%   TOLERANCES ARE THE INSTRUMENT'S OWN RESOLUTION, NOT FITTED. A range cell
%   is c/(2*fs) = 46.84 m and quantisation gives it sigma = cell/sqrt(12) =
%   13.5 m; a velocity bin is lambda*PRF/(2*numPulses) = 3.747 m/s. Where a
%   least-squares slope is asserted, the tolerance is that sigma propagated
%   through the fit, stated at the assertion.
%
%   THE EMITTER FIX IS DELIBERATELY INCOMPLETE, and that is the honest
%   answer rather than a shortfall. One aperture measures the emitter's
%   BEARING exactly (Blueprint 2.4: every phantom is radiated from the one
%   platform, so they all carry its bearing) but its RANGE only as an UPPER
%   BOUND, from causality: a repeater cannot plant a phantom in front of
%   itself, so R_mother <= min(R_phantom). A point position would need a
%   second receiver. The export says bearing-only and offers the bound; it
%   does not invent a range.

    properties (Constant)
        % Phantom t=0 apparent range [m]. 3600 -> 3250, clear of the 1798.75 m
        % blind range throughout AND at least the CA-CFAR's own train+guard
        % width (1124.2 m) clear of the platform at 2000 m in EVERY frame --
        % 3600 + 7*(-50) - 2000 = 1250 m. Closer than that and the two returns
        % share a training window and collapse to one local max, which is the
        % detector working correctly on a scene that asked too much of it.
        R0       = 3600
        RDOT     = -50      % [m/s] closing, inside v_ua = 59.958
        NFRAMES  = 8
        % THE PLATFORM. 2000 m puts it OUTSIDE the blind range, which is what
        % makes a skin return physically possible at all -- see the emitter
        % tests. 3 m/s of crossing sweeps 21 m over the dwell, 0.6 deg, well
        % inside the +-2.8640 deg unambiguous sector.
        MOTHER_R = 2000
        MOTHER_V = 3
        EL_RAD   = 0.0175   % ~1 deg commanded elevation, also inside sector
    end

    methods (Test)

        function test_position_is_recorded_as_real_coordinates(tc)
            % x, y, z per hit, assembled from the SAME measurements the
            % screens read. x is dominated by range (the target is near
            % boresight) so it is checked against the true range; y is the
            % component range space structurally cannot hold.
            [fb, truth, az] = localRun(tc, 11);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1);

            P = fb.track_position_xyz_m{1};
            tc.verifySize(P, [3, numel(fb.track_range_m{1})], ...
                'position must be [3 x K], one column per hit');

            % Consistency with the series the discriminator sees: the export
            % must be an assembly of the measurements, not a second estimate.
            R = fb.track_range_m{1}(:)'; A = fb.track_azimuth_rad{1}(:)';
            tc.verifyEqual(vecnorm(P, 2, 1), R, 'RelTol', 1e-12, ...
                'the exported position does not reproduce the measured range');
            tc.verifyEqual(P(2,:), R .* sin(A), 'AbsTol', 1e-9, ...
                'cross-range is not R*sin(az) of the measured bearing');

            % ...and against the truth the generator built. One range cell:
            % the measurement IS quantised to cells, so anything tighter would
            % be asserting below the instrument's resolution. Interpolated on
            % the track's OWN hit times, so a coasted frame does not silently
            % compare frame k's measurement against frame k's truth.
            C = physics.Constants();
            tHit = fb.track_time_s{1}(:)';
            rAtHit  = interp1(truth.times_s(:)', truth.range_m(1, :), tHit);
            azAtHit = interp1(truth.times_s(:)', az(:)', tHit);
            tc.verifyEqual(P(1,:), rAtHit .* cos(azAtHit), ...
                'AbsTol', C.range_per_sample, ...
                'down-range coordinate is off by more than one range cell');
            tc.verifyEqual(P(2,:), rAtHit .* sin(azAtHit), 'AbsTol', 20, ...
                'cross-range coordinate does not track the platform geometry');
        end

        function test_velocity_is_recovered_and_agrees_with_the_doppler(tc)
            % THE LOAD-BEARING TEST. The velocity vector is fitted from the
            % POSITION series (delay + monopulse). The range-rate is measured
            % independently from the slow-time Doppler -- a different physical
            % quantity out of a different part of the signal. If the radial
            % projection of the fitted velocity matches the Doppler, the two
            % independent extractions agree and neither is an artefact of the
            % other.
            [fb, ~, ~] = localRun(tc, 12);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1);

            V = fb.track_velocity_xyz_mps{1};
            tc.verifySize(V, [3, 1]);

            % THE TOLERANCE IS THIS ESTIMATOR'S OWN RESOLUTION, and it is
            % coarse for a reason worth stating rather than padding around.
            % The range series is not noisy, it is QUANTISED: a -50 m/s target
            % moves 1.067 range cells per second, so its measured range is a
            % staircase that steps one 46.84 m cell per frame and occasionally
            % two. A straight line through a staircase can only realise slopes
            % that are whole cells over the span, so the slope error is
            % bounded by one cell divided by the fit's own time span -- NOT by
            % sigma/sqrt(sum((t-tbar)^2)), which assumes independent noise
            % this measurement does not have. Measured here: 6 cells over 5 s
            % = -56.2 m/s against a true -50.
            tHit = fb.track_time_s{1}(:);
            C = physics.Constants();
            fitTol = C.range_per_sample / (max(tHit) - min(tHit));
            tc.verifyEqual(V(1), tc.RDOT, 'AbsTol', fitTol, ...
                'down-range velocity is outside one range cell per fit span');

            % Cross-range component: strictly zero in range space, non-zero
            % here, and that is the whole point of measuring a bearing.
            P = fb.track_position_xyz_m{1};
            yFit = polyfit(fb.track_time_s{1}(:), P(2,:)', 1);
            tc.verifyEqual(V(2), yFit(1), 'AbsTol', 1e-9);
            tc.verifyGreaterThan(abs(V(2)), 2, ...
                'no cross-range velocity was recovered from the bearing sweep');

            % THE INDEPENDENCE CHECK, and the reason both exports exist.
            % The Doppler range-rate comes out of the slow-time phase; this
            % velocity comes out of the delay and the monopulse angle. Nothing
            % connects them in code, so agreement is evidence. They agree here
            % to within the coarser one's resolution -- which is the fit's,
            % not the Doppler's: the Doppler measured -48.72 against a true
            % -50 (0.35 of a 3.747 m/s velocity bin) while the position fit
            % managed -57.6. A caller wanting RADIAL speed should read
            % track_range_rate_mps; the non-redundant part of this vector is
            % the CROSS-RANGE component, which no Doppler measurement gives.
            radial = mean(fb.track_range_rate_mps{1});
            u = P(:, end) / norm(P(:, end));        % unit line-of-sight
            tc.verifyEqual(dot(V, u), radial, 'AbsTol', fitTol, ...
                ['the velocity fitted from position disagrees with the ' ...
                 'independently Doppler-measured range-rate by more than ' ...
                 'the fit''s own quantisation limit']);
        end

        function test_elevation_is_recorded_when_the_channel_exists(tc)
            % With the orthogonal baseline switched on the target stops being
            % assumed to lie in the horizontal plane.
            [fb, truth, ~] = localRun(tc, 13, 'IncludeElevationChannel', true, ...
                                       'SourceElevationRad', tc.EL_RAD);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1);
            tc.verifyEqual(fb.elevation_source, 'monopulse');

            P = fb.track_position_xyz_m{1};
            rAtHit = interp1(truth.times_s(:)', truth.range_m(1,:), ...
                             fb.track_time_s{1}(:)');
            zTrue = rAtHit * sin(tc.EL_RAD);
            % R*sigma_el at 2300 m with the estimator's own scatter is a few
            % metres; one range cell is the honest ceiling to assert against.
            C = physics.Constants();
            tc.verifyEqual(P(3,:), zTrue, 'AbsTol', C.range_per_sample, ...
                'height was not recovered from the elevation difference channel');
            tc.verifyGreaterThan(mean(P(3,:)), 20, ...
                'z is flat: the elevation channel was not actually read');
        end

        function test_without_an_elevation_channel_z_is_zero_and_says_so(tc)
            % The default. An unmeasured height must be reported as an
            % ASSUMPTION, never as a measurement of zero -- the same posture
            % as dopplerMeasured and angle_source elsewhere in this judge.
            [fb, ~, ~] = localRun(tc, 14);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1);
            tc.verifyEqual(fb.elevation_source, 'none');
            P = fb.track_position_xyz_m{1};
            tc.verifyEqual(P(3,:), zeros(1, size(P,2)), 'AbsTol', 0);
            tc.verifyTrue(all(isnan(fb.track_elevation_rad{1})), ...
                'an unmeasured elevation must be NaN, not 0');
        end

        function test_the_emitter_bearing_is_backtracked_from_the_phantom(tc)
            % Run the deception backwards. The drone never transmits its own
            % position; it transmits a phantom. But the phantom can only
            % arrive from where the drone physically is, so its measured
            % bearing IS the drone's -- and the radar recovers it without
            % being told anything.
            [fb, truth, az] = localRun(tc, 15);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 1);

            % Against the bearing series actually rendered. The 0.0726 deg
            % (1.27 mrad) worst-case within-track azimuth scatter measured in
            % tests/test_monopulse_snr_boundary.m is the bar; the mean over a
            % dwell beats it, so 2 mrad is generous rather than tuned.
            tHit = fb.track_time_s{1}(:)';
            azAtHit = interp1(truth.times_s(:)', az(:)', tHit);
            tc.verifyEqual(fb.emitter_az_rad, mean(azAtHit), 'AbsTol', 2e-3, ...
                'the emitter bearing does not match the platform actually rendered');

            % Causality gives a hard UPPER bound on its range, and the bound
            % must contain the truth. That is all one aperture gets from
            % phantoms alone -- see the next test for what closes it.
            tc.verifyTrue(isfinite(fb.emitter_range_max_m));
            tc.verifyGreaterThanOrEqual(fb.emitter_range_max_m, ...
                min(truth.mother_range_m) - physics.Constants().range_per_sample, ...
                'the causality bound excludes the platform that really made the scene');
        end

        function test_a_detectable_platform_collapses_the_bound_to_a_position(tc)
            % THE FULL BACKTRACK. A drone reflects the radar's own pulse like
            % any object. With that skin echo present the nearest co-bearing
            % return IS the platform, so the causality bound stops being a
            % bound and becomes a measured position -- range from its own
            % delay, bearing from the monopulse.
            [fb, truth, ~] = localRun(tc, 16, 'IncludePlatformSkinReturn', true, ...
                                       'PlatformRcs', 1.0);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 2, ...
                'the platform''s own skin return was not detected');
            tc.verifyEqual(fb.emitter_fix, 'nearest-cobearing');

            C = physics.Constants();
            tc.verifyEqual(fb.emitter_range_max_m, min(truth.mother_range_m), ...
                'AbsTol', C.range_per_sample, ...
                'the emitter fix is not at the platform''s true range');

            % ...and as coordinates, against the platform's true track.
            pTrue = truth.mother_position_xyz_m;      % [3 x numFrames]
            err = vecnorm(fb.emitter_position_xyz_m - pTrue, 2, 1);
            tc.verifyLessThan(min(err), C.range_per_sample, ...
                'the backtracked emitter position misses the real drone by more than one range cell');
        end

        function test_a_platform_inside_the_blind_range_cannot_be_fixed(tc)
            % The counter-tactic, and the honest limit of the backtrack. Inside
            % c*PW/2 = 1798.75 m the receiver is deaf while transmitting, so
            % the drone has no skin return to be found by -- the generator's
            % own eclipse veto refuses to render one. The radar is left with a
            % bearing and a bound, which is exactly what it should report.
            tc.verifyError(@() renderPhantomScene(tc.R0, tc.RDOT, ...
                'NumFrames', tc.NFRAMES, 'MotherRangeM', 1400, ...
                'IncludePlatformSkinReturn', true, 'Tag', 'state_blind'), ...
                'MATLAB:Python:PyException');
        end

    end
end


function [fb, truth, az] = localRun(tc, seed, varargin)
%LOCALRUN  One phantom, one MOVING platform, through the real generator and
%   the real judge.
%
%   The bearing is NOT passed in. It is derived by the builder from the one
%   MotherTrack that also supplies the causality veto's range reference, so
%   this test cannot be measuring a bearing the platform's own geometry would
%   never produce -- which is exactly what a hand-built atan2(cross*t, R)
%   series allows, and what +experiments/bearingHeadroom.m still does.
    rng(seed, 'twister');
    [m, truth] = renderPhantomScene(tc.R0, tc.RDOT, ...
        'NumFrames', tc.NFRAMES, ...
        'MotherRangeM', tc.MOTHER_R, ...
        'MotherVelocityMps', [0, tc.MOTHER_V, 0], ...
        'Tag', sprintf('state_%d', seed), varargin{:});
    fb = engine.runJudge(m);
    az = truth.source_azimuth_rad;
end
