classdef test_multi_target_judge < matlab.unittest.TestCase
%TEST_MULTI_TARGET_JUDGE  Proves +engine/runJudge.m's multi-target rewrite
%   before trusting it on a real rendered multi-phantom scene.
%
%   Until this revision, engine.runJudge kept only the single strongest CFAR
%   peak per frame, so a scene with several phantoms could never be judged
%   as anything but 0 or 1 confirmed track -- see runJudge.m's header. Two
%   properties matter here, both checked:
%     1. Several SIMULTANEOUS, well-separated real targets each confirm as
%        their OWN track (trackerGNN itself was always multi-target; only
%        its caller wasn't feeding it more than one detection/frame).
%     2. Two simultaneous phantoms with DIFFERENT true signatures (one
%        kinematically/amplitude-consistent "real" mover, one naive static
%        "decoy") are discriminated INDEPENDENTLY and correctly -- proving
%        the per-track range/amplitude history reconstruction (nearest-
%        range match to each track's own filtered state) isn't smearing
%        the two tracks' histories together.

    methods (Test)

        function test_multiple_simultaneous_real_targets_confirm_as_separate_tracks(tc)
            % Two well-separated, independently-consistent detection trains
            % in the SAME frames (cf. Stage3_Test's single-target version).
            C = physics.Constants(); %#ok<NASGU>
            F = 8; times = (0:F-1) * 1.0;
            dets = cell(1, F);
            for k = 1:F
                d1 = objectDetection(times(k), [1200 + 5*k; 0; 0], 'MeasurementNoise', eye(3));
                d2 = objectDetection(times(k), [3600 - 8*k; 0; 0], 'MeasurementNoise', eye(3));
                dets{k} = [d1, d2];
            end
            [confirmed, history] = track.runTracker(dets, times, physics.Constants());
            tc.verifyEqual(numel(confirmed), 2, ...
                'Exactly two well-separated consistent targets should confirm -- no more, no less.');
            tc.verifyEqual(numel(unique([confirmed.TrackID])), numel(confirmed), ...
                'Confirmed tracks must have distinct TrackIDs.');
            tc.verifyEqual(numel(history), F);
        end

        function test_runJudge_confirms_and_discriminates_two_simultaneous_phantoms(tc)
            % A physically-closing "real-like" phantom (range decreasing,
            % amplitude following the 1/R^2 law -- Stage5_Test's own
            % test_passes_real_target recipe) SUMMED with a static,
            % constant-amplitude, zero-Doppler "naive decoy" phantom
            % (Stage5_Test's test_flags_naive_decoy recipe), both via
            % synth.synthesizeSwarm (Rule 2: +synth never grades itself),
            % run through the real independent judge end to end.
            C = physics.Constants();
            rng(2024);

            wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
                    'PulseWidth', 12e-6, 'PRF', physics.Constants().PRF, 'SweepBandwidth', 2e6);
            pulse = wav();
            bufferLen = 400;
            xTemplate = [pulse; zeros(bufferLen - numel(pulse), 1)];

            F = 8;
            % vClose=60 m/frame at this project's established 1 Hz revisit
            % cadence (+track/runTracker.m's "60-120 m/s closing" comment;
            % same convention as the project's canonical R=1800m scene) --
            % NOT a small jitter: the discriminator only has something to
            % say about range-rate/amplitude-slope if the target's motion
            % actually crosses range bins (46.84 m/sample); an earlier
            % 5 m/frame draft moved less than one bin over 8 frames, looked
            % perfectly static to the quantized range estimate, and (per
            % track.discriminator's own documented default) got scored
            % "decoy" by having NOTHING informative to say, not by actually
            % looking fake.
            R0_real = 1800; vClose = 40;     % m/frame, closing
            R_decoy = 3600;                  % static
            gain0 = 3;

            rxFrames = complex(zeros(bufferLen, F));
            for k = 1:F
                R_real_k = R0_real - vClose * (k - 1);
                gainReal = gain0 * (R0_real / R_real_k)^2;   % 1/R^2 amplitude law
                actionReal = struct('delay_s', 2 * R_real_k / C.c, 'phase_rad', 0, 'gain', gainReal);
                actionDecoy = struct('delay_s', 2 * R_decoy / C.c, 'phase_rad', 0, 'gain', gain0);

                yReal  = synth.synthesizeSwarm(xTemplate, actionReal, C);
                yDecoy = synth.synthesizeSwarm(xTemplate, actionDecoy, C);
                noise = 0.05 * (randn(bufferLen,1) + 1i*randn(bufferLen,1)) / sqrt(2);
                rxFrames(:, k) = yReal + yDecoy + noise;
            end

            here = fileparts(mfilename('fullpath'));
            tmpMat = fullfile(here, '_tmp_multi_target_judge.mat');
            cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>

            S = struct('rx_frames', rxFrames, 'fs', C.fs, 'pulse_width_s', 12e-6, ...
                        'bandwidth_hz', 2e6, 'prf_hz', physics.Constants().PRF, 'cfar_pfa', 1e-4, ...
                        'cfar_num_training', 20, 'cfar_num_guard', 4, 'frame_interval_s', 1.0);
            save(tmpMat, '-struct', 'S');

            feedback = engine.runJudge(tmpMat);

            fprintf(['multi-target judge: confirmed_tracks=%d surviving=%d flagged=%d ' ...
                'labels=%s\n'], feedback.confirmed_tracks, feedback.false_tracks_surviving, ...
                feedback.flagged_decoys, strjoin(string(feedback.track_label), ','));

            tc.verifyGreaterThanOrEqual(feedback.confirmed_tracks, 2, ...
                'Both the real mover and the naive decoy should confirm as tracks.');
            tc.verifyGreaterThanOrEqual(feedback.false_tracks_surviving, 1, ...
                'The physically-consistent closing phantom should be labeled real.');
            tc.verifyGreaterThanOrEqual(feedback.flagged_decoys, 1, ...
                'The naive static/constant-amplitude phantom should be flagged as a decoy.');
        end

    end

end

% ===================== file-local helpers =============================
function tf = localDeleteIfExists(f) %#ok<DEFNU>
    tf = isfile(f);
    if tf; delete(f); end
end
