classdef test_track_count_matches_ground_truth < matlab.unittest.TestCase
%TEST_TRACK_COUNT_MATCHES_GROUND_TRUTH  Task 2 (PHASE2_COMPLETION_POA.md):
%   confirmed_tracks must be trustworthy STANDALONE -- matching the true
%   phantom count exactly, not just "no label is wrong" (test_four_phantom_
%   swarm.m's earlier de-dup-by-range workaround) and not just "close
%   enough" (test_four_phantom_swarm_seeds.m's rate-over-noise-seeds
%   statistic, which legitimately varies run to run because CFAR's own
%   Pfa means real rendered scenes occasionally throw a genuine false
%   alarm -- see below).
%
%   Root cause found and fixed in +engine/runJudge.m (not here): detections
%   there were built with MeasurementNoise=eye(3) (claims ~1 m std) while
%   the REAL range-bin quantization error is ~C.range_per_sample (~47 m
%   std) -- a ~47x overconfidence that made trackerGNN's gates falsely
%   tight, so tracks born in the same frame (identical, uninformative birth
%   covariance) occasionally missed their own next detection and spawned a
%   duplicate TrackID for the same physical target. Fixed by matching
%   MeasurementNoise to the true bin resolution.
%
%   This test uses a FROZEN, previously-observed real quantized CFAR peak
%   sequence (the actual localMaxPeaks output from rendering this project's
%   canonical 4-phantom swarm scene, ranges 1800/3000/4200/5400 m,
%   v=-60 m/s, power-equalized -- tests/test_four_phantom_swarm.m), fed
%   DIRECTLY to track.runTracker with the SAME (now-fixed) MeasurementNoise
%   convention +engine/runJudge.m uses. Deterministic -- no RNG, no CFAR,
%   no rendering -- so this assertion is not allowed to be flaky.
%
%   Known, separate, NOT-a-bug residual (documented, not hidden): the full
%   noisy rendered pipeline (test_four_phantom_swarm_seeds.m) still shows
%   an extra confirmed track in roughly 1/8 seeds, traced directly to a
%   genuine CFAR false alarm (Pfa=1e-4 means SOME false-alarm rate is
%   correct behavior, not a defect -- Stage3_Test.m's own
%   test_noise_only_rarely_confirms already documents "almost never", not
%   "never"). That is a property of CFAR + noise, not something this
%   ground-truth-known test tries to reproduce or suppress.

    methods (Test)

        function test_four_simultaneous_phantoms_confirm_exactly_four(tc)
            C = physics.Constants();
            times = (0:7) * 1.0;
            % Frozen real localMaxPeaks output, tests/test_four_phantom_swarm.m's
            % canonical scene, seed 40002 (captured during Task 2's root-cause
            % investigation) -- 4 physical phantoms, well-separated throughout.
            peaksByFrame = { ...
                [1780.0 2997.9 4215.8 5386.9], ...
                [1733.2 2951.1 4122.1 5340.1], ...
                [1686.3 2857.4 4075.3 5293.2], ...
                [1639.5 2810.6 4028.5 5199.5], ...
                [1545.8 2763.7 3981.6 5152.7], ...
                [1499.0 2716.9 3887.9 5105.8], ...
                [1452.1 2623.2 3841.1 5059.0], ...
                [1358.4 2576.3 3794.2 4965.3] };

            measNoise = diag([C.range_per_sample^2, 1, 1]);  % matches +engine/runJudge.m
            dets = cell(1, 8);
            for k = 1:8
                R = peaksByFrame{k};
                detArr = objectDetection.empty;
                for j = 1:numel(R)
                    detArr(j) = objectDetection(times(k), [R(j); 0; 0], ...
                                    'MeasurementNoise', measNoise); %#ok<AGROW>
                end
                dets{k} = detArr;
            end

            confirmed = track.runTracker(dets, times, C);

            fprintf('ground-truth regression: %d confirmed (want exactly 4): IDs=%s\n', ...
                numel(confirmed), mat2str([confirmed.TrackID]));

            tc.verifyEqual(numel(confirmed), 4, ...
                'confirmed_tracks must match the true phantom count exactly on this frozen, noise-free-of-quantization-jitter-only scenario.');
            tc.verifyEqual(numel(unique([confirmed.TrackID])), 4, ...
                'No duplicate TrackIDs for the same physical phantom.');
        end

    end

end
