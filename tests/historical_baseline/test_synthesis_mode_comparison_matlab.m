classdef test_synthesis_mode_comparison_matlab < matlab.unittest.TestCase
%TEST_SYNTHESIS_MODE_COMPARISON_MATLAB  HISTORICAL BASELINE -- retained for
%   reproducibility of the generic-vs-feature-matched delta measured through
%   the full MATLAB judge chain (radar.pulseCompress -> radar.cfarDetect ->
%   track.runTracker -> track.discriminator); NOT part of the active runtime.
%
%   Feature-matched synthesis is now the SOLE active path --
%   agent.buildEnvWithFeatures no longer accepts a synthesisMode argument
%   (see CLAUDE.md's "Directory Map & Status"). This file preserves the
%   ORIGINAL dual-mode comparison that measured the reported
%   confirmation-rate delta (0% generic -> 100% feature-matched,
%   R=1800m/actionIdx=6/interceptNoiseAmp=2.0, N=10 episodes) via a FROZEN,
%   self-contained local copy of agent.buildEnvWithFeatures's OLD
%   'generic'|'featureMatched' switch -- deliberately NOT calling the active
%   agent.buildEnvWithFeatures for the 'generic' side, which can no longer
%   produce it.
%
%   Moved here (from tests/test_feature_integration.m's test 4) and adapted
%   after synthesisMode was removed as a caller-facing option. NOT
%   auto-discovered by runAllTests.m (TestSuite.fromFolder(tests/) is
%   non-recursive by default) -- run directly:
%       runtests('tests/historical_baseline')

    methods (Test)
        function test_confirmation_rate_generic_vs_feature_matched_frozen(tc)
            C = physics.Constants();
            actionIdx = 6;   % closing delta + a gain level, arbitrary but fixed for both modes
            numEpisodes = 10;

            genericRate = tc.localRunEpisodesFrozen('generic', C, actionIdx, numEpisodes);
            featureMatchedRate = tc.localRunEpisodesFrozen('featureMatched', C, actionIdx, numEpisodes);

            fprintf('[historical_baseline] Confirmation rate over %d episodes: generic=%.0f%% feature-matched=%.0f%%\n', ...
                numEpisodes, genericRate*100, featureMatchedRate*100);

            tc.verifyGreaterThan(featureMatchedRate, genericRate, ...
                ['Feature-matched synthesis should confirm more often than generic replay ' ...
                 'at this noise level (frozen historical comparison).']);
        end
    end

    methods (Access = private)
        function rate = localRunEpisodesFrozen(tc, synthesisMode, C, actionIdx, numEpisodes)
            env = tc.buildEnvWithFeaturesFrozen(C, synthesisMode);
            confirmedCount = 0;
            for ep = 1:numEpisodes
                rng(1000 + ep);
                reset(env);
                info = struct('confirmedCount', 0, 'eccmLabel', "");
                for k = 1:8
                    [~, ~, ~, info] = step(env, actionIdx);
                end
                confirmedCount = confirmedCount + double(info.confirmedCount >= 1);
            end
            rate = confirmedCount / numEpisodes;
        end

        function env = buildEnvWithFeaturesFrozen(tc, C, synthesisMode)
        %BUILDENVWITHFEATURESFROZEN  Frozen copy of +agent/buildEnvWithFeatures.m
        %   exactly as it was BEFORE the "sole active pipeline" mission removed
        %   its synthesisMode switch -- verbatim except for being a private
        %   method here instead of a package function.
            obsInfo = rlNumericSpec([3 1], 'Name', 'obs');
            obsInfo.LowerLimit = [0; 0; 0];
            obsInfo.UpperLimit = [1; 1; 1];

            numDeltas = 5;
            numGains  = 9;
            actInfo = rlFiniteSetSpec(1:(numDeltas*numGains));
            actInfo.Name = 'drfm_action';

            pulseWidthS = 12e-6;
            sweepBandwidthHz = 2e6;
            wav = phased.LinearFMWaveform('SampleRate', C.fs, ...
                    'PulseWidth', pulseWidthS, 'PRF', 50e3, 'SweepBandwidth', sweepBandwidthHz);
            pulse = wav();
            bufferLen = 400;

            activeLen = numel(getMatchedFilter(wav));
            activePulse = pulse(1:activeLen);

            interceptNoiseAmp = 2.0;
            rngIntercept = RandStream('mt19937ar', 'Seed', 12345);
            interceptNoise = interceptNoiseAmp * ...
                (randn(rngIntercept, size(activePulse)) + 1i*randn(rngIntercept, size(activePulse))) / sqrt(2);
            xIntercepted = activePulse + interceptNoise;

            switch synthesisMode
                case 'generic'
                    txPulse = xIntercepted;    % verbatim replay -- carries the intercept noise forward
                case 'featureMatched'
                    nominal.chirp_rate_hz_s = sweepBandwidthHz / pulseWidthS;
                    nominal.n_samples = numel(xIntercepted);
                    wp = features.characterizeInterceptDechirp(xIntercepted, C.fs, nominal);
                    txPulse = features.coherentReplica(wp, C.fs, numel(xIntercepted));
                otherwise
                    error('synthesisMode must be ''generic'' or ''featureMatched'', got ''%s''.', synthesisMode);
            end
            xTemplate = [txPulse; zeros(bufferLen - numel(txPulse), 1)];

            deltaOptionsM = linspace(-120, 120, numDeltas);
            gainOptions   = linspace(0.5, 4.5, numGains);
            F = 8; dt = 1.0;
            R0 = 1800;

            env = rlFunctionEnv(obsInfo, actInfo, ...
                @(action, logged) tc.frozenLocalStep(action, logged, C, wav, xTemplate, bufferLen, ...
                                             deltaOptionsM, gainOptions, F, dt), ...
                @() tc.frozenLocalReset(R0));
        end

        function [obs, logged] = frozenLocalReset(tc, R0) %#ok<INUSL>
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

        function [obs, reward, isDone, logged] = frozenLocalStep(tc, action, logged, C, wav, xTemplate, ...
                bufferLen, deltaOptionsM, gainOptions, F, dt) %#ok<INUSL>
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

            obs = [logged.k/F; newRange/3000; double(detected)];
        end
    end
end
