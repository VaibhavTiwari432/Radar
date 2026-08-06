function results = runJudgeBatchFeatureConditioned()
%RUNJUDGEBATCHFEATURECONDITIONED  Mission task 5 revalidation: run every
%   seed's CEM-planned scene (exported by
%   cem_vs_judge_batch_feature_conditioned.py, intercept_noise_amplitude=2.0,
%   feature-matched synthesis as the SOLE mode) through the real MATLAB judge
%   (radar.pulseCompress -> radar.cfarDetect -> track.runTracker ->
%   track.discriminator) and log confirmed/surviving/flagged/label per seed.
%
%   Same structure as runJudgeBatch.m (the intercept_noise_amplitude=0.0
%   kinematic cross-check), pointed at the feature-conditioned batch file
%   instead -- CLAUDE.md Rule 2, Golden Rule: the independent judge's actual
%   verdict on the twin's feature-conditioned plans, logged per seed.

    here = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(here);
    addpath(projectRoot);

    S = load(fullfile(here, 'cem_batch_feature_conditioned.mat'));
    numSeeds = numel(S.seeds);

    results = struct('seed', {}, 'confirmed_tracks', {}, 'false_tracks_surviving', {}, ...
                      'flagged_decoys', {}, 'eccm_label', {});

    C = physics.Constants();
    wav = phased.LinearFMWaveform('SampleRate', S.fs, ...
            'PulseWidth', S.pulse_width_s, 'PRF', S.prf_hz, ...
            'SweepBandwidth', S.bandwidth_hz);
    times = (0:size(S.rx_frames_all,2)-1) * S.frame_interval_s;

    for i = 1:numSeeds
        rxFrames = S.rx_frames_all(:,:,i);
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
            m = ~isnan(rangeEst);
            if nnz(m) >= 2
                rSeq = rangeEst(m); aSeq = ampEst(m);
                % See runJudgeBatch.m's note: no slow-time axis in this
                % script's 2-D buffers, so no Doppler is reported and
                % track.discriminator's sign screen self-disables rather
                % than granting the tautological pass diff(rSeq) used to.
                dSeq = zeros(size(rSeq));
                [label, ~] = track.discriminator(struct('range', rSeq, 'amplitude', aSeq, 'doppler', dSeq), C);
            else
                label = "unscreened";
            end
        end

        isReal = confirmedCount >= 1 && strcmp(char(label), 'real');
        isDecoy = confirmedCount >= 1 && strcmp(char(label), 'decoy');

        results(i).seed = S.seeds(i);
        results(i).confirmed_tracks = confirmedCount;
        results(i).false_tracks_surviving = double(isReal);
        results(i).flagged_decoys = double(isDecoy);
        results(i).eccm_label = char(label);

        fprintf('seed %d: judge_confirmed=%d judge_surviving=%d judge_flagged=%d label=%s\n', ...
            S.seeds(i), confirmedCount, double(isReal), double(isDecoy), char(label));
    end

    fid = fopen(fullfile(here, 'cem_batch_feature_conditioned_matlab_results.json'), 'w');
    fwrite(fid, jsonencode(results, 'PrettyPrint', true));
    fclose(fid);
end
