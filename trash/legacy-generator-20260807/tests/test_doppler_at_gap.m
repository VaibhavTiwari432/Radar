classdef test_doppler_at_gap < matlab.unittest.TestCase
%TEST_DOPPLER_AT_GAP  Task 4 (PHASE2_COMPLETION_POA.md): the "Doppler-at-gap"
%   diagnostic patch. +engine/runJudge.m used to compute each confirmed
%   track's Doppler/range-rate as diff(rSeq)/S.frame_interval_s, where rSeq
%   is the range at each DETECTED frame -- silently assuming consecutive
%   entries are exactly one frame_interval_s apart. A track that missed a
%   detection in the middle (its own CFAR peak didn't beat threshold that
%   one frame -- not rare with intercept_noise_amplitude=2.0) has
%   consecutive rSeq entries 2+ frame_interval_s apart in real time, so the
%   old formula overstated the range-rate by the gap factor right at the
%   frames most likely to need an honest Doppler estimate (a track that
%   survived a miss, not a clean one).
%
%   Fixed: diff(rSeq)./diff(tSeq), using each track's own recorded hit
%   times (feedback.track_time_s, added this session specifically so this
%   is externally verifiable, not just trusted).
%
%   SUPERSEDED, PARTLY -- read before citing this as the current behaviour.
%   The Virtual Entity Engine build removed diff(range) as the source of
%   Doppler entirely: on the pulse-cube path +engine/runJudge.m now MEASURES
%   range-rate from slow-time Doppler processing, which has no dependence on
%   the elapsed time between detected frames at all, so the gap bug it
%   describes cannot arise there. What this test still verifies, and what is
%   still true and still worth guarding, is that feedback.track_time_s
%   records the REAL per-hit times so a gap is visible to any caller -- the
%   arithmetic below is the test's own, not runJudge's. See runJudge.m's
%   "DOPPLER IS NOW MEASURED" header block.

    methods (Test)

        function test_gap_uses_actual_elapsed_time_not_frame_interval(tc)
            C = physics.Constants();
            rng(777);
            wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
                    'PulseWidth', 12e-6, 'PRF', physics.Constants().PRF, 'SweepBandwidth', 2e6);
            pulse = wav();
            bufferLen = 400;
            xTemplate = [pulse; zeros(bufferLen - numel(pulse), 1)];

            F = 8; frameIntervalS = 1.0;
            R0 = 1800; vClose = 40; gain0 = 3;

            rxFrames = complex(zeros(bufferLen, F));
            missedFrame = 5;   % deliberately kill the signal at this one frame
            for k = 1:F
                noise = 0.05 * (randn(bufferLen,1) + 1i*randn(bufferLen,1)) / sqrt(2);
                if k == missedFrame
                    rxFrames(:, k) = noise;   % noise only -- no phantom this frame
                    continue;
                end
                Rk = R0 - vClose * (k - 1);
                gain = gain0 * (R0 / Rk)^2;
                action = struct('delay_s', 2*Rk/C.c, 'phase_rad', 0, 'gain', gain);
                y = synth.synthesizeSwarm(xTemplate, action, C);
                rxFrames(:, k) = y + noise;
            end

            here = fileparts(mfilename('fullpath'));
            tmpMat = fullfile(here, '_tmp_doppler_gap.mat');
            cleanupObj = onCleanup(@() localDeleteIfExists(tmpMat)); %#ok<NASGU>
            S = struct('rx_frames', rxFrames, 'fs', C.fs, 'pulse_width_s', 12e-6, ...
                        'bandwidth_hz', 2e6, 'prf_hz', physics.Constants().PRF, 'cfar_pfa', 1e-4, ...
                        'cfar_num_training', 20, 'cfar_num_guard', 4, ...
                        'frame_interval_s', frameIntervalS);
            save(tmpMat, '-struct', 'S');

            feedback = engine.runJudge(tmpMat);
            tc.assumeGreaterThanOrEqual(feedback.confirmed_tracks, 1, ...
                'Target should still confirm despite one missed frame (DeletionThreshold=[5 5] tolerates it).');

            tSeq = feedback.track_time_s{1};
            rSeq = feedback.track_range_m{1};
            gaps = diff(tSeq);
            fprintf('track_time_s gaps: %s\n', mat2str(gaps', 4));

            tc.verifyTrue(any(gaps > 1.5 * frameIntervalS), ...
                'The missed frame should show up as a >1-frame_interval_s gap in track_time_s.');

            % Recompute BOTH ways from the returned series and show they
            % genuinely differ at the gap -- proving the fix changes the
            % actual number, not just that a gap was recorded.
            dSeqOldBuggy = diff(rSeq) / frameIntervalS;
            dSeqFixed    = diff(rSeq) ./ gaps;
            gapIdx = find(gaps > 1.5 * frameIntervalS, 1);
            fprintf('at the gap: old(constant-interval)=%.2f m/s  fixed(actual-elapsed)=%.2f m/s\n', ...
                dSeqOldBuggy(gapIdx), dSeqFixed(gapIdx));
            tc.verifyNotEqual(dSeqOldBuggy(gapIdx), dSeqFixed(gapIdx));
            tc.verifyEqual(abs(dSeqFixed(gapIdx)), abs(dSeqOldBuggy(gapIdx)) / 2, 'RelTol', 0.05, ...
                'A 2-frame_interval_s gap should halve the range-rate magnitude vs. the old constant-interval formula.');
        end

    end

end

% ===================== file-local helpers =============================
function tf = localDeleteIfExists(f) %#ok<DEFNU>
    tf = isfile(f);
    if tf; delete(f); end
end
