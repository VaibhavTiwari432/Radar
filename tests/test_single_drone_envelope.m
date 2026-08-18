classdef test_single_drone_envelope < matlab.unittest.TestCase
%TEST_SINGLE_DRONE_ENVELOPE  The mission's own preconditions, locked.
%
%   THE MISSION. One drone, one aperture, one phantom. Transmit a signal the
%   radar accepts as a real target.
%
%   THIS FILE ASSERTS ONLY WHAT IS ACTUALLY SUPPORTED, which after
%   +experiments/singleDroneEnvelope.m's quantisation-phase jitter is less
%   than the first run appeared to show. Three things:
%
%     1. N >= 2 is unavailable to one drone. Not hard -- unavailable, because
%        the transmitted phase cancels in the monopulse ratio and every
%        phantom therefore lands on the drone's own bearing.
%     2. The drone must be INSIDE its own blind range. Outside it, the drone's
%        skin echo is itself a second co-bearing track, which is exactly the
%        comparison +track/emitterAttribution.m needs to name the phantom.
%     3. At close claimed range, the drone's own trajectory decides. A
%        station-keeping drone is condemned; one flying a trajectory
%        proportional to the range it is claiming is not.
%
%   WHAT IS DELIBERATELY NOT ASSERTED: any trend across claimed range. The
%   first version of the sweep showed a dramatic one and it was an artefact --
%   every seed in a cell shared one range staircase, so five seeds carried the
%   confidence of one. With sub-cell jitter the range dependence largely
%   disappears. Asserting it would lock in the artefact.

    properties (Constant)
        DRONE_R  = 1400     % inside the 1798.75 m blind range
        PHANTOM  = 2300     % the close range where the screen has signal
        RATE     = -50
        NFRAMES  = 8
    end

    methods (Test)

        function test_a_second_phantom_is_condemned_on_bearing_alone(tc)
            % Why N = 1 is the whole game. Two phantoms from one aperture are
            % two tracks on one bearing, and that is answerable without any
            % amplitude or Doppler reasoning.
            rng(4, 'twister');
            m = renderPhantomScene([2300 4400], tc.RATE, 'NumFrames', tc.NFRAMES, ...
                'MotherRangeM', tc.DRONE_R, 'MotherVelocityMps', [-30.4 3 0], ...
                'Tag', 'sd_two');
            fb = engine.runJudge(m);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 2);
            v = track.emitterAttribution(fb);
            tc.verifyGreaterThanOrEqual(nnz(v == "radiated-fake"), 1, ...
                'a second phantom from one aperture must be attributable');
            tc.verifyTrue(fb.cobearing_flagged, ...
                'the co-bearing screen did not fire on two tracks sharing a bearing');
        end

        function test_a_visible_drone_gives_the_judge_its_own_second_track(tc)
            % THE PRECONDITION, and the least obvious part of the mission. The
            % drone's skin echo is not merely a detection -- it is the second
            % co-bearing track that makes a LONE phantom attributable.
            rng(9, 'twister');
            m = renderPhantomScene(3600, tc.RATE, 'NumFrames', tc.NFRAMES, ...
                'MotherRangeM', 2000, ...                 % OUTSIDE the blind range
                'MotherVelocityMps', [0 3 0], ...
                'IncludePlatformSkinReturn', true, 'PlatformRcs', 1.0, ...
                'Tag', 'sd_visible');
            fb = engine.runJudge(m);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 2, ...
                'the drone''s own skin return was not detected');
            v = track.emitterAttribution(fb);
            tc.verifyEqual(nnz(v == "radiated-fake"), 1, ...
                ['with the drone visible, its single phantom must be named -- ' ...
                 'the drone supplies the comparison itself']);
        end

        function test_the_blind_range_is_what_removes_that_second_track(tc)
            % ...and the counter. Inside c*PW/2 the receiver is deaf while
            % transmitting, so the generator refuses to render a skin echo at
            % all -- the drone is genuinely unobservable, not merely faint.
            tc.verifyLessThan(tc.DRONE_R, physics.Constants().blind_range);
            tc.verifyError(@() renderPhantomScene(3600, tc.RATE, ...
                'NumFrames', tc.NFRAMES, 'MotherRangeM', tc.DRONE_R, ...
                'IncludePlatformSkinReturn', true, 'Tag', 'sd_blind'), ...
                'MATLAB:Python:PyException');
        end

        function test_at_close_range_the_drones_own_trajectory_decides(tc)
            % The one contrast in the sweep wide enough to mean anything: at
            % the closest claimed range, station-keeping is condemned and
            % flying is not. Run over the same jittered seed set the
            % experiment uses, so this is the measured effect and not one
            % lucky geometry.
            out = experiments.singleDroneEnvelope('PhantomRanges', tc.PHANTOM, ...
                'SpeedRatios', [0 2.5], 'PhantomRate', tc.RATE, ...
                'DroneRangeM', tc.DRONE_R, 'NumFrames', tc.NFRAMES, 'Seeds', 1:8);

            stationKeeping = out.survive(1, 1);
            flying         = out.survive(1, 2);
            tc.verifyGreaterThanOrEqual(flying - stationKeeping, 3, ...
                ['flying a trajectory matched to the claimed range must beat ' ...
                 'station-keeping by a clear margin at close range']);

            % ...and the mechanism, not just the outcome: it is screen 2c that
            % moved, which is the screen that reads bearing against range.
            tc.verifyGreaterThan(out.mean_screen_2c(1, 2), out.mean_screen_2c(1, 1), ...
                'the improvement did not come from the bearing screen');
        end

        function test_the_sweep_refuses_a_drone_it_could_see(tc)
            % The experiment must not be runnable in the configuration that
            % invalidates it -- a drone outside the blind range makes every
            % survival number in the table meaningless.
            tc.verifyError(@() experiments.singleDroneEnvelope('DroneRangeM', 2000, ...
                'Seeds', 1), 'singleDroneEnvelope:droneVisible');
        end

    end
end
