classdef test_multi_aperture_render < matlab.unittest.TestCase
%TEST_MULTI_APERTURE_RENDER  Phase 0 gate for the multi-drone-swarm research.
%
%   +generator/render.m's PhantomAzimuthRad lets each phantom radiate from its
%   OWN bearing, so the monopulse difference channel carries each echo at its
%   own angle -- the one engine change needed to break the co-bearing
%   assumption F7 rests on. Three guards:
%
%   1. ABSENT-PATH BYTE-IDENTITY. With one phantom, PhantomAzimuthRad=[az]
%      must give a bit-identical rx_frames_delta to the historical shared
%      SourceAzimuthRad=az (one phantom => no summation-order difference), so
%      no existing single-aperture result moves. The renderer draws its noise
%      from the global RNG, so each render is preceded by the same rng seed;
%      renderPhantomScene itself draws nothing (only generator.render does).
%   2. EQUAL-BEARING REDUCTION. With N phantoms all at the SAME bearing, the
%      per-phantom path matches the shared path to floating-point tolerance
%      (summation order differs, so not bit-exact -- physically identical).
%   3. TWO-BEARING ROUND TRIP. Two phantoms at two DISTINCT bearings, through
%      the real judge's monopulse, must be MEASURED at those two bearings --
%      proof the difference channel now encodes per-phantom angle.

    methods (Static, Access = private)
        function jm = render(ranges, azShared, azPhantom, noiseAmp, seedTag)
            rng(4242, 'twister');       % identical noise draws across paired renders
            args = {'MotherRangeM', 900, 'NumFrames', 8, 'NumPulses', 32, ...
                    'SourceAzimuthRad', azShared, 'NoiseAmplitude', noiseAmp, ...
                    'Tag', seedTag};
            if ~isempty(azPhantom)
                args = [args, {'PhantomAzimuthRad', azPhantom}];
            end
            jm = renderPhantomScene(ranges, -35.0, args{:});
        end
    end

    methods (Test)
        function test_single_phantom_absent_path_is_byte_identical(tc)
            az = deg2rad(1.2);
            shared = tc.render(2600, az, [],  1e-9, 'ma_single_shared');
            perph  = tc.render(2600, az, az,  1e-9, 'ma_single_perph');
            a = load(shared, 'rx_frames_delta'); b = load(perph, 'rx_frames_delta');
            tc.verifyEqual(b.rx_frames_delta, a.rx_frames_delta);   % bit-exact
        end

        function test_equal_bearing_reduces_to_the_shared_path(tc)
            az = deg2rad(0.8);
            shared = tc.render([2600, 3800], az, [],        1e-9, 'ma_equal_shared');
            perph  = tc.render([2600, 3800], az, [az; az],  1e-9, 'ma_equal_perph');
            a = load(shared, 'rx_frames_delta'); b = load(perph, 'rx_frames_delta');
            tc.verifyLessThan(max(abs(a.rx_frames_delta(:) - b.rx_frames_delta(:))), 1e-9);
        end

        function test_two_distinct_bearings_are_measured_apart(tc)
            az1 = deg2rad(-1.5); az2 = deg2rad(1.5);
            jm = tc.render([2600, 3800], 0.0, [az1; az2], 1e-9, 'ma_twobearing');
            fb = engine.runJudge(jm);
            tc.assertGreaterThanOrEqual(fb.confirmed_tracks, 2, ...
                'both phantoms must confirm for the bearing check to mean anything');
            az = sort(fb.track_azimuth_mean(:));
            tc.verifyEqual(az(1), az1, 'AbsTol', deg2rad(0.05));
            tc.verifyEqual(az(end), az2, 'AbsTol', deg2rad(0.05));
            % Genuinely resolved apart, not collapsed co-bearing.
            tc.verifyGreaterThan(az(end) - az(1), deg2rad(2.5));
        end
    end
end
