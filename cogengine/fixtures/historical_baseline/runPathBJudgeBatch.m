function results = runPathBJudgeBatch()
%RUNPATHBJUDGEBATCH  Run each seed's CEM-planned scene, under BOTH
%   synthesis modes (generic / featureMatched), through the real MATLAB
%   judge (+radar/+track) -- Path B's actual verdict: does feature-matched
%   synthesis improve judge-verified evasion for CEM-planned scenes, not
%   just the twin's own prediction?
%
%   Loads path_b_batch.mat (from cogengine/fixtures/path_b_synthesis_comparison.py),
%   which has rx_frames_generic and rx_frames_featureMatched, each
%   [fast_time_samples x num_frames x num_seeds].

    here = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(here);
    addpath(projectRoot);

    S = load(fullfile(here, 'path_b_batch.mat'));
    numSeeds = numel(S.seeds);
    modes = {'generic', 'featureMatched'};

    C = physics.Constants();
    wav = phased.LinearFMWaveform('SampleRate', S.fs, ...
            'PulseWidth', S.pulse_width_s, 'PRF', S.prf_hz, ...
            'SweepBandwidth', S.bandwidth_hz);

    results = struct();
    for m = 1:numel(modes)
        mode = modes{m};
        rxAll = S.(['rx_frames_' mode]);
        times = (0:size(rxAll,2)-1) * S.frame_interval_s;

        modeResults = struct('seed', {}, 'confirmed_tracks', {}, ...
            'false_tracks_surviving', {}, 'flagged_decoys', {}, 'eccm_label', {});

        fprintf('\n=== mode: %s ===\n', mode);
        for i = 1:numSeeds
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
            confirmedCount = numel(confirmedTracks);

            label = "";
            if confirmedCount >= 1
                mIdx = ~isnan(rangeEst);
                if nnz(mIdx) >= 2
                    rSeq = rangeEst(mIdx); aSeq = ampEst(mIdx);
                    dSeq = diff(rSeq) / S.frame_interval_s;
                    dSeq = [dSeq(1), dSeq];
                    [label, ~] = track.discriminator(struct('range', rSeq, 'amplitude', aSeq, 'doppler', dSeq), C);
                else
                    label = "unscreened";
                end
            end

            isReal = confirmedCount >= 1 && strcmp(char(label), 'real');
            isDecoy = confirmedCount >= 1 && strcmp(char(label), 'decoy');

            modeResults(i).seed = S.seeds(i);
            modeResults(i).confirmed_tracks = confirmedCount;
            modeResults(i).false_tracks_surviving = double(isReal);
            modeResults(i).flagged_decoys = double(isDecoy);
            modeResults(i).eccm_label = char(label);

            fprintf('seed %d: judge_confirmed=%d judge_surviving=%d judge_flagged=%d label=%s\n', ...
                S.seeds(i), confirmedCount, double(isReal), double(isDecoy), char(label));
        end
        results.(mode) = modeResults;
    end

    fid = fopen(fullfile(here, 'path_b_matlab_results.json'), 'w');
    fwrite(fid, jsonencode(results, 'PrettyPrint', true));
    fclose(fid);
end
