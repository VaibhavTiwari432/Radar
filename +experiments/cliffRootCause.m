function out = cliffRootCause(nEp, seed)
%CLIFFROOTCAUSE  Why does the judge's CFAR training length change the ECCM
%   VERDICT when it does not change whether anything is DETECTED?
%
%   out = experiments.cliffRootCause(nEp, seed)   % 60, 11
%
%   THE OBSERVATION BEING EXPLAINED (experiments.observerSweep, n=100,
%   seed 11): sweeping the judge's CA-CFAR NumTraining from 20 to 32 drops
%   the structural generator's real-rate from 23.0% [16,32] to 8.0% [4,15] --
%   Wilson intervals disjoint -- while `confirmed` stays at 100.0% in BOTH
%   configurations, and while Pfa swept across FOUR ORDERS OF MAGNITUDE
%   (1e-6 to 1e-2) changes precisely nothing. A knob that does not change
%   what is detected should not change what the detections are labelled.
%
%   THE HYPOTHESIS, stated before measuring so it can be wrong: a wider
%   training window moves the CA-CFAR threshold, which changes WHICH
%   adjacent bins cross it, which changes which peak localMaxPeaks returns,
%   which perturbs the per-track AMPLITUDE series -- and discriminator
%   screen 1 fits log(A) vs log(R) over only ~8 frames and a ~1.27x range
%   change, a lever arm this project already documents as too short to fit a
%   slope against noise. Under that hypothesis the cliff is a REAL and
%   already-known weakness of screen 1 being exposed by a new knob, not a
%   new bug and not a physics effect of the training window itself.
%
%   THE COMPETING EXPLANATION it has to beat: the training length genuinely
%   changes detection quality in a way `confirmed` (a binary, saturated at
%   100%) is too coarse to show -- e.g. it drops individual FRAMES from
%   tracks, shortening the series screen 1 fits. That predicts a change in
%   the NUMBER of usable frames, which the amplitude hypothesis does not.
%   The two are separated by measuring both.
%
%   METHOD. One rollout per episode; the SAME retained cube scored twice,
%   at NumTraining 20 and 32, nothing else moved. Per episode record, for
%   each configuration: the number of frames the track actually has, the
%   fitted log-amplitude-vs-log-range slope, and the judge's label. A
%   difference cannot be a different noise draw.

    if nargin < 1 || isempty(nEp);  nEp  = 60; end
    if nargin < 2 || isempty(seed); seed = 11; end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);

    C = physics.Constants();
    [env, spec] = agent.buildEnvEntity(C, struct('shaping', false, ...
                        'keepCube', true, 'swerling', 1));
    nVel = numel(spec.velOptionsMps);
    nRcs = numel(spec.rcsOptionsDbsm);
    zeroVel = find(abs(spec.velOptionsMps) < 1e-9);

    trainVals = [20 32];
    nFrames = nan(nEp, 2); slope = nan(nEp, 2); isReal = nan(nEp, 2);

    rng(seed);
    fprintf('cliffRootCause: %d episodes, same cube at NumTraining %d and %d\n\n', ...
        nEp, trainVals(1), trainVals(2));
    for e = 1:nEp
        reset(env);
        vi = zeroVel;
        while vi == zeroVel; vi = randi(nVel); end
        a = sub2ind([nVel nRcs], vi, randi(nRcs));
        lg = [];
        for k = 1:spec.framesPerEpisode
            [~, ~, ~, lg] = step(env, a);
        end

        S = struct('rx_frames', lg.cubeFrames, 'fs', C.fs, ...
            'pulse_width_s', 12e-6, 'bandwidth_hz', 2e6, 'prf_hz', C.PRF, ...
            'frame_interval_s', spec.dt, 'carrier_hz', spec.carrierHz);
        f = [tempname '.mat']; save(f, '-struct', 'S');
        for t = 1:2
            fb = engine.runJudge(f, 'NumTraining', trainVals(t), ...
                                     'EccmScreens', {'amplitude', 'doppler'});
            if isempty(fb.track_range_m); continue; end
            R = fb.track_range_m{1}; A = fb.track_amp{1};
            m = isfinite(R) & isfinite(A) & R > 0 & A > 0;
            nFrames(e, t) = nnz(m);
            if nnz(m) >= 2
                p = polyfit(log(R(m)), log(A(m)), 1);
                slope(e, t) = p(1);
            end
            isReal(e, t) = double(strcmp(char(fb.eccm_label), 'real'));
        end
        delete(f);
        if mod(e, 20) == 0; fprintf('  %d/%d\n', e, nEp); end
    end

    fprintf('\n  %-22s %12s %12s\n', '', sprintf('NumTraining %d', trainVals(1)), ...
        sprintf('NumTraining %d', trainVals(2)));
    fprintf('  %-22s %12.1f %12.1f\n', 'mean usable frames', ...
        mean(nFrames(:,1), 'omitnan'), mean(nFrames(:,2), 'omitnan'));
    fprintf('  %-22s %12.3f %12.3f\n', 'mean fitted slope', ...
        mean(slope(:,1), 'omitnan'), mean(slope(:,2), 'omitnan'));
    fprintf('  %-22s %12.3f %12.3f\n', 'std fitted slope', ...
        std(slope(:,1), 'omitnan'), std(slope(:,2), 'omitnan'));
    fprintf('  %-22s %11.1f%% %11.1f%%\n', 'judge real rate', ...
        100*mean(isReal(:,1), 'omitnan'), 100*mean(isReal(:,2), 'omitnan'));

    % The discriminating statistics. The amplitude hypothesis predicts the
    % SLOPE moves and the frame count does not; the detection-quality
    % explanation predicts the frame count moves.
    dFrames = nFrames(:,2) - nFrames(:,1);
    dSlope  = slope(:,2)  - slope(:,1);
    fracFrameChanged = mean(dFrames ~= 0, 'omitnan');
    fracSlopeChanged = mean(abs(dSlope) > 1e-9, 'omitnan');
    flipped = isReal(:,1) == 1 & isReal(:,2) == 0;

    fprintf('\n  episodes whose usable-frame COUNT changed : %5.1f%%\n', 100*fracFrameChanged);
    fprintf('  episodes whose fitted SLOPE changed       : %5.1f%%\n', 100*fracSlopeChanged);
    fprintf('  episodes that flipped real -> decoy       : %5.1f%% (n=%d)\n', ...
        100*mean(flipped), nnz(flipped));
    if nnz(flipped) > 0
        fprintf('    their slope at %d: %+.3f   at %d: %+.3f   (physical value -2)\n', ...
            trainVals(1), mean(slope(flipped,1), 'omitnan'), ...
            trainVals(2), mean(slope(flipped,2), 'omitnan'));
        fprintf('    their frame count at %d: %.2f   at %d: %.2f\n', ...
            trainVals(1), mean(nFrames(flipped,1), 'omitnan'), ...
            trainVals(2), mean(nFrames(flipped,2), 'omitnan'));
    end

    if fracSlopeChanged > 0 && fracFrameChanged < 0.1
        verdict = 'AMPLITUDE-SERIES (screen 1 lever arm) -- hypothesis supported';
    elseif fracFrameChanged >= 0.1
        verdict = 'DETECTION QUALITY (frames dropped) -- competing explanation supported';
    else
        verdict = 'NEITHER moved -- hypothesis REFUTED, cause is elsewhere';
    end
    fprintf('\n  VERDICT: %s\n', verdict);

    out = struct('nEp', nEp, 'seed', seed, 'trainVals', trainVals, ...
        'nFrames', nFrames, 'slope', slope, 'isReal', isReal, ...
        'fracFrameChanged', fracFrameChanged, 'fracSlopeChanged', fracSlopeChanged, ...
        'nFlipped', nnz(flipped), 'verdict', verdict);
    f = fullfile(root, 'results', 'cliff_root_cause.mat');
    save(f, '-struct', 'out');
    fprintf('\nsaved -> %s\n', f);
end
