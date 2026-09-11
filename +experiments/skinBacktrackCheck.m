function results = skinBacktrackCheck(varargin)
%SKINBACKTRACKCHECK  Does the drones' OWN skin echo expose the swarm? (Track A, SIM)
%
%   results = experiments.skinBacktrackCheck('Name', value, ...)
%
%   N drones sit OUTSIDE the blind range, each at its own bearing and cross
%   speed, each reflecting the radar's pulse (a skin echo of PlatformRcs) and
%   radiating one phantom beyond the whole swarm from its own aperture -- so
%   the phantom's bearing series is its drone's. +track/skinBacktrack.m looks
%   for (nearer, farther) pairs sharing a bearing series. Three arms, all with
%   the SAME 2N ranges, rates and received powers, row for row, so detection
%   is common and only the bearing structure differs:
%     'swarm'     far i carries near i's bearing series (the repeater)
%     'genuine'   every far object at its own bearing, own motion
%     'trailing'  far i starts exactly behind near i with the same linear
%                 cross speed -- same bearing, different angular rate. The
%                 counter's hard case (D3).
%   Predictions D1-D5 in SWARM_PREDICTIONS.md were committed before this ran.
%
%   Skin echoes are rendered as ordinary rows: a reflection at range R with
%   RCS sigma is exactly what render.m draws for a row (amplitude from the
%   radar equation, phase from range), and build_scene's own platform skin
%   path supports only one platform.

    p = inputParser;
    p.addParameter('N', 4);
    p.addParameter('PlatformRcs', [1.0 0.1 0.01]);   % drone skin RCS [m^2]
    p.addParameter('NumSeeds', 10);
    p.addParameter('DroneStartM', 2000);             % clear of 1798.8 m blind range for the dwell
    p.addParameter('SpacingM', 1200);                % clears the CFAR window (1124 m)
    % Farthest drone -> first phantom. [] = SpacingM. Widen it to test whether a
    % strong phantom closing into the last drone's CFAR window masks its skin.
    p.addParameter('GapM', []);
    p.addParameter('DroneRateMps', -10);
    p.addParameter('PhantomRateMps', -35);
    p.addParameter('SpreadDeg', 2.0);
    p.parse(varargin{:});
    o = p.Results;

    N = o.N; t = 0:7;
    Rd = o.DroneStartM + o.SpacingM * (0:N-1);
    gap = o.GapM; if isempty(gap); gap = o.SpacingM; end
    Rp = Rd(end) + gap + o.SpacingM * (0:N-1);
    rates = [repmat(o.DroneRateMps, 1, N), repmat(o.PhantomRateMps, 1, N)];
    assert(max(Rp) + 50 < physics.Constants().R_unambiguous, 'far rows would fold');
    % ponytail: build_scene checks causality against ONE mother range, so it is
    % set below every row (1700 m) and the per-drone check is asserted here:
    % every phantom starts >1 km beyond every drone, far past c*1us/2 = 150 m.
    assert(min(Rp) - max(Rd) > 150, 'a phantom sits in front of its drone');

    s = deg2rad(o.SpreadDeg);
    b = linspace(-s/2, s/2, N)';                     % drone bearings
    v = linspace(-4.5, 4.5, N)';                     % drone cross speeds [m/s]
    c = b + s / (2*N);                               % genuine far bearings: between drones
    azNear = atan2(Rd' .* tan(b) + v .* t, Rd');

    fprintf('\n=== SKIN BACKTRACK CHECK [SIM] === N=%d, %d seeds, drones %g-%g m\n', ...
        N, o.NumSeeds, Rd(1), Rd(end));
    fprintf('%-9s %8s %10s %16s %10s %22s\n', 'arm', 'rcs', 'skin det', ...
        'far backtracked', 'to own', 'far real / flagged CI');
    results = struct('arm', {}, 'rcs', {}, 'skinByDrone', {}, 'skinDetected', {},'farBacktracked', {}, ...
        'toOwnDrone', {}, 'farReal', {}, 'k', {}, 'n', {}, 'ciLow', {}, 'ciHigh', {});

    for rcsSkin = o.PlatformRcs
        rcs = [repmat(rcsSkin, 1, N), (Rp / 2400).^4];   % far rows at equal received power
        for arm = ["swarm", "genuine", "trailing"]
            switch arm
                case "swarm";    azFar = azNear;
                case "genuine";  azFar = atan2(Rp' .* tan(c) - v .* t, Rp');
                case "trailing"; azFar = atan2(Rp' .* tan(b) + v .* t, Rp');
            end
            det = 0; k = 0; own = 0; real_ = 0; detByDrone = zeros(1, N);
            for seed = 1:o.NumSeeds
                rng(seed, 'twister');
                [jm, truth] = renderPhantomScene([Rd, Rp], rates, 'Rcs', rcs, ...
                    'MotherRangeM', 1700, 'NumFrames', 8, 'NumPulses', 32, ...
                    'SourceAzimuthRad', 0, 'PhantomAzimuthRad', [azNear; azFar], ...
                    'Tag', sprintf('skinbt_%s_r%g_g%d_%d', arm, rcsSkin, gap, seed));
                fb = engine.runJudge(jm);
                [verdict, d] = track.skinBacktrack(fb);
                row = localMatchRows(fb, truth);          % track -> truth row (0 = none)
                lbl = string(fb.track_label);
                det = det + nnz(ismember(1:N, row));
                detByDrone = detByDrone + ismember(1:N, row);
                for j = 1:N
                    tr = find(row == N + j, 1);
                    if isempty(tr); continue; end
                    real_ = real_ + (lbl(tr) == "real");
                    if verdict(tr) == "backtracked"
                        k = k + 1;
                        own = own + (row(d(tr).partner) == j);
                    end
                end
            end
            n = N * o.NumSeeds;
            [lo, hi] = localWilson(k, n);
            fprintf('%-9s %8.2g %6d/%-3d %12d/%-3d %6d %11d/%d [%.2f,%.2f]   skin by drone range: %s\n', ...
                arm, rcsSkin, det, n, k, n, own, real_, n, lo, hi, mat2str(detByDrone));
            results(end+1) = struct('arm', char(arm), 'rcs', rcsSkin, 'skinByDrone', detByDrone, ...
                'skinDetected', det / n, 'farBacktracked', k / n, 'toOwnDrone', own, ...
                'farReal', real_ / n, 'k', k, 'n', n, 'ciLow', lo, 'ciHigh', hi); %#ok<AGROW>
        end
    end
end


function row = localMatchRows(fb, truth)
%LOCALMATCHROWS  Each confirmed track -> the truth row within 3 range cells of
%   its mean range (rows are 1200 m apart, so this never picks the wrong one).
    rowMean = mean(truth.range_m, 2)';
    row = zeros(1, fb.confirmed_tracks);
    for i = 1:fb.confirmed_tracks
        [gap, r] = min(abs(rowMean - mean(fb.track_range_m{i})));
        if gap < 3 * physics.Constants().range_per_sample; row(i) = r; end
    end
end


function [lo, hi] = localWilson(k, n)
    z = 1.96; pHat = k / n; denom = 1 + z^2/n;
    center = (pHat + z^2/(2*n)) / denom;
    half = (z/denom) * sqrt(pHat*(1-pHat)/n + z^2/(4*n^2));
    lo = max(0, center - half); hi = min(1, center + half);
end
