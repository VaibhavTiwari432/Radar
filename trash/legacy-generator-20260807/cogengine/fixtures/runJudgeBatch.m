function results = runJudgeBatch()
%RUNJUDGEBATCH  Run every seed's CEM-planned scene (exported by
%   cem_vs_judge_batch.py) through the real MATLAB judge
%   (+engine/runJudge.m) and log confirmed/surviving/flagged/label per seed.
%
%   CLAUDE.md Rule 2, Golden Rule: this is the independent scorer's actual
%   verdict on the twin's plans -- logged per seed, not averaged away.

    here = fileparts(mfilename('fullpath'));
    projectRoot = fileparts(here);
    addpath(projectRoot);

    S = load(fullfile(here, 'cem_batch.mat'));
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
                % No Doppler is reported: this script's rx_frames_all is a
                % 2-D per-frame buffer with no slow-time axis, so there is
                % physically nothing to Doppler-process. It used to pass
                % diff(rSeq)/frame_interval_s here, which made
                % track.discriminator's sign screen a tautology that could
                % never fail -- see +engine/runJudge.m's "DOPPLER IS NOW
                % MEASURED" header. All-zero correctly trips the
                % discriminator's own abs(dopplerMean) > 1e-9 guard so the
                % screen self-disables as uninformative instead of handing
                % out a free pass. Labels from this script can therefore
                % differ from ones published before 25 July 2026.
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

    fid = fopen(fullfile(here, 'cem_batch_matlab_results.json'), 'w');
    fwrite(fid, jsonencode(results, 'PrettyPrint', true));
    fclose(fid);
end
