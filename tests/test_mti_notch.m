classdef test_mti_notch < matlab.unittest.TestCase
%TEST_MTI_NOTCH  The clutter filter every real radar has, and both its edges.
%
%   +physics/surfaceClutter.m gave this project ground return for the first
%   time. A radar with clutter and no clutter FILTER is not a radar anyone
%   ships, so any result measured on one is provisional. This is the filter:
%   runJudge discards the Doppler bins around zero radial velocity before
%   taking its max, which is what a pulse-Doppler radar does with its
%   zero-Doppler filter output.
%
%   IT CUTS BOTH WAYS, and that is the finding rather than a caveat:
%
%     RESTORES A MOVING TARGET. Uniform clutter raises the CA-CFAR threshold
%     everywhere, because the training cells are clutter-dominated. Notching
%     zero Doppler drops those cells back to the thermal floor, so a phantom
%     that was masked becomes detectable again. Measured below: a 0.1 m^2
%     phantom goes 0 tracks -> 1 track.
%
%     REMOVES A SLOW ONE. The same filter cannot tell a tangentially-flying
%     drone from the ground, because neither has radial velocity. Measured
%     below: the drone is detected at 1.0 m^2 with the notch off and NEVER
%     with it on, at any RCS, with or without clutter.
%
%   WHAT THAT MEANS FOR THIS PROJECT. Both mechanisms hide the emitter and
%   neither hides its phantom. The drone's counter-tactic is therefore not to
%   hide inside the blind range -- an earlier, thermal-noise-only conclusion of
%   this project's -- but simply to FLY TANGENTIALLY, which puts it in the
%   notch of any MTI radar at any range and any RCS.
%
%   DEFAULT IS OFF (MtiNotchMps = 0), so no published number moves.

    properties (Constant)
        DRONE_R   = 2000        % outside the 1798.75 m blind range
        PHANTOM_R = 3600
        RATE      = -50         % clear of the notch by 13 Doppler bins
        GAMMA_DB  = -15
    end

    methods (Test)

        function test_the_notch_width_is_a_speed_and_one_bin_is_derivable(tc)
            % Expressed in m/s because a notch is a statement about what the
            % radar refuses to believe is moving. The bin it corresponds to is
            % arithmetic: lambda*PRF/(2*numPulses).
            C = physics.Constants();
            vbin = C.lambda * C.PRF / (2 * 32);
            tc.verifyEqual(vbin, 3.75, 'AbsTol', 0.01, ...
                'the velocity bin should be 3.75 m/s at this operating point');
        end

        function test_the_default_is_off_and_changes_nothing(tc)
            % Any published number would move if this ran by default.
            m = localScene(tc, [], 1.0);
            a = engine.runJudge(m);
            b = engine.runJudge(m, 'MtiNotchMps', 0);
            tc.verifyEqual(b.confirmed_tracks, a.confirmed_tracks);
            tc.verifyEqual(b.track_range_m, a.track_range_m);
        end

        function test_mti_restores_a_phantom_that_clutter_had_masked(tc)
            % THE POSITIVE EDGE. Clutter lifts the CFAR threshold everywhere;
            % notching zero Doppler drops it back and the moving phantom
            % reappears.
            m = localScene(tc, tc.GAMMA_DB, 0.1);
            noMti = engine.runJudge(m);
            withMti = engine.runJudge(m, 'MtiNotchMps', 3.75);
            tc.verifyEqual(noMti.confirmed_tracks, 0, ...
                'a 0.1 m^2 phantom should be masked by clutter without MTI');
            tc.verifyGreaterThanOrEqual(withMti.confirmed_tracks, 1, ...
                'MTI should recover a moving phantom from uniform clutter');
            tc.verifyEqual(withMti.track_label{1}, 'real', ...
                'the recovered phantom should still read as a genuine target');
        end

        function test_mti_removes_a_tangential_drone_at_any_rcs(tc)
            % THE NEGATIVE EDGE, and the more consequential one. A drone
            % crossing at 3 m/s has essentially no radial rate, so the filter
            % that rejects the ground rejects it too -- even at a
            % fighter-sized 1 m^2, and even with no clutter present at all.
            C = physics.Constants();
            for rcs = [1.0 0.1]
                for gamma = {[], tc.GAMMA_DB}
                    m = localSceneWithDrone(tc, gamma{1}, rcs);
                    fb = engine.runJudge(m, 'MtiNotchMps', 3.75);
                    rr = cellfun(@(r) mean(r), fb.track_range_m);
                    found = any(abs(rr - tc.DRONE_R) < 2 * C.range_per_sample);
                    tc.verifyFalse(found, sprintf(...
                        ['the drone should be invisible to an MTI radar ' ...
                         '(rcs %.2f, clutter %d)'], rcs, ~isempty(gamma{1})));
                end
            end
        end

        function test_but_the_drone_IS_visible_without_the_notch(tc)
            % The control that stops the test above passing vacuously: with
            % the notch off and no clutter, the same drone is found. So its
            % disappearance is the filter, not the scene.
            C = physics.Constants();
            m = localSceneWithDrone(tc, [], 1.0);
            fb = engine.runJudge(m);
            rr = cellfun(@(r) mean(r), fb.track_range_m);
            tc.verifyTrue(any(abs(rr - tc.DRONE_R) < 2 * C.range_per_sample), ...
                'the drone should be detectable with no clutter and no notch');
        end

        function test_the_moving_phantom_survives_the_notch(tc)
            % The adversary pays nothing. At -50 m/s the phantom is thirteen
            % bins clear of a one-bin notch.
            m = localScene(tc, tc.GAMMA_DB, 1.0);
            fb = engine.runJudge(m, 'MtiNotchMps', 3.75);
            tc.verifyGreaterThanOrEqual(fb.confirmed_tracks, 1);
            tc.verifyEqual(fb.track_label{1}, 'real');
        end

    end
end


function m = localScene(tc, gammaDB, rcs)
    rng(17, 'twister');
    args = {tc.PHANTOM_R, tc.RATE, 'NumFrames', 8, 'Rcs', rcs, ...
            'MotherRangeM', 1400, 'MotherVelocityMps', [0 3 0], ...
            'IncludeAngleChannel', false, ...
            'Tag', sprintf('mtin_%d_%d', round(rcs*100), isempty(gammaDB))};
    if ~isempty(gammaDB); args = [args, {'ClutterGammaDB', gammaDB}]; end
    m = renderPhantomScene(args{:});
end


function m = localSceneWithDrone(tc, gammaDB, rcs)
    rng(9, 'twister');
    args = {tc.PHANTOM_R, tc.RATE, 'NumFrames', 8, ...
            'MotherRangeM', tc.DRONE_R, 'MotherVelocityMps', [0 3 0], ...
            'IncludePlatformSkinReturn', true, 'PlatformRcs', rcs, ...
            'IncludeAngleChannel', false, ...
            'Tag', sprintf('mtid_%d_%d', round(rcs*100), isempty(gammaDB))};
    if ~isempty(gammaDB); args = [args, {'ClutterGammaDB', gammaDB}]; end
    m = renderPhantomScene(args{:});
end
