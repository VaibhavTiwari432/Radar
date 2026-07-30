function results = canonical_scene_crosscheck()
%CANONICAL_SCENE_CROSSCHECK  Run each canonical scenario (loaded from the
%   byte-identical rx buffers Python exported) through the Phase 1 MATLAB
%   judge (+radar/+track), frame by frame, for comparison against
%   cogengine/fixtures/<name>_python_result.json.
%
%   Scenarios (see canonical_scene_crosscheck.py for definitions):
%     closing_real -- R0=5000m, v=-60 m/s: both sides should confirm AND
%                     label "real" (self-consistent kinematics).
%     static_decoy -- R0=5000m, v=0: both sides should confirm the raw
%                     track but FLAG it at the ECCM stage (zero Doppler,
%                     no amplitude-range law to verify against).
%
%   CLAUDE.md Rule 2: this script feeds the judge byte-identical input to
%   Python's twin -- any DIFFERENCE in detected/range/confirmed/label is a
%   genuine algorithm or convention mismatch, not noise-draw divergence.

    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    projectRoot = fileparts(root);
    addpath(projectRoot);

    scenarios = {'closing_real', 'static_decoy'};
    results = struct();
    for i = 1:numel(scenarios)
        name = scenarios{i};
        results.(name) = runOne(here, name);
    end
end

% ------------------------------------------------------------------------
function result = runOne(here, name)
    S = load(fullfile(here, [name '_iq.mat']));
    rxFrames = S.rx_frames;
    numFrames = size(rxFrames, 2);

    C = physics.Constants();
    wav = phased.LinearFMWaveform('SampleRate', S.fs, ...
            'PulseWidth', S.pulse_width_s, 'PRF', S.prf_hz, ...
            'SweepBandwidth', S.bandwidth_hz);

    detected = false(1, numFrames);
    rangeEst = nan(1, numFrames);
    ampEst   = nan(1, numFrames);
    dets = cell(1, numFrames);
    times = (0:numFrames-1) * S.frame_interval_s;

    for k = 1:numFrames
        rx = rxFrames(:, k);
        power = radar.pulseCompress(rx, wav);
        detIdx = radar.cfarDetect(power, 'Pfa', S.cfar_pfa, ...
                    'NumTraining', S.cfar_num_training, 'NumGuard', S.cfar_num_guard);
        if isempty(detIdx)
            dets{k} = objectDetection.empty;
        else
            [~, im] = max(power(detIdx));
            rbin = detIdx(im);
            detected(k) = true;
            rangeEst(k) = (rbin - 1) * C.range_per_sample;
            ampEst(k) = sqrt(power(rbin));
            dets{k} = objectDetection(times(k), [rangeEst(k); 0; 0], 'MeasurementNoise', eye(3));
        end
    end

    confirmedTracks = track.runTracker(dets, times, C);
    confirmed = numel(confirmedTracks) >= 1;

    label = "";
    if confirmed
        m = ~isnan(rangeEst);
        rSeq = rangeEst(m);
        aSeq = ampEst(m);
        if nnz(m) >= 2
            dSeq = diff(rSeq) / S.frame_interval_s;
            dSeq = [dSeq(1), dSeq];
            trackStruct = struct('range', rSeq, 'amplitude', aSeq, 'doppler', dSeq);
            [label, ~] = track.discriminator(trackStruct, C);
        else
            label = "unscreened";
        end
    end

    result = struct();
    result.true_range_m = S.true_range_m;
    result.detected = detected;
    result.range_est_m = rangeEst;
    result.amp_est = ampEst;
    result.confirmed = confirmed;
    result.eccm_label = char(label);

    fprintf('\n=====================================\n');
    fprintf(' MATLAB JUDGE -- %s\n', name);
    fprintf('=====================================\n');
    for k = 1:numFrames
        fprintf('frame %d: true_R=%.1f detected=%d range_est=%.2f amp_est=%.4f\n', ...
            k, S.true_range_m(k), detected(k), rangeEst(k), ampEst(k));
    end
    fprintf('-------------------------------------\n');
    fprintf('confirmed = %d\n', confirmed);
    fprintf('eccm_label = %s\n', char(label));
    fprintf('=====================================\n\n');

    fid = fopen(fullfile(here, [name '_matlab_result.json']), 'w');
    fwrite(fid, jsonencode(result, 'PrettyPrint', true));
    fclose(fid);
end
