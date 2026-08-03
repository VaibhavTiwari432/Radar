function out = drfmLatency(nSeeds)
%DRFMLATENCY  Tier 2.1 -- can leading-edge tracking see a DRFM's processing
%   latency at this radar's bandwidth? Measured, at several bandwidths, so
%   the answer is a boundary rather than an opinion.
%
%   out = experiments.drfmLatency(nSeeds)     % default 20
%
%   THE MECHANISM BEING TESTED. A DRFM repeater must receive a pulse before
%   it can retransmit one, so its copy is late by the repeater's own
%   processing latency (10-100 ns is the figure quoted for fielded hardware).
%   A radar tracking the LEADING EDGE rather than the matched-filter peak
%   should therefore see the genuine skin return first and reject the copy.
%
%   THE PREDICTION, DERIVED BEFORE MEASURING (radar.leadingEdge's header):
%   an edge cannot be located finer than the rise time ~ 1/B, which is
%   500 ns = 74.95 m at this radar's 2 MHz. A 100 ns latency is 15.0 m --
%   5x smaller. So the screen should be INERT here and should come alive
%   somewhere near B ~ 1/tau. This sweeps B to find that crossing rather
%   than asserting it.

    if nargin < 1 || isempty(nSeeds); nSeeds = 20; end
    C = physics.Constants();

    latenciesNs = [0 10 50 100 500 1000];
    bandwidthsHz = [2e6 10e6 50e6];      % this radar, 5x, 25x
    R0 = 1800; pw = 12e-6;
    % The window must hold the pulse at whatever fs the bandwidth demands
    % (12 us at 4*50 MHz is 2400 samples), so it is derived per bandwidth
    % rather than fixed at this project's 400.
    nFastFor = @(B) round(pw * max(physics.Constants().fs, 4*B)) * 3;

    fprintf('\n=== 2.1 DRFM LATENCY vs LEADING-EDGE RESOLUTION, %d seeds ===\n', nSeeds);
    fprintf('one sample = %.1f ns = %.2f m | latency->range = c*tau/2\n', ...
        1e9/C.fs, C.range_per_sample);

    out = struct('bandwidthHz', {}, 'latencyNs', {}, 'edgeShiftM', {}, ...
                 'edgeNoiseM', {}, 'detectable', {}, 'riseTimeM', {});

    for B = bandwidthsHz
        riseM = C.c / (2 * B);
        fprintf('\nB = %5.1f MHz | rise time 1/B = %6.1f ns = %7.2f m\n', ...
            B/1e6, 1e9/B, riseM);
        fprintf('  %10s %12s %12s %12s %s\n', 'latency ns', 'true dR m', ...
            'edge shift m', 'edge noise m', 'detectable');

        % Baseline edge estimate at zero latency, and its seed-to-seed
        % scatter -- the noise floor any shift has to clear.
        base = zeros(1, nSeeds);
        for s = 1:nSeeds
            base(s) = localEdge(R0, 0, B, pw, nFastFor(B), C, s);
        end
        edgeNoise = std(base);

        for latNs = latenciesNs
            est = zeros(1, nSeeds);
            for s = 1:nSeeds
                est(s) = localEdge(R0, latNs*1e-9, B, pw, nFastFor(B), C, s);
            end
            shift = mean(est) - mean(base);
            trueDR = C.c * latNs*1e-9 / 2;
            % Detectable if the mean shift clears 3 sigma of the estimator's
            % own scatter -- the same "clears its own noise" rule the
            % co-bearing screen uses, not a tuned threshold.
            det = abs(shift) > 3 * max(edgeNoise, eps);
            fprintf('  %10d %12.2f %12.2f %12.3f %s\n', latNs, trueDR, shift, ...
                edgeNoise, string(det));
            out(end+1) = struct('bandwidthHz', B, 'latencyNs', latNs, ...
                'edgeShiftM', shift, 'edgeNoiseM', edgeNoise, ...
                'detectable', det, 'riseTimeM', riseM); %#ok<AGROW>
        end
    end

    % ==================== THE OPERATIONAL CASE ====================
    % Everything above measures a shift against a KNOWN zero-latency baseline
    % of the same target, which a real radar does not have -- it does not
    % independently know the target's range. The question a radar CAN ask is:
    % with the skin return and the repeater's delayed copy BOTH in the dwell,
    % does the leading edge still land on the skin return? That is
    % resolution-limited, not precision-limited, and it is what decides
    % whether leading-edge tracking is a usable counter.
    % ---- READ THIS BEFORE QUOTING ANY 2.1b NUMBER --------------------------
    % THE TWO-RETURN RESULT BELOW IS NOT ESTABLISHED, AND THE ARITHMETIC SAYS
    % IT CANNOT BE AT THIS J/S. The repeat is 20 dB stronger than the skin
    % return. An UNWINDOWED LFM's matched-filter response has a first range
    % sidelobe at -13.2 dB. So the repeat's own sidelobes sit
    %
    %       20.0 - 13.2 = +6.8 dB ABOVE the skin return
    %
    % i.e. the skin return is buried inside the repeat's sidelobe structure
    % and is not present as a distinguishable feature in the compressed
    % profile at all. No leading-edge threshold strategy can recover a return
    % that the waveform's own sidelobes have masked -- and that is exactly
    % what the erratic column below shows: the edge estimate lands on
    % different parts of the sidelobe skirt from cell to cell (2 MHz/1000 ns
    % gives 45 m, 2 MHz/2000 ns gives 391 m against a true 300 m), which is
    % scatter about the sidelobe structure, not a measurement of the skin
    % return.
    %
    % WHAT WOULD MAKE IT MEASURABLE, stated as the actionable result:
    % sidelobe suppression must exceed the J/S ratio. A Hamming-weighted
    % matched filter reaches -42 dB, which clears a 20 dB repeat by 22 dB.
    % Amplitude weighting costs ~1.3 dB of SNR and broadens the mainlobe by
    % ~50% -- a real trade, and one this project has never made. Until it is
    % made, leading-edge tracking is not a usable counter here.
    %
    % Reported rather than deleted, because the negative is the finding.
    fprintf('\n=== 2.1b TWO-RETURN CASE (skin + delayed repeat, same dwell) ===\n');
    fprintf('*** NOT ESTABLISHED: repeat sidelobes (-13.2 dB) sit +6.8 dB ABOVE\n');
    fprintf('*** the skin return at 20 dB J/S. The column below is sidelobe\n');
    fprintf('*** scatter, not a skin-return measurement. See header.\n');
    fprintf('The repeat is 20 dB STRONGER, which is the whole point of a repeater:\n');
    fprintf('the peak follows the repeat; only the EDGE can still find the skin.\n');
    fprintf('  %8s %10s %12s %14s %14s %s\n', 'B MHz', 'latency ns', 'separation m', ...
        'peak err m', 'edge err m', 'edge wins');
    for B = bandwidthsHz
        for latNs = [100 500 1000 2000]
            pErr = zeros(1, nSeeds); eErr = zeros(1, nSeeds);
            for s = 1:nSeeds
                [pErr(s), eErr(s)] = localTwoReturn(R0, latNs*1e-9, B, pw, ...
                                        nFastFor(B), C, s);
            end
            sep = C.c * latNs*1e-9 / 2;
            wins = mean(abs(eErr)) < mean(abs(pErr));
            fprintf('  %8.1f %10d %12.2f %14.2f %14.2f %s\n', B/1e6, latNs, sep, ...
                mean(abs(pErr)), mean(abs(eErr)), string(wins));
            out(end+1) = struct('bandwidthHz', B, 'latencyNs', -latNs, ...
                'edgeShiftM', mean(abs(eErr)), 'edgeNoiseM', mean(abs(pErr)), ...
                'detectable', wins, 'riseTimeM', C.c/(2*B)); %#ok<AGROW>
        end
    end

    fprintf('\n=== 2.1 BOUNDARY ===\n');
    for B = bandwidthsHz
        sel = out([out.bandwidthHz] == B & [out.latencyNs] > 0);
        d = find([sel.detectable], 1, 'first');
        if isempty(d)
            fprintf('  B = %5.1f MHz : NO tested latency (10-1000 ns) is detectable\n', B/1e6);
        else
            fprintf('  B = %5.1f MHz : smallest detectable latency = %d ns (%.2f m)\n', ...
                B/1e6, sel(d).latencyNs, C.c*sel(d).latencyNs*1e-9/2);
        end
    end
end

% ------------------------------------------------------------------------
function [peakErrM, edgeErrM] = localTwoReturn(R0, latencyS, B, pw, nFast, C, seed)
%LOCALTWORETURN  Skin return AND the repeater's delayed copy in one dwell.
%   Returns each estimator's error against the SKIN return's true range --
%   the quantity a tracker actually wants. The repeat is 20 dB stronger,
%   which is what a repeater is for; the matched-filter peak therefore
%   follows the repeat, and the only way to stay on the skin return is to
%   track the leading edge.
    fs = max(C.fs, 4*B);
    Cb = C; Cb.fs = fs; Cb.range_per_sample = C.c / (2*fs);
    C = Cb;

    rs = RandStream('twister', 'Seed', 5000 + seed);
    wav = phased.LinearFMWaveform('SampleRate', C.fs, 'PulseWidth', pw, ...
              'PRF', C.PRF, 'SweepBandwidth', B);
    pulse = wav();
    activeLen = numel(getMatchedFilter(wav));
    p = pulse(1:activeLen);

    n = (0:nFast-1)';
    rx = complex(zeros(nFast, 1));
    REPEAT_GAIN = 10;                       % 20 dB in power
    for i = 1:activeLen
        rx = rx + p(i) * sinc(n - (2*R0/C.c*C.fs + (i-1)));
        rx = rx + REPEAT_GAIN * p(i) * sinc(n - ((2*R0/C.c + latencyS)*C.fs + (i-1)));
    end
    rx = rx + 0.05*(randn(rs, nFast, 1) + 1i*randn(rs, nFast, 1))/sqrt(2);

    compressed = radar.pulseCompress(rx, wav);

    % ORIGIN IS CALIBRATED, NOT ASSUMED. A first version subtracted an
    % analytic (activeLen-1) group delay and produced errors of ~1700 m
    % against an 1800 m target -- i.e. it was measuring the offset, not the
    % estimators. Running the SAME chain on a skin-only return at the same
    % range gives the reference each estimator would report for a target with
    % no repeater present, so both errors below are differences within one
    % convention and no alignment has to be known.
    ref = complex(zeros(nFast, 1));
    for i = 1:activeLen
        ref = ref + p(i) * sinc(n - (2*R0/C.c*C.fs + (i-1)));
    end
    refC = radar.pulseCompress(ref, wav);
    [~, refPk] = max(abs(refC));
    refPeakM = (refPk - 1) * C.range_per_sample;

    % Noise floor estimated FROM THE PROFILE, robustly (median absolute
    % deviation scaling), the way a real detector would -- not passed in from
    % the generator, which the radar has no access to.
    sig = 1.4826 * median(abs(compressed));
    refEdgeM = radar.leadingEdge(refC, C, 'NoiseSigma', 1.4826*median(abs(refC)));

    [~, pkBin] = max(abs(compressed));
    peakErrM = (pkBin - 1) * C.range_per_sample - refPeakM;
    edgeErrM = radar.leadingEdge(compressed, C, 'NoiseSigma', sig) - refEdgeM;
end

% ------------------------------------------------------------------------
function edgeM = localEdge(R0, latencyS, B, pw, nFast, C, seed)
%LOCALEDGE  One noisy realisation: place a return at R0 delayed by latencyS,
%   pulse-compress, and estimate its leading edge.
%
%   THE SAMPLE RATE MUST SCALE WITH THE BANDWIDTH, and a first version of
%   this file got that wrong in a way that silently invalidated the whole
%   sweep. Holding fs at this project's 3.2 MHz while sweeping B to 50 MHz
%   does not simulate a wideband radar -- it simulates a grossly aliased one.
%   Nyquist here is 1.6 MHz, so even the project's own 2 MHz waveform already
%   folds (the same limit tests/test_feature_integration.m documents for the
%   blind characteriser). All three "bandwidths" collapsed to the same
%   effective one, which is exactly what the first run showed: an edge shift
%   of ~25 m at 50 ns regardless of B, and 4x larger than the true 7.49 m
%   offset. Oversampling at 4B is the fix; range_per_sample follows fs, so
%   the local constants are rebuilt per bandwidth rather than inherited.
    fs = max(C.fs, 4*B);
    Cb = C; Cb.fs = fs; Cb.range_per_sample = C.c / (2*fs);
    C = Cb;

    rs = RandStream('twister', 'Seed', 4000 + seed);
    wav = phased.LinearFMWaveform('SampleRate', C.fs, 'PulseWidth', pw, ...
              'PRF', C.PRF, 'SweepBandwidth', B);
    pulse = wav();
    activeLen = numel(getMatchedFilter(wav));
    p = pulse(1:activeLen);

    % Fractional-sample delay: the whole point is a SUB-SAMPLE shift, so an
    % integer round() would quantise the effect away before it is measured.
    tau = 2*R0/C.c + latencyS;
    dSamples = tau * C.fs;
    n = (0:nFast-1)';
    rx = complex(zeros(nFast, 1));
    % Band-limited (sinc) interpolation of the delayed pulse onto the grid.
    for i = 1:activeLen
        centre = dSamples + (i-1);
        rx = rx + p(i) * sinc(n - centre);
    end
    rx = rx + 0.05*(randn(rs, nFast, 1) + 1i*randn(rs, nFast, 1))/sqrt(2);

    compressed = radar.pulseCompress(rx, wav);
    edgeM = radar.leadingEdge(compressed, C);
end
