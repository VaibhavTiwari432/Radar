classdef test_second_baseline < matlab.unittest.TestCase
%TEST_SECOND_BASELINE  The radar's swarm counter: a second, wider monopulse
%   baseline the coarse one disambiguates.
%
%   +generator/render.m writes rx_frames_delta2 (subaperture 0.90 m); the judge
%   uses the coarse 0.30 m baseline to pick which fringe of the fine one a target
%   sits in, then the fine phase for precision. Two guards:
%     1. ACCURACY -- the two-baseline azimuth is unbiased at a known bearing
%        inside the coarse sector.
%     2. PRECISION -- on identical scenes (same seed), the two-baseline azimuth
%        error scatters LESS than the coarse baseline alone. The finer angle is
%        the whole point: it sharpens the angular-rate estimate emitter
%        attribution needs.

    methods (Static, Access = private)
        function azMean = measure(azTrue, useBaseline2, seed)
            rng(seed, 'twister');
            jm = renderPhantomScene(3000, -35.0, 'NumFrames', 8, 'NumPulses', 32, ...
                'SourceAzimuthRad', azTrue, 'IncludeSecondBaseline', useBaseline2, ...
                'NoiseAmplitude', 0.05, 'Tag', sprintf('sb_%d_%d', useBaseline2, seed));
            fb = engine.runJudge(jm);
            if fb.confirmed_tracks < 1
                azMean = NaN;
            else
                azMean = fb.track_azimuth_mean(1);
            end
        end
    end

    methods (Test)
        function test_two_baseline_azimuth_is_accurate(tc)
            azTrue = deg2rad(1.2);
            errs = arrayfun(@(s) tc.measure(azTrue, true, s) - azTrue, 1:8);
            errs = errs(~isnan(errs));
            tc.assertNotEmpty(errs);
            tc.verifyLessThan(abs(mean(errs)), deg2rad(0.05));   % unbiased
        end

        function test_two_baseline_beats_coarse_precision(tc)
            azTrue = deg2rad(1.2);
            seeds = 1:12;
            eC = arrayfun(@(s) tc.measure(azTrue, false, s) - azTrue, seeds);
            e2 = arrayfun(@(s) tc.measure(azTrue, true,  s) - azTrue, seeds);
            eC = eC(~isnan(eC)); e2 = e2(~isnan(e2));
            tc.verifyLessThan(std(e2), std(eC), ...
                'the wider baseline must scatter less than the coarse one');
        end
    end
end
