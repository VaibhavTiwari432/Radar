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
