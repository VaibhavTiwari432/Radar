classdef test_bearing_rate_screen < matlab.unittest.TestCase
%TEST_BEARING_RATE_SCREEN  +track/bearingRateScreen.m, on synthetic series.
%
%   THE MATHEMATICS FIRST, THE SIGNAL LATER. This file feeds the screen
%   hand-built (azimuth, range, time) series whose provenance is exact, so a
%   failure here is a failure of the SCREEN. Whether the same separation
%   survives CFAR, the tracker and real monopulse noise is a different
%   question, asked end-to-end in test_bearing_rate_vs_judge.m -- keeping them
%   apart is what makes a red test interpretable, the same split
%   test_generator_math_roundtrip.m uses.
%
%   THE CLAIM UNDER TEST. A target in straight-line constant-velocity motion
%   conserves R^2*dtheta/dt, which makes theta an exactly linear function of
%   1/R. A phantom inherits its bearing from the mother platform (Blueprint
%   2.4) while reporting its own range, so its theta is linear in TIME
%   instead. The screen scores which model fits better.
%
%   BOTH DIRECTIONS ARE TESTED, and the negative ones matter more: a screen
%   that flags everything is worthless, and this project has already
%   withdrawn one screen (innovation whiteness) that turned out to be
%   measuring target speed rather than authenticity.

    properties (Constant)
        T       = (0:7)'        % 8 frames at 1 Hz, this project's dwell
        R0      = 2500          % phantom's claimed t=0 range [m]
        RDOT    = -35           % closing [m/s], inside v_ua
        MOTHER_R = 900          % mother platform range [m]
        MOTHER_V = 5            % mother cross-range speed [m/s]
    end

    methods (Test)

        function test_a_genuine_cv_target_scores_above_a_half(tc)
            [az, R] = localGenuine(tc);
            s = track.bearingRateScreen(az, R, tc.T);
            tc.verifyGreaterThan(s, 0.5, ...
                'a genuine CV target must not be condemned by its own kinematics');
        end

        function test_a_mother_slaved_phantom_scores_below_a_half(tc)
            [az, R] = localPhantom(tc);
            s = track.bearingRateScreen(az, R, tc.T);
            tc.verifyLessThan(s, 0.5, ...
                'a bearing-slaved phantom was not caught');
        end

        function test_the_two_are_separated_by_a_wide_margin(tc)
            % Not merely on opposite sides of 0.5 -- far enough apart that
            % measurement noise has room. The end-to-end file is what proves
            % the margin actually survives; this pins the noiseless ceiling.
            [azG, RG] = localGenuine(tc);
            [azP, RP] = localPhantom(tc);
            sG = track.bearingRateScreen(azG, RG, tc.T);
            sP = track.bearingRateScreen(azP, RP, tc.T);
            tc.verifyGreaterThan(sG - sP, 0.8, ...
                sprintf('separation too thin: genuine %.3f vs phantom %.3f', sG, sP));
        end

        function test_the_mechanism_is_the_range_ratio_not_a_speed_limit(tc)
            % The screen must NOT be an absolute cross-range speed envelope.
            % A genuine target flying FASTER across than the phantom implies
            % still has to pass, because what condemns the phantom is the
            % INCONSISTENCY between its bearing law and its range law, not
            % how fast it appears to move.
            fast = localGenuineAt(tc, tc.R0, tc.RDOT, 60);    % 60 m/s crossing
            sFast = track.bearingRateScreen(fast.az, fast.R, tc.T);
            tc.verifyGreaterThan(sFast, 0.5, ...
                'a fast but self-consistent genuine target was flagged');

            % ...while a phantom implying a much SLOWER cross speed is still
            % caught, because its inconsistency is unchanged.
            slow = localPhantomAt(tc, tc.R0, tc.RDOT, 1.0);
            [~, d] = track.bearingRateScreen(slow.az, slow.R, tc.T);
            tc.verifyLessThan(abs(d.impliedCrossSpeedMps), 10, ...
                'this case was supposed to imply a modest cross speed');
            tc.verifyLessThan(track.bearingRateScreen(slow.az, slow.R, tc.T), 0.5);
        end

        function test_a_static_bearing_is_uninformative_not_a_pass(tc)
            % Guard 1. A parked mother produces a flat bearing; both models
            % then fit noise equally and the ratio is 0.5 BY CONSTRUCTION.
            % Reporting that as a reading would be exactly the
            % "inadmissible evidence" hole the Doppler screen already had.
            R = tc.R0 + tc.RDOT * tc.T;
            az = zeros(size(tc.T)) + 1e-9 * randn(size(tc.T));
            [s, d] = track.bearingRateScreen(az, R, tc.T);
            tc.verifyTrue(isnan(s), 'a flat bearing was scored instead of skipped');
            tc.verifyNotEmpty(char(d.skipReason));
        end

        function test_a_static_range_is_uninformative_not_a_pass(tc)
            % Guard 2. With R constant, 1/R is constant, model G degenerates
            % and the comparison means nothing -- which is also the honest
            % statement that this screen cannot judge a hovering target.
            R = repmat(tc.R0, size(tc.T));
            az = linspace(0, 0.04, numel(tc.T))';
            [s, d] = track.bearingRateScreen(az, R, tc.T);
            tc.verifyTrue(isnan(s));
            tc.verifyEqual(char(d.skipReason), ...
                'range barely changed: 1/R is constant, model G degenerate');
        end

        function test_a_short_track_is_skipped(tc)
            tc.verifyTrue(isnan(track.bearingRateScreen([0;0.01;0.02], ...
                [2500;2465;2430], [0;1;2])));
        end

        function test_the_documented_evasion_really_does_defeat_it(tc)
            % Stated in the screen's own header, asserted here so it cannot
            % be quietly forgotten: if the mother flies a trajectory
            % PROPORTIONAL to the phantom's claimed range (R_p/R_m constant),
            % then R_p^2*dtheta/dt is constant too and the two models
            % coincide. The screen does not make deception impossible; it
            % makes it expensive, by coupling the adversary's own flight path
            % to the range it wants the phantom to claim.
            ratio = tc.R0 / tc.MOTHER_R;
            Rm = (tc.R0 + tc.RDOT * tc.T) / ratio;     % mother, same shape
            h  = Rm(1)^2 * (tc.MOTHER_V / Rm(1));
            azM = cumtrapz(tc.T, h ./ Rm.^2);          % mother's own bearing
            Rp = tc.R0 + tc.RDOT * tc.T;
            s = track.bearingRateScreen(azM, Rp, tc.T);
            tc.verifyGreaterThan(s, 0.5, ...
                'the documented evasion no longer works -- re-read the header');
        end

    end
end


% ---- series builders. Closed form, so the test's own physics is auditable --

function [az, R] = localGenuine(tc)
    g = localGenuineAt(tc, tc.R0, tc.RDOT, tc.MOTHER_V * tc.R0 / tc.MOTHER_R);
    az = g.az; R = g.R;
end

function g = localGenuineAt(tc, R0, Rdot, crossSpeed0)
% A real CV target: theta0 + (h/Rdot)*(1/R0 - 1/R(t)), h = R0^2*dtheta0/dt.
    R = R0 + Rdot * tc.T;
    h = R0^2 * (crossSpeed0 / R0);          % = R0 * crossSpeed0
    g.az = (h / Rdot) * (1 ./ R0 - 1 ./ R);
    g.R = R;
end

function [az, R] = localPhantom(tc)
    p = localPhantomAt(tc, tc.R0, tc.RDOT, tc.MOTHER_V);
    az = p.az; R = p.R;
end

function p = localPhantomAt(tc, R0, Rdot, motherCrossSpeed)
% A phantom: its RANGE is its own, its BEARING is the mother's. The mother
% holds station in range here, so its bearing rate is constant and the
% phantom's azimuth is linear in TIME.
    p.R = R0 + Rdot * tc.T;
    p.az = (motherCrossSpeed / tc.MOTHER_R) * tc.T;
end
