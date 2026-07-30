function params = characterizeInterceptDechirp(iq, fs, nominal)
%CHARACTERIZEINTERCEPTDECHIRP  Nyquist-safe chirp characterization by
%   dechirping against a KNOWN nominal waveform, then estimating the
%   (small, slowly-varying) residual -- instead of blind phase-differencing
%   on the raw intercept, which aliases whenever the TRUE instantaneous
%   frequency exceeds fs/2 (a hard Nyquist limit, not something a cleverer
%   blind estimator can work around: see Integration_Report.md's
%   "project waveform" finding, features.characterizeIntercept).
%
%   params = features.characterizeInterceptDechirp(iq, fs, nominal)
%       nominal : struct with fields chirp_rate_hz_s, n_samples -- the
%                 EXPECTED/nominal chirp rate and pulse length. Consistent
%                 with this project's core Phase 2 premise (design doc
%                 Part 1: "the mother drone knows the radar" -- its
%                 structure and nominal parameters): characterization here
%                 refines THIS FRAME's actual pulse against a known prior,
%                 rather than blind-estimating a fast sweep from scratch.
%
%   Method: multiply iq by the conjugate of the nominal reference chirp
%   (removing the KNOWN fast sweep). If the actual chirp rate is close to
%   nominal, the residual sweeps at only (k_true - k_nominal) -- much
%   slower, safely within Nyquist even when the raw signal was not.
%   Ordinary phase-differencing (features.characterizeIntercept's method)
%   then recovers that small residual rate reliably, and
%   k_est = k_nominal + delta_k_est.
%
%   Same output shape/fields as features.characterizeIntercept, so it
%   drops into features.coherentReplica unchanged.
%
%   Sweep-DIRECTION (sign) ambiguity: tries the nominal rate at BOTH signs
%   and keeps whichever gives the higher quality (Integration_Report.md's
%   own flagged-but-not-built extension: "confirming sweep direction (try
%   both signs, keep the higher-confidence one)"). Necessary, not
%   theoretical -- verified directly: a wrong-SIGN nominal (same magnitude,
%   true rate = -nominal) gave aliasingMargin=0.0091, JUST above
%   synthesizeTxPulse.m's aliasingMargin<=0 fallback gate, so the OLD
%   single-sign version would silently commit to a wrong-signed
%   chirp_rate_hz_s estimate instead of either correcting itself or
%   triggering the documented fallback -- a real silent failure (Rule 7),
%   not a hypothetical one. Trying the correct sign's nominal against
%   itself is unaffected (the wrong-sign alternative scores far lower, so
%   the correct one is still selected) -- this is additive robustness, not
%   a behavior change for the already-validated correctly-signed case.
%   params.sign_used (+1 or -1, relative to the CALLER-supplied nominal
%   sign) is exposed so a caller wanting to audit "did the known-nominal
%   prior's sign ever get overridden" can still observe it -- not fully
%   silent even though the correction itself is automatic.

    iq = iq(:);
    n = numel(iq);

    [paramsPos, qualityPos] = localDechirpOneSign(iq, fs, nominal.chirp_rate_hz_s, n);
    [paramsNeg, qualityNeg] = localDechirpOneSign(iq, fs, -nominal.chirp_rate_hz_s, n);
    if qualityPos >= qualityNeg
        params = paramsPos; params.sign_used = 1;
    else
        params = paramsNeg; params.sign_used = -1;
    end

    % Spectral centroid/bandwidth and pulse width are NOT chirp-rate
    % dependent in the same aliasing-prone way (they're magnitude-domain,
    % not phase-unwrap-domain), so reuse the same helpers as the blind
    % estimator for those -- only the chirp-rate/classification step needed
    % the dechirp fix.
    [centroid, bw] = localSpectralFeatures(iq, fs);
    pw = localEstimatePulseWidth(iq, fs);

    % Classification DEFAULTS to the known nominal class ('lfm', since the
    % caller supplied a nominal LFM chirp rate to dechirp against) rather
    % than re-deciding from scratch every frame. Falling back to a
    % completely different waveform class (tone/coded) when confidence is
    % merely LOW due to intercept noise -- not because the signal is
    % actually a different waveform -- was verified to make things WORSE:
    % it discards the chirp structure exactly when denoising would help
    % most (high noise). The known-radar assumption is the whole point of
    % Phase 2; use it here too.
    wclass = 'lfm';

    params.wclass = wclass;
    params.f0_hz = centroid;
    params.bandwidth_hz = bw;
    params.pulse_width_s = pw;
    params.n_samples = n;
    % params.chirp_rate_hz_s, params.confidence, params.aliasingMargin
    % already set by localDechirpOneSign (see header comment for their
    % semantics -- aliasingMargin<=0 is features.synthesizeTxPulse's
    % structural-failure fallback gate, confidence is NOT a safe trigger
    % on its own since it legitimately reads near 0 under ordinary noise).
end

% ------------------------------------------------------------------------
function [params, quality] = localDechirpOneSign(iq, fs, chirpRateHzS, n)
%LOCALDECHIRPONESIGN  The dechirp/estimate/confidence math for ONE candidate
%   sign of the nominal chirp rate. Returns just the sign-dependent fields
%   (chirp_rate_hz_s, confidence, aliasingMargin) plus quality (used by the
%   caller to pick between +/- sign candidates) -- the sign-independent
%   fields (wclass, spectral features, pulse width, n_samples) are added by
%   the caller once, after a sign is chosen.
    t = (0:n-1)' / fs;
    refChirp = exp(1i * pi * chirpRateHzS * t.^2);
    residual = iq .* conj(refChirp);

    ph = unwrap(angle(residual));
    fInstResidual = diff(ph) / (2*pi) * fs;
    tFit = t(1:end-1);
    A = [tFit, ones(numel(tFit),1)];
    coeffs = A \ fInstResidual;
    deltaK = coeffs(1);

    % Confidence = "how small is the residual deviation relative to
    % Nyquist" -- NOT "how linear is the residual" (features.characterizeIntercept's
    % metric). A GOOD dechirp match makes the residual nearly flat (no
    % strong trend for a linear fit to explain), which the linearity metric
    % misreads as low confidence -- verified this the hard way: a perfect
    % dechirp (k_nominal == k_true) gave confidence=0 under that metric
    % despite the residual instantaneous frequency staying within +-15 kHz
    % of Nyquist's 1.6 MHz. This metric instead directly checks that the
    % dechirp didn't itself alias (which a badly-wrong nominal guess would
    % cause) and that the fit residual is small in absolute terms.
    nyquist = fs / 2;
    maxResidualFreq = max(abs(fInstResidual));
    fitResidualStd = std(fInstResidual - (deltaK*tFit + coeffs(2)));
    aliasingMargin = max(0, 1 - maxResidualFreq / nyquist);
    fitTightness = max(0, 1 - fitResidualStd / (0.1 * nyquist));
    quality = max(0, min(1, min(aliasingMargin, fitTightness)));

    % Shrinkage toward the KNOWN nominal rate as confidence drops, rather
    % than an all-or-nothing accept/reject of the correction. At high
    % intercept noise, deltaK itself becomes unreliable -- but the
    % "known radar" premise (design doc Part 1) means k_nominal is already
    % a good prior, so a low-confidence frame should fall back TOWARD it,
    % not discard the chirp structure entirely.
    kEst = chirpRateHzS + quality * deltaK;

    params.chirp_rate_hz_s = kEst;
    params.confidence = quality;
    params.aliasingMargin = aliasingMargin;
end

% ------------------------------------------------------------------------
function [centroid, bw] = localSpectralFeatures(iq, fs)
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
    thresh = 0.1;
    env = abs(iq);
    m = env > thresh * (max(env) + 1e-12);
    pw = sum(m) / fs;
end
