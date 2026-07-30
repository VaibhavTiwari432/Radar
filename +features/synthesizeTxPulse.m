function [txPulse, degradedEvent] = synthesizeTxPulse(cleanChirp, fs, nominalChirpRateHzS, ...
        interceptNoiseAmp, rng, frameIdx)
%SYNTHESIZETXPULSE  THE single entry point for synthesis: intercept the
%   radar's own pulse (add receiver noise), characterize it, and return a
%   clean coherent replica. Feature-matched synthesis is the ONLY path a
%   caller selects -- there is no generic/verbatim mode to opt into. This
%   function's OWN internal safety net falls back to a raw noisy replay,
%   and ONLY when characterization fails structurally (aliasingMargin<=0:
%   the residual itself exceeded Nyquist even after dechirping against the
%   known nominal rate) -- not merely when confidence is low from ordinary
%   noise, which shrinkage already handles (see
%   characterizeInterceptDechirp's comments).
%
%   [txPulse, degradedEvent] = features.synthesizeTxPulse(cleanChirp, fs, ...
%       nominalChirpRateHzS, interceptNoiseAmp, rng, frameIdx)
%       rng           : a RandStream (so callers control reproducibility
%                       the same way MATLAB's randn(rngStream,...) does)
%       frameIdx      : logged into degradedEvent for visibility, not used
%                       otherwise
%       degradedEvent : [] (empty) when the fallback did NOT fire, or a
%                       struct with frame/reason/confidence when it did --
%                       callers MUST surface this, not swallow it.
%
%   Direct MATLAB port of cogengine.features.synthesize_tx_pulse (Python).
%
%   Honest limitation (checked empirically in the Python port, carries
%   over here unchanged): aliasingMargin is a WEAK discriminator between
%   "correct nominal, bad noise draw" and "genuinely wrong nominal" --
%   swept thresholds and found both cases fire at nearly the same rate at
%   every threshold tested. The strictest threshold (<=0, residual
%   literally at/past Nyquist) is used because it stays near-zero on
%   validated canonical scenes; it is a crash-prevention safety net for
%   the most extreme cases, not a reliable "is my known-radar assumption
%   wrong" detector.

    n = numel(cleanChirp);
    if interceptNoiseAmp <= 0
        txPulse = cleanChirp;
        degradedEvent = [];
        return;
    end

    noise = interceptNoiseAmp * (randn(rng, n, 1) + 1i*randn(rng, n, 1)) / sqrt(2);
    noisyIntercept = cleanChirp(:) + noise;

    nominal.chirp_rate_hz_s = nominalChirpRateHzS;
    nominal.n_samples = n;
    wp = features.characterizeInterceptDechirp(noisyIntercept, fs, nominal);

    if wp.aliasingMargin <= 0.0
        txPulse = noisyIntercept;
        degradedEvent = struct('frame', frameIdx, 'reason', 'residual_aliasing', ...
            'confidence', wp.confidence);
        return;
    end

    txPulse = features.coherentReplica(wp, fs, n);
    degradedEvent = [];
end
