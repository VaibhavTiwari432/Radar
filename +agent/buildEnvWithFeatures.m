function [env, degradedEvent] = buildEnvWithFeatures(C)
%BUILDENVWITHFEATURES  Same DRFM-vs-radar engagement as agent.buildEnv, but
%   the tx_template fed to synth.synthesizeSwarm is built from a NOISY
%   intercepted pulse via feature-matched synthesis
%   (features.synthesizeTxPulse): characterize the intercept against the
%   known nominal chirp rate (features.characterizeInterceptDechirp) and
%   rebuild a clean coherent replica (features.coherentReplica) to use as
%   the tx_template.
%
%   Feature-matched synthesis is the ONLY path -- there is no caller-facing
%   'generic'/'featureMatched' switch (mission: "remove the generic/baseline
%   path as a caller-facing option everywhere"). features.synthesizeTxPulse
%   is THE single entry point and carries its OWN internal safety net: if
%   the intercept characterization fails structurally (aliasingMargin<=0 --
%   not merely ordinary high-noise low confidence, which shrinkage already
%   handles), it falls back to a raw noisy verbatim replay. degradedEvent
%   below surfaces that -- callers MUST report it, not swallow it (mission
%   Task 1: "visible, not silent").
%
%   The historical generic-vs-featureMatched COMPARISON that measured the
%   original +10pt confirmation-rate / 2.13x compression deltas is
%   preserved, frozen, in
%   tests/historical_baseline/test_synthesis_mode_comparison_matlab.m -- NOT
%   reproducible by calling this function anymore, since 'generic' is no
%   longer a mode this function can produce.
%
%   Why this needs a noisy-intercept step at all, and why agent.buildEnv
%   couldn't show it: agent.buildEnv builds its tx_template directly from a
%   mathematically perfect phased.LinearFMWaveform() output -- there is no
%   modeled intercept-receiver noise, so a verbatim replay is ALREADY a
%   perfect coherent copy and characterize->replicate has nothing to
%   improve. This function adds that missing noisy-intercept step.
%
%   [env, degradedEvent] = agent.buildEnvWithFeatures(C)
%       degradedEvent : [] (empty) normally, or a struct with
%                       frame/reason/confidence if synthesizeTxPulse's
%                       internal fallback fired for this build's intercept
%                       draw -- report it, don't discard it.
%
%   ADDITIVE (per mission constraints): agent.buildEnv.m is untouched and
%   kept in the repo as the fallback TARGET synthesizeTxPulse's gate replays
%   verbatim when characterization fails -- not as a caller-selectable mode.
%   Action space, reward shape, and judge chain (radar.pulseCompress ->
%   radar.cfarDetect -> track.runTracker -> track.discriminator) are
%   IDENTICAL to agent.buildEnv -- only tx_template construction differs.
%   Ref: cognitive_engine/cogengine/features.py; +features/*.m.

    obsInfo = rlNumericSpec([3 1], 'Name', 'obs');
    obsInfo.LowerLimit = [0; 0; 0];
    obsInfo.UpperLimit = [1; 1; 1];

    numDeltas = 5;
    numGains  = 9;                   % 5*9 = 45 actions, same as agent.buildEnv
    actInfo = rlFiniteSetSpec(1:(numDeltas*numGains));
    actInfo.Name = 'drfm_action';

    pulseWidthS = 12e-6;
    sweepBandwidthHz = 2e6;
    wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
            'PulseWidth', pulseWidthS, 'PRF', 50e3, 'SweepBandwidth', sweepBandwidthHz);
    pulse = wav();
    bufferLen = 400;

    % Active pulse length ONLY (~39 samples of actual chirp energy, per
    % getMatchedFilter -- NOT the full 64-sample PRI, which is mostly
    % trailing quiet time). See features.synthesizeTxPulse's own comments
    % for why characterizing the full PRI would corrupt the phase-based IF
    % estimator once intercept noise is added.
    activeLen = numel(getMatchedFilter(wav));
    activePulse = pulse(1:activeLen);

    % ponytail: fixed intercept-noise amplitude, not derived from a modeled
    % receiver noise figure. Verified at interceptNoiseAmp=2.0 this is where
    % a noisy verbatim replay stops detecting at all (its numerically larger
    % raw peak is a WORSE CFAR statistic -- uncorrelated intercept noise
    % elevates nearby training cells too, not just the peak) while
    % feature-matched synthesis keeps detecting reliably -- see
    % tests/historical_baseline/test_synthesis_mode_comparison_matlab.m and
    % Integration_Report.md.
    interceptNoiseAmp = 2.0;
    rngIntercept = RandStream('mt19937ar', 'Seed', 12345);
    nominalChirpRateHzS = sweepBandwidthHz / pulseWidthS;

    [txPulse, degradedEvent] = features.synthesizeTxPulse( ...
        activePulse, C.fs, nominalChirpRateHzS, interceptNoiseAmp, rngIntercept, 0);

    xTemplate = [txPulse; zeros(bufferLen - numel(txPulse), 1)];

    deltaOptionsM = linspace(-120, 120, numDeltas);
    gainOptions   = linspace(0.5, 4.5, numGains);
    F = 8; dt = 1.0;
    R0 = 1800;

    env = rlFunctionEnv(obsInfo, actInfo, ...
        @(action, logged) localStep(action, logged, C, wav, xTemplate, bufferLen, ...
                                     deltaOptionsM, gainOptions, F, dt), ...
        @() localReset(R0));
end

% ------------------------------------------------------------------------
% Everything below is IDENTICAL to agent.buildEnv.m's localReset/localStep
% (copied, not modified -- CLAUDE.md/mission "no removals," and a fair
% before/after comparison needs the SAME downstream mechanics with only
% tx_template construction differing).
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
                % Unscreened-reward fix (Task 4, PHASE2_COMPLETION_POA.md):
                % previously `reward + 1`, IDENTICAL to the explicit "decoy"
                % branch above -- silently telling the RL agent "ECCM
                % rejected you" was equally true for an outcome ECCM never
                % actually evaluated (too few valid range/amplitude points
                % to run track.discriminator at all). No ECCM-dependent
                % bonus here: matches +experiments/runBenchmark.m's own
                % stated intent ("unscreened... honestly excluded rather
                % than silently counted as a pass") -- the reward signal
                % needs the same honesty as the reporting already has, or
                % training can't tell "caught" from "never judged".
                logged.eccmLabel = "unscreened";
            end
        end
    end

    obs = [logged.k/F; newRange/3000; double(detected)];
end
