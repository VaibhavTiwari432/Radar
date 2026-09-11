classdef test_skin_backtrack < matlab.unittest.TestCase
%TEST_SKIN_BACKTRACK  +track/skinBacktrack.m on synthetic judge exports (no render).
%
%   Four guards, each the smallest case that fails if the pair test breaks:
%   1. a far track carrying the near track's bearing series is backtracked to it
%   2. a far track at its own bearing (0.5 deg off) is not
%   3. causality: the NEAR member is never backtracked to the far one
%   4. bearings that CROSS mid-dwell (zero-mean difference, real trend) are not
%      a pair -- the case a mean-only test would wrongly accept
%   5. a track failing runJudge's NIS test (stitched from two objects) is
%      never used as an emitter

    properties (Constant)
        T = 0:7                         % 8 frames at 1 s
        SIG = deg2rad(0.05)             % per-hit azimuth noise
    end

    methods (Access = private)
        function fb = scene(tc, azNear, azFar)
            rng(7, 'twister');
            fb.confirmed_tracks = 2;
            fb.track_time_s = {tc.T, tc.T};
            fb.track_range_m = {2000 - 10*tc.T, 6000 - 35*tc.T};
            fb.track_azimuth_rad = {azNear + tc.SIG*randn(1,8), ...
                                    azFar  + tc.SIG*randn(1,8)};
        end
    end

    methods (Test)
        function test_shared_bearing_series_is_backtracked(tc)
            az = deg2rad(0.4) + deg2rad(0.1) * tc.T;          % the drone sweeps
            [v, d] = track.skinBacktrack(tc.scene(az, az));
            tc.verifyEqual(v, ["emitter", "backtracked"]);
            tc.verifyEqual(d(2).partner, 1);
        end

        function test_own_bearing_is_not_paired(tc)
            az = deg2rad(0.4) + deg2rad(0.1) * tc.T;
            v = track.skinBacktrack(tc.scene(az, az + deg2rad(0.5)));
            tc.verifyEqual(v, ["unpaired", "unpaired"]);
        end

        function test_near_track_is_never_the_backtracked_one(tc)
            az = deg2rad(-0.7) * ones(1, 8);
            fb = tc.scene(az, az);
            fb.track_range_m = fliplr(fb.track_range_m);      % track 1 is now FAR
            v = track.skinBacktrack(fb);
            tc.verifyEqual(v, ["backtracked", "emitter"]);
        end

        function test_an_incoherent_track_cannot_be_an_emitter(tc)
            % A track stitched from two objects alternates between their
            % bearings; its huge scatter would make it pair with anything.
            % runJudge's NIS column marks it, and the counter must refuse it.
            azF = deg2rad(-0.6) * ones(1, 8);
            fb = tc.scene(deg2rad(repmat([0.2 -0.6], 1, 4)), azF);
            fb.track_nis_pass = [false, true];
            v = track.skinBacktrack(fb);
            tc.verifyEqual(v, ["undetermined", "unpaired"]);
        end

        function test_crossing_bearings_are_not_a_pair(tc)
            azN = deg2rad(0.3) * ones(1, 8);
            azF = azN + deg2rad(linspace(-0.3, 0.3, 8));      % mean diff 0, trend real
            v = track.skinBacktrack(tc.scene(azN, azF));
            tc.verifyEqual(v, ["unpaired", "unpaired"]);
        end
    end
end
