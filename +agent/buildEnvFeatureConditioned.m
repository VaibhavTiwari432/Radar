function [env, degradedEvent] = buildEnvFeatureConditioned(C, pfb)
%BUILDENVFEATURECONDITIONED  Feature-conditioned DRFM-vs-radar environment for
%   a D3QN that generates fake signals informed by the 54-D PFB feature
%   vector of its OWN rendered echo -- the missing link the mission asked
%   for: features.featureVector is in the OBSERVATION, so the agent perceives
%   how "real" its fake looks and can steer toward a signature the
%   INDEPENDENT judge (radar.pulseCompress -> radar.cfarDetect ->
%   track.runTracker -> track.discriminator) confirms as real.
%
%   [env, degradedEvent] = agent.buildEnvFeatureConditioned(C, pfb)
%       C   : physics.Constants()
%       pfb : features.buildChannelizer() (built with defaults if omitted;
%             cached ONCE here, reused every step -- see buildChannelizer's
%             own note about not recomputing per call).
%       degradedEvent : [] normally, or {frame,reason,confidence} if the
%             feature-matched tx-template intercept fell back to verbatim
%             replay (features.synthesizeTxPulse's internal gate) -- surfaced,
%             never swallowed (same contract as agent.buildEnvWithFeatures).
%
%   DESIGN (CLAUDE.md Rule 2, held exactly):
%     * OBSERVATION [57x1] = [ k/F ; range/3000 ; detected ;
%                              tanh( featureVector(rx) ./ (3*refScale) ) ]
%       The 54 feature dims are the PFB fingerprint of the actual received
%       echo this frame (features.featureVector). refScale normalizes them
%       by a clean matched reference echo so the block is O(1)-bounded and
%       NN-stable, and tanh caps it to (-1,1).
%     * REWARD is UNCHANGED from agent.buildEnv: purely from the independent
%       radar/ECCM chain (+0.05/frame detected, +2 confirmed-and-real,
%       +1 confirmed-but-decoy/unscreened). Features NEVER enter the reward
%       -- letting +features grade the synthesizer's own realism would be
%       exactly the self-verification Rule 2 forbids. Features perceive; the
%       independent judge decides.
%     * ACTION space is the SAME 45 (5 range-walk deltas x 9 gains) as
%       agent.buildEnv -- Stage6_Test already proves this space can express
%       the gain~1/R^2 policy that beats the ECCM. The upgrade here is the
%       state the agent conditions on, not the knobs it turns. (Micro-Doppler
%       / coded-phase actions are a future extension -- synth.synthesizeSwarm
%       models delay/phase/gain only.)
%
%   Pairs with agent.buildAgentFeatureConditioned(env).

    if nargin < 2 || isempty(pfb); pfb = features.buildChannelizer(); end

    obsDim = 3 + 54;
    obsInfo = rlNumericSpec([obsDim 1], 'Name', 'obs');
    obsInfo.LowerLimit = [0; 0; 0; -ones(54,1)];
    obsInfo.UpperLimit = [1; 1; 1;  ones(54,1)];

    numDeltas = 5;
    numGains  = 9;                       % 5*9 = 45 actions (same as agent.buildEnv)
    actInfo = rlFiniteSetSpec(1:(numDeltas*numGains));
    actInfo.Name = 'drfm_action';

    pulseWidthS = 12e-6;
    sweepBandwidthHz = 2e6;
    wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
            'PulseWidth', pulseWidthS, 'PRF', 50e3, 'SweepBandwidth', sweepBandwidthHz);
    pulse = wav();
    bufferLen = 400;

    % Feature-matched tx template from a NOISY intercept (the SOLE active tx
    % path, per agent.buildEnvWithFeatures) -- characterize against the known
    % nominal chirp rate, rebuild a clean coherent replica.
    activeLen = numel(getMatchedFilter(wav));
    activePulse = pulse(1:activeLen);
    interceptNoiseAmp = 2.0;             % ponytail: validated tie-point, see buildEnvWithFeatures
    rngIntercept = RandStream('mt19937ar', 'Seed', 12345);
    nominalChirpRateHzS = sweepBandwidthHz / pulseWidthS;
    [txPulse, degradedEvent] = features.synthesizeTxPulse( ...
        activePulse, C.fs, nominalChirpRateHzS, interceptNoiseAmp, rngIntercept, 0);
    xTemplate = [txPulse; zeros(bufferLen - numel(txPulse), 1)];

    deltaOptionsM = linspace(-120, 120, numDeltas);
    gainOptions   = linspace(0.5, 4.5, numGains);
    F = 8; dt = 1.0;
    R0 = 1800;

    % ---- refScale: per-feature normalizer from ONE clean matched echo ----
    % A noiseless gain-1 phantom at R0 through the same rx pipeline is the
    % "this is what a real return's fingerprint looks like" anchor. Computed
    % once; the observation reports each frame's features relative to it.
    refAction = struct('delay_s', 2*R0/C.c, 'phase_rad', 0, 'gain', 1.0);
    refRx = synth.synthesizeSwarm(xTemplate, refAction, C);
    refScale = abs(features.featureVector(refRx, pfb)) + 1e-6;

    env = rlFunctionEnv(obsInfo, actInfo, ...
        @(action, logged) localStep(action, logged, C, wav, xTemplate, bufferLen, ...
                                     deltaOptionsM, gainOptions, F, dt, pfb, refScale), ...
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
    obs = [0; R0/3000; 0; zeros(54,1)];   % no echo yet -> zero feature block
end

% ------------------------------------------------------------------------
function [obs, reward, isDone, logged] = localStep(action, logged, C, wav, xTemplate, ...
        bufferLen, deltaOptionsM, gainOptions, F, dt, pfb, refScale)

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

    reward = 0.05 * double(detected);
    isDone = (logged.k >= F);

    if isDone
        confirmed = track.runTracker(logged.dets, logged.times, C);
        logged.confirmedCount = numel(confirmed);
        if numel(confirmed) >= 1
            m = ~isnan(logged.rangeHist) & ~isnan(logged.ampHist);
            rngSeq = logged.rangeHist(m);
            ampSeq = logged.ampHist(m);
            if nnz(m) >= 2
                dopSeq = diff(rngSeq) / dt;
                dopSeq = [dopSeq(1), dopSeq];   %#ok<AGROW>
                trackStruct = struct('range', rngSeq, 'amplitude', ampSeq, 'doppler', dopSeq);
                [label, ~] = track.discriminator(trackStruct, C);
                logged.eccmLabel = label;
                if label == "real"
                    reward = reward + 2;
                else
                    reward = reward + 1;
                end
            else
                logged.eccmLabel = "unscreened";
                reward = reward + 1;
            end
        end
    end

    % 54-D feature perception of THIS frame's echo, normalized + bounded.
    fv = features.featureVector(rx, pfb);
    fnorm = tanh(fv ./ (3*refScale));
    obs = [logged.k/F; newRange/3000; double(detected); fnorm];
end
