function out = t9RealIntercept(nSamp, outDir)
%T9REALINTERCEPT  Does intercepting a REAL pulse instead of a synthetic chirp
%   move the synthesis closer to the real distribution? (POA Phase 3, T9)
%
%   out = experiments.t9RealIntercept(nSamp, outDir)
%
%   THE ANCHOR THIS MUST MOVE. benchmarkSuite reports the synthesized
%   transmit pulse sitting 0.8-0.9 sigma from the real RadChar distribution
%   in the project's own 54-D feature space (Wasserstein mean 0.902-0.941).
%   That pipeline characterises a SYNTHETIC chirp. RadChar-Tiny.h5 is local
%   and data.loadRadChar exists, so the intercept can be a real recorded
%   pulse instead. T9 asks whether that closes the gap.
%
%   NO CODE CHANGE WAS NEEDED IN +features. synthesizeTxPulse takes whatever
%   it is handed as the intercepted signal, so "intercept a real pulse" is a
%   CALLER choice, not a new capability. This is therefore a measurement,
%   not a build.
%
%   THREE ARMS, all scored against the same held-out real pulses:
%     A synthetic  intercept an ideal LFM chirp        (the current pipeline)
%     B real       intercept a REAL RadChar LFM record (T9's proposal)
%     C verbatim   the real record with NO characterisation at all
%
%   Arm C is the control that keeps this honest. BENCHMARK_RESULTS.md already
%   establishes that verbatim replay of a real pulse is a WEAK CFAR statistic
%   -- 6-15x matched-filter peak loss, 5-14x range smearing -- so if arm B
%   only wins by drifting toward arm C, it has bought distributional realism
%   with detectability, which is a trade and not an improvement. Both are
%   reported.
%
%   RMS NORMALISATION IS NOT OPTIONAL (benchmarkSuite method error M3): raw
%   RadChar record RMS spans 1.5x-9.8x the ideal chirp's WITHIN one class, so
%   unnormalised inputs measure loudness rather than waveform structure.
%
%   NO SELF-VERIFICATION (CLAUDE.md Rule 2): this scores signals against a
%   dataset. It never asks +radar or +track whether anything was detected.

    if nargin < 1 || isempty(nSamp);  nSamp  = 40; end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    if nargin < 2 || isempty(outDir); outDir = fullfile(root, 'results'); end

    C   = physics.Constants();
    cfg = struct('fs', 3.2e6, 'pulseWidth', 12e-6, 'bandwidth', 2e6, ...
                 'interceptNoise', 2.0);
    nominalK = cfg.bandwidth / cfg.pulseWidth;
    pfb = features.buildChannelizer();

    D = data.loadRadChar(fullfile(root, 'data', 'RadChar-Tiny.h5'));
    lfm = find(D.signal_type == 4);
    assert(numel(lfm) >= 3*nSamp, 't9:tooFewLFM', ...
        'need %d LFM records for disjoint intercept/reference sets, have %d', ...
        3*nSamp, numel(lfm));

    % Disjoint draws: the pulses used AS intercepts must not also be the
    % reference distribution, or arm B is scored against its own inputs.
    rs   = RandStream('twister', 'Seed', 31337);
    perm = lfm(randperm(rs, numel(lfm), 2*nSamp));
    interceptIdx = perm(1:nSamp);
    referenceIdx = perm(nSamp+1:end);

    n = round(cfg.pulseWidth * C.fs);
    t = (0:n-1)' / C.fs;
    cleanChirp = exp(1i * pi * nominalK * t.^2);

    A = zeros(nSamp, 54); B = zeros(nSamp, 54);
    Cv = zeros(nSamp, 54); R = zeros(nSamp, 54);
    degradedA = 0; degradedB = 0;
    for i = 1:nSamp
        realPulse = localUnitRms(localExtract(D, interceptIdx(i), cfg.fs, n));

        [txA, evA] = features.synthesizeTxPulse(cleanChirp, C.fs, nominalK, ...
                        cfg.interceptNoise, rs, i);
        [txB, evB] = features.synthesizeTxPulse(realPulse, C.fs, nominalK, ...
                        cfg.interceptNoise, rs, i);
        degradedA = degradedA + ~isempty(evA);
        degradedB = degradedB + ~isempty(evB);

        A(i,:)  = features.featureVector(txA, pfb).';
        B(i,:)  = features.featureVector(txB, pfb).';
        Cv(i,:) = features.featureVector(realPulse, pfb).';
        R(i,:)  = features.featureVector( ...
                    localUnitRms(localExtract(D, referenceIdx(i), cfg.fs, n)), pfb).';
    end

    out = struct();
    out.synthetic = localWasserstein(A,  R);
    out.realInt   = localWasserstein(B,  R);
    out.verbatim  = localWasserstein(Cv, R);
    out.degraded_synthetic = degradedA;
    out.degraded_real      = degradedB;
    out.n_samples = nSamp;

    fprintf('\nT9 -- Wasserstein to held-out REAL RadChar LFM (54-D, std-normalised, n=%d)\n', nSamp);
    fprintf('  A synthetic intercept  mean %.3f  median %.3f  max %.3f   (fallback fired %d/%d)\n', ...
        out.synthetic.mean, out.synthetic.median, out.synthetic.max, degradedA, nSamp);
    fprintf('  B REAL intercept       mean %.3f  median %.3f  max %.3f   (fallback fired %d/%d)\n', ...
        out.realInt.mean, out.realInt.median, out.realInt.max, degradedB, nSamp);
    fprintf('  C verbatim (control)   mean %.3f  median %.3f  max %.3f\n', ...
        out.verbatim.mean, out.verbatim.median, out.verbatim.max);
    fprintf('  delta B-A %+.3f   (negative = real intercept is closer to real)\n', ...
        out.realInt.mean - out.synthetic.mean);

    f = fullfile(outDir, 't9_real_intercept.mat');
    save(f, '-struct', 'out');
    fprintf('saved -> %s\n', f);
end

% ------------------------------------------------------------------------
function W = localWasserstein(X, Y)
%LOCALWASSERSTEIN  Per-dimension 1-D Wasserstein, std-normalised so the 54
%   dimensions are comparable. Same protocol as benchmarkSuite's
%   wassersteinToRadChar, deliberately, so the numbers can be read together.
    qs = linspace(0, 1, 51);
    wd = zeros(1, size(X,2));
    for d = 1:size(X,2)
        a = quantile(X(:,d), qs); b = quantile(Y(:,d), qs);
        sc = max(std([X(:,d); Y(:,d)]), 1e-12);
        wd(d) = mean(abs(a-b)) / sc;
    end
    W = struct('per_dim', wd, 'mean', mean(wd), ...
               'median', median(wd), 'max', max(wd));
end

function y = localExtract(D, idx, fs, n)
%LOCALEXTRACT  The PULSE inside one RadChar record, trimmed/padded to n.
%
%   Slices using the record's OWN time_delay and pulse_width labels, the
%   same way benchmarkSuite's extractPulse does. This is not a detail: a
%   RadChar record is 512 samples and the pulse starts at its labelled time
%   delay, so taking the first n samples blindly returns mostly PRE-PULSE
%   NOISE. The first version of this file did exactly that, which made arm B
%   a measurement of noise rather than of a real pulse.
    a = max(1, round(D.time_delay(idx)*fs) + 1);
    L = max(1, round(D.pulse_width(idx)*fs));
    x = D.iq(:, idx);
    y = x(a : min(numel(x), a+L-1));
    % Length-match to the synthetic arm so the 54-D comparison is fair.
    y = y(:);
    if numel(y) >= n; y = y(1:n); else; y = [y; zeros(n-numel(y),1)]; end
end

function y = localUnitRms(x)
%LOCALUNITRMS  Raw RadChar record RMS spans 1.5x-9.8x the ideal chirp WITHIN
%   one class (benchmarkSuite M3). Without this the comparison measures
%   loudness, not waveform structure.
    y = x / max(rms(x), eps);
end
