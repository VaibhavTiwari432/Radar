function env = buildEnv(C)
%BUILDENV  rlFunctionEnv wrapping a genuinely sequential DRFM-vs-radar
%          deception engagement.
%
%   env = agent.buildEnv(C)
%
%   Multi-step episode (F=8 frames, one rlFunctionEnv step per frame). At
%   each step the agent picks ONE of 45 discretized actions: 5 per-frame
%   RANGE-WALK deltas x 9 GAIN levels. The walk means Doppler is DERIVED
%   from the agent's own kinematic choices (not a fixed/zero parameter),
%   and the agent can learn to make gain track range the way a physical
%   1/R^2 return would -- both are prerequisites for fooling
%   track.discriminator, not just track.runTracker.
%
%   Observation [3x1]: [frameIndex/F ; currentFakeRange/3000 ; wasDetectedLastFrame]
%   -- lets the agent condition its next gain/delta choice on where it
%   currently is and whether it's currently visible, which a single-shot
%   bandit could never do.
%
%   Reward: small per-frame shaping (+0.05 if detected that frame) plus a
%   terminal bonus computed ONLY from the independent radar chain:
%       +2  track.runTracker confirms a track AND track.discriminator
%           labels it "real"        (fooled tracker AND ECCM -- full win)
%       +1  track.runTracker confirms a track but track.discriminator
%           labels it "decoy"       (fooled tracker only -- Stage 3's win,
%                                    not Stage 5's)
%       +0  no confirmed track
%   CLAUDE.md Rule 2: reward derives ONLY from track.runTracker and
%   track.discriminator, never from +synth grading itself.
%
%   Paired with agent.buildAgent(env) (dueling Double-DQN). Ref: POA Part
%   4-5, Stage 6, claim C9.

    obsInfo = rlNumericSpec([3 1], 'Name', 'obs');
    obsInfo.LowerLimit = [0; 0; 0];
    obsInfo.UpperLimit = [1; 1; 1];

    numDeltas = 5;
    numGains  = 9;                   % 5*9 = 45 actions (POA)
    actInfo = rlFiniteSetSpec(1:(numDeltas*numGains));
    actInfo.Name = 'drfm_action';

    wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
            'PulseWidth', 12e-6, 'PRF', 50e3, 'SweepBandwidth', 2e6);
    pulse = wav();
    bufferLen = 400;
    xTemplate = [pulse; zeros(bufferLen - numel(pulse), 1)];

    deltaOptionsM = linspace(-120, 120, numDeltas);   % per-frame range walk [m]
    gainOptions   = linspace(0.5, 4.5, numGains);     % repeater gain levels
    F = 8; dt = 1.0;                 % same revisit cadence as Stage 3
    R0 = 1800;                       % fixed start, comfortably inside the
                                     % detectable zone (Stage 6's own probe
                                     % found the CFAR guard/training margin
                                     % blinds ranges below ~1300 m)

    env = rlFunctionEnv(obsInfo, actInfo, ...
        @(action, logged) localStep(action, logged, C, wav, xTemplate, bufferLen, ...
                                     deltaOptionsM, gainOptions, F, dt), ...
        @() localReset(R0));
end

% ------------------------------------------------------------------------
function [obs, logged] = localReset(R0)
    logged.k       = 0;
    logged.range   = R0;
    logged.dets    = {};
    logged.times   = [];
    logged.rangeHist = [];
    logged.ampHist   = [];
    logged.detectedHist = [];
    logged.confirmedCount = 0;
    logged.eccmLabel = "";
    obs = [0; R0/3000; 0];
end

% ------------------------------------------------------------------------
function [obs, reward, isDone, logged] = localStep(action, logged, C, wav, xTemplate, ...
        bufferLen, deltaOptionsM, gainOptions, F, dt)

    [di, gi] = ind2sub([numel(deltaOptionsM) numel(gainOptions)], action);
    newRange = min(2950, max(150, logged.range + deltaOptionsM(di)));
    gain     = gainOptions(gi);
    tau      = 2 * newRange / C.c;

    actionStruct = struct('delay_s', tau, 'phase_rad', 0, 'gain', gain);
    Y = synth.synthesizeSwarm(xTemplate, actionStruct, C);

    frameTime = logged.k * dt;
    noise = 0.05 * (randn(bufferLen,1) + 1i*randn(bufferLen,1)) / sqrt(2);
    rx = Y + noise;
    power  = radar.pulseCompress(rx, wav);
    detIdx = radar.cfarDetect(power, 'Pfa', 1e-4);

    if isempty(detIdx)
        det = objectDetection.empty;
        detected = false;
        rEst = NaN; ampEst = NaN;
    else
        [pk, im] = max(power(detIdx));
        rbin = detIdx(im);
        rEst = (rbin-1) * C.range_per_sample;
        ampEst = sqrt(pk);
        detected = true;
        det = objectDetection(frameTime, [rEst; 0; 0], 'MeasurementNoise', eye(3));
    end

    logged.dets{end+1}     = det;
    logged.times(end+1)    = frameTime;
    logged.rangeHist(end+1) = rEst;
    logged.ampHist(end+1)   = ampEst;
    logged.detectedHist(end+1) = detected;
    logged.k     = logged.k + 1;
    logged.range = newRange;

    reward = 0.05 * double(detected);   % small shaping: partial credit for staying visible
    isDone = (logged.k >= F);

    if isDone
        confirmed = track.runTracker(logged.dets, logged.times, C);
        logged.confirmedCount = numel(confirmed);
        if numel(confirmed) >= 1
            m = ~isnan(logged.rangeHist) & ~isnan(logged.ampHist);
            rngSeq = logged.rangeHist(m);
            ampSeq = logged.ampHist(m);
            if nnz(m) >= 2
                % track.discriminator expects doppler with the SAME sign as
                % the range-rate diff(range) (closing = both negative,
                % verified against Stage 5's own convention) -- no negation.
                dopSeq = diff(rngSeq) / dt;
                dopSeq = [dopSeq(1), dopSeq];   %#ok<AGROW>  % pad to match length
                trackStruct = struct('range', rngSeq, 'amplitude', ampSeq, 'doppler', dopSeq);
                [label, ~] = track.discriminator(trackStruct, C);
                logged.eccmLabel = label;
                if label == "real"
                    reward = reward + 2;   % fooled tracker AND ECCM
                else
                    reward = reward + 1;   % fooled tracker only
                end
            else
                logged.eccmLabel = "unscreened";
                reward = reward + 1;       % confirmed, too few points to screen
            end
        end
    end

    obs = [logged.k/F; newRange/3000; double(detected)];
end
