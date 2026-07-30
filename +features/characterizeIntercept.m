function params = characterizeIntercept(iq, fs)
%CHARACTERIZEINTERCEPT  Estimate waveform parameters from an intercepted pulse.
%
%   params = features.characterizeIntercept(iq, fs) returns a struct:
%       wclass          - 'lfm' | 'coded' | 'tone'
%       f0_hz           - spectral centroid [Hz]
%       bandwidth_hz    - 90%-energy occupied bandwidth [Hz]
%       chirp_rate_hz_s - linear-fit instantaneous-frequency slope [Hz/s]
%       pulse_width_s   - energy-threshold pulse duration [s]
%       n_samples       - length(iq)
%       confidence      - IF-linearity fit quality in [0,1] (1 = confidently LFM)
%
%   Direct MATLAB port of cognitive_engine/cogengine/features.py's
%   estimate_waveform_params (that reference: 11/11 tests pass, chirp-rate
%   recovery exact to the value used in its own test, 13.07x measured
%   pulse-compression gain of a matched replica vs a generic copy -- see
%   Integration_Report.md for the MATLAB-side re-measurement).
%
%   Phase-based IF estimation assumes the pulse is critically sampled
%   (f_max < fs/2); a wideband chirp that aliases would need a spectrogram
%   instead (same caveat as the Python reference -- not handled here).
%
%   This is CHARACTERIZE, one of feature extraction's three synthesis uses
%   (the others are REPLICATE -- features.coherentReplica -- and MEASURE
%   REALISM -- features.featureDistance). See +agent/buildEnvWithFeatures.m
%   for where this plugs into the DRFM synthesis loop.

    iq = iq(:);
    [k, ~, quality] = localEstimateChirpRate(iq, fs);
    [centroid, bw] = localSpectralFeatures(iq, fs);
    pw = localEstimatePulseWidth(iq, fs);
    wclass = localClassifyWaveform(iq, k, quality);

    params.wclass = wclass;
    params.f0_hz = centroid;
    params.bandwidth_hz = bw;
    params.chirp_rate_hz_s = k;
    params.pulse_width_s = pw;
    params.n_samples = numel(iq);
    params.confidence = quality;
end

% ------------------------------------------------------------------------
function fInst = localInstantaneousFrequency(iq, fs)
%LOCALINSTANTANEOUSFREQUENCY  IF(t) from the phase derivative (Hz).
    ph = unwrap(angle(iq));
    fInst = diff(ph) / (2*pi) * fs;
end

% ------------------------------------------------------------------------
function [k, fStart, quality] = localEstimateChirpRate(iq, fs)
%LOCALESTIMATECHIRPRATE  Fit IF(t) = k*t + fStart by least squares.
    fInst = localInstantaneousFrequency(iq, fs);
    t = (0:numel(fInst)-1)' / fs;
    A = [t, ones(numel(t),1)];
    coeffs = A \ fInst;
    k = coeffs(1);
    fStart = coeffs(2);
    resid = std(fInst - (k*t + fStart));
    quality = max(0, min(1, 1 - resid / (std(fInst) + 1e-12)));
end

% ------------------------------------------------------------------------
function [centroid, bw] = localSpectralFeatures(iq, fs)
%LOCALSPECTRALFEATURES  Spectral centroid and 90%-energy occupied bandwidth.
    N = numel(iq);
    X = fftshift(fft(iq));
    k = (0:N-1)' - floor(N/2);
    f = (k / N) * fs;
    P = abs(X).^2;
    Psum = sum(P) + 1e-12;
    centroid = sum(f .* P) / Psum;
    cum = cumsum(P) / Psum;
    loIdx = find(cum >= 0.05, 1, 'first');
    hiIdx = find(cum >= 0.95, 1, 'first');
    bw = f(hiIdx) - f(loIdx);
end

% ------------------------------------------------------------------------
function pw = localEstimatePulseWidth(iq, fs)
%LOCALESTIMATEPULSEWIDTH  Energy-threshold pulse duration.
    thresh = 0.1;
    env = abs(iq);
    m = env > thresh * (max(env) + 1e-12);
    pw = sum(m) / fs;
end

% ------------------------------------------------------------------------
function wclass = localClassifyWaveform(iq, k, quality)
%LOCALCLASSIFYWAVEFORM  Coarse class from the IF law: linear sweep -> lfm;
%   phase jumps -> coded; otherwise -> tone.
    if abs(k) > 1e9 && quality > 0.6
        wclass = 'lfm';
        return;
    end
    ph = unwrap(angle(iq));
    if mean(abs(diff(ph)) > pi/2) > 0.05
        wclass = 'coded';
    else
        wclass = 'tone';
    end
end
