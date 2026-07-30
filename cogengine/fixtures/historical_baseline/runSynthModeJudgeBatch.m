function results = runSynthModeJudgeBatch()
%RUNSYNTHMODEJUDGEBATCH  HISTORICAL BASELINE -- retained for reproducibility
%   of the generic-vs-feature-matched delta; not part of the active
%   runtime. Feature-matched synthesis is now the sole active path
%   (+agent/buildEnvWithFeatures.m, cogengine/matlab_judge.py); the
%   "generic" rx buffers this script scores were produced by a frozen
%   local copy of the old export path (see
%   historical_baseline/synthesis_mode_judge_comparison.py), not the
%   active pipeline, which can no longer emit them.
%
%   The SAME canonical scene, generic vs feature-matched synthesis,
%   scored by the REAL MATLAB judge. Loads synth_mode_batch.mat (from
%   historical_baseline/synthesis_mode_judge_comparison.py).

    here = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(here);
    addpath(projectRoot);

    S = load(fullfile(here, 'synth_mode_batch.mat'));
    modes = {'generic', 'featureMatched'};

    C = physics.Constants();
    wav = phased.LinearFMWaveform('SampleRate', S.fs, ...
            'PulseWidth', S.pulse_width_s, 'PRF', S.prf_hz, ...
            'SweepBandwidth', S.bandwidth_hz);

    results = struct();
    for m = 1:numel(modes)
        mode = modes{m};
        rxAll = S.(['rx_frames_' mode]);
        nTrials = size(rxAll, 3);
        times = (0:size(rxAll,2)-1) * S.frame_interval_s;

        confirmedCount = 0; survivingCount = 0; flaggedCount = 0;
        for i = 1:nTrials
            rxFrames = rxAll(:,:,i);
            numFrames = size(rxFrames, 2);
            detected = false(1, numFrames);
            rangeEst = nan(1, numFrames);
            ampEst   = nan(1, numFrames);
            dets = cell(1, numFrames);

            for k = 1:numFrames
                rx = rxFrames(:, k);
                power = radar.pulseCompress(rx, wav);
                detIdx = radar.cfarDetect(power, 'Pfa', S.cfar_pfa, ...
                            'NumTraining', S.cfar_num_training, 'NumGuard', S.cfar_num_guard);
                if ~isempty(detIdx)
                    [~, im] = max(power(detIdx));
                    rbin = detIdx(im);
                    detected(k) = true;
                    rangeEst(k) = (rbin - 1) * C.range_per_sample;
                    ampEst(k) = sqrt(power(rbin));
                    dets{k} = objectDetection(times(k), [rangeEst(k); 0; 0], 'MeasurementNoise', eye(3));
                else
                    dets{k} = objectDetection.empty;
                end
            end

            confirmedTracks = track.runTracker(dets, times, C);
            isConfirmed = numel(confirmedTracks) >= 1;
            confirmedCount = confirmedCount + double(isConfirmed);

            if isConfirmed
                mIdx = ~isnan(rangeEst);
                if nnz(mIdx) >= 2
                    rSeq = rangeEst(mIdx); aSeq = ampEst(mIdx);
                    dSeq = diff(rSeq) / S.frame_interval_s;
                    dSeq = [dSeq(1), dSeq];
                    [label, ~] = track.discriminator(struct('range', rSeq, 'amplitude', aSeq, 'doppler', dSeq), C);
                    if strcmp(char(label), 'real')
                        survivingCount = survivingCount + 1;
                    elseif strcmp(char(label), 'decoy')
                        flaggedCount = flaggedCount + 1;
                    end
                end
            end
        end

        results.(mode).confirmed_rate = confirmedCount / nTrials;
        results.(mode).surviving_rate = survivingCount / nTrials;
        results.(mode).flagged_rate = flaggedCount / nTrials;
        fprintf('%s: confirmed=%.0f%% surviving=%.0f%% flagged=%.0f%% (N=%d)\n', ...
            mode, results.(mode).confirmed_rate*100, results.(mode).surviving_rate*100, ...
            results.(mode).flagged_rate*100, nTrials);
    end

    fprintf('\ndelta_confirmed = %+.0f pts\n', ...
        (results.featureMatched.confirmed_rate - results.generic.confirmed_rate)*100);
    fprintf('delta_flagged   = %+.0f pts\n', ...
        (results.featureMatched.flagged_rate - results.generic.flagged_rate)*100);
end
