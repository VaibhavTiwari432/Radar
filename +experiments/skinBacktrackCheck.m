function results = skinBacktrackCheck(varargin)
%SKINBACKTRACKCHECK  Does the drones' OWN skin echo expose the swarm? (Track A, SIM)
%
%   results = experiments.skinBacktrackCheck('Name', value, ...)
%
%   N drones sit OUTSIDE the blind range, each at its own bearing and cross
%   speed, each reflecting the radar's pulse (a skin echo of PlatformRcs) and
%   radiating K phantoms beyond the whole swarm from its own aperture -- so
%   each phantom's bearing series is its drone's. +track/skinBacktrack.m looks
%   for (nearer, farther) pairs sharing a bearing series. Three arms, all with
%   the SAME ranges, rates and received powers, row for row, so detection
%   is common and only the bearing structure differs:
%     'swarm'     far phantom carries its drone's bearing series (the repeater)
%     'genuine'   every far object at its own bearing, own motion
%     'trailing'  far object starts exactly behind its drone with the same
%                 linear cross speed -- same bearing, different angular rate.
%                 The counter's hard case (D3).
%   Predictions D1-D5 (and S/M for the options below) in SWARM_PREDICTIONS.md
%   were committed before each run.
%
%   Skin echoes are rendered as ordinary rows: a reflection at range R with
%   RCS sigma is exactly what render.m draws for a row (amplitude from the
%   radar equation, phase from range), and build_scene's own platform skin
%   path supports only one platform.
%
%   OPTIONS ADDED 11 Sep 2026 (each default reproduces F12 bit for bit):
%     'K'                 phantoms per drone, siblings interleaved in range
%     'DroneVelocityMps'  [vx vy] -> ONE moving mother (N must be 1), rendered
%                         through renderPhantomScene's platform path so the
%                         bearing, curvature guard and per-pulse causality all
%                         come from generator.platform.MotherTrack. Its path is
%                         centred on boresight to stay inside the sector.
%     'ClutterGammaDB'    ground clutter (-15 = rural land); [] = off
%     'MtiNotchMps'       runJudge's MTI notch; 0 = off
%     'Arms'              subset of the three arms
%   "To own" counts a backtrack whose partner is the drone's skin echo OR one
%   of its sibling phantoms: either way the phantom was tied to its drone.

    p = inputParser;
    p.addParameter('N', 4);
    p.addParameter('K', 1);
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
    p.addParameter('DroneVelocityMps', []);
    p.addParameter('ClutterGammaDB', []);
    p.addParameter('MtiNotchMps', 0);
    p.addParameter('Arms', ["swarm", "genuine", "trailing"]);
    p.parse(varargin{:});
    o = p.Results;

    N = o.N; K = o.K; t = 0:7;
    owner = repmat(1:N, 1, K);                       % far row -> its drone
    Rd = o.DroneStartM + o.SpacingM * (0:N-1);
    gap = o.GapM; if isempty(gap); gap = o.SpacingM; end
    Rp = Rd(end) + gap + o.SpacingM * (0:N*K-1);
    rates = [repmat(o.DroneRateMps, 1, N), repmat(o.PhantomRateMps, 1, N*K)];
    assert(max(Rp) + 50 < physics.Constants().R_unambiguous, 'far rows would fold');
    % ponytail: build_scene checks causality against ONE mother range, so it is
    % set below every row (1700 m) and the per-drone check is asserted here:
    % every phantom starts >1 km beyond every drone, far past c*1us/2 = 150 m.
    assert(min(Rp) - max(Rd) > 150, 'a phantom sits in front of its drone');
    sector = double(py.generator.platform.unambiguous_sector_rad());

    s = deg2rad(o.SpreadDeg);
    b = linspace(-s/2, s/2, N)';                     % drone bearings
    v = linspace(-4.5, 4.5, N)';                     % drone cross speeds [m/s]
    c = linspace(-s/2, s/2, N*K)' + s / (2*N*K);     % genuine far bearings: between drones
    vg = linspace(-4.5, 4.5, N*K)';                  % genuine cross speeds (crossing opposite)
    t0 = 0;
    azNear = atan2(Rd' .* tan(b) + v .* t, Rd');
    moving = ~isempty(o.DroneVelocityMps);
    if moving
        assert(N == 1, 'the platform path models one mother drone');
        vel = [o.DroneVelocityMps(:)', 0];
        x0 = Rd; y0 = -vel(2) * t(end) / 2;          % crossing path centred on boresight
        mt = py.generator.platform.MotherTrack(pyargs( ...
            'position0_m', py.tuple({x0, y0, 0}), 'velocity_mps', py.tuple(num2cell(vel))));
        azNear = cellfun(@double, cell(mt.azimuth_rad(py.list(num2cell(t))).tolist()));
        % Genuine arm = a FORMATION: same cross velocity as the drone, own bearings.
        b = 0; v = vel(2); vg = -v * ones(N*K, 1); t0 = t(end) / 2;
    end
    tt = t - t0;
    judgeArgs = {};
    if o.MtiNotchMps > 0; judgeArgs = {'MtiNotchMps', o.MtiNotchMps}; end

    fprintf('\n=== SKIN BACKTRACK CHECK [SIM] === N=%d K=%d, %d seeds, drones %g-%g m, clutter %s, MTI %g, vel %s\n', ...
        N, K, o.NumSeeds, Rd(1), Rd(end), mat2str(o.ClutterGammaDB), o.MtiNotchMps, mat2str(o.DroneVelocityMps));
    fprintf('%-9s %8s %10s %16s %10s %22s %8s %8s %6s\n', 'arm', 'rcs', 'skin det', ...
        'far backtracked', 'to own', 'far real / flagged CI', 'cob', 'EA fake', 'unm');
    results = struct('arm', {}, 'rcs', {}, 'K', {}, 'skinByDrone', {}, 'skinDetected', {}, ...
        'farBacktracked', {}, 'toOwnDrone', {}, 'farReal', {}, 'cobFlagged', {}, ...
        'farFake', {}, 'unmatched', {}, 'k', {}, 'n', {}, 'ciLow', {}, 'ciHigh', {});

    for rcsSkin = o.PlatformRcs
        rcs = [repmat(rcsSkin, 1, N), (Rp / 2400).^4];   % far rows at equal received power
        for arm = string(o.Arms)
            switch arm
                case "swarm";    azFar = azNear(owner, :);
                case "genuine";  azFar = atan2(Rp' .* tan(c) - vg .* tt, Rp');
                case "trailing"; azFar = atan2(Rp' .* tan(b(owner)) + v(owner) .* tt, Rp');
            end
            % render.m does not police the monopulse sector; a wrapped bearing
            % would be a silent, wrong scene.
            assert(max(abs([azNear(:); azFar(:)])) < sector, 'a row leaves the monopulse sector');
            det = 0; k = 0; own = 0; real_ = 0; fake = 0; cob = 0; unm = 0;
            detByDrone = zeros(1, N);
            ownerOf = [0, 1:N, owner];                    % truth row + 1 -> drone (0 = none)
            for seed = 1:o.NumSeeds
                rng(seed, 'twister');
                tag = sprintf('skinbt_%s_r%g_g%d_K%d_c%s_m%g_v%s_%d', arm, rcsSkin, gap, ...
                    K, mat2str(o.ClutterGammaDB), o.MtiNotchMps, ...
                    strjoin(string(o.DroneVelocityMps), '_'), seed);
                if moving
                    % The builder appends the skin row LAST; map back to drones-first.
                    [jm, truth] = renderPhantomScene(Rp, o.PhantomRateMps, 'Rcs', rcs(N+1:end), ...
                        'MotherRangeM', hypot(x0, y0), 'MotherAzimuthRad', atan2(y0, x0), ...
                        'MotherVelocityMps', vel, 'IncludePlatformSkinReturn', true, ...
                        'PlatformRcs', rcsSkin, 'NumFrames', 8, 'NumPulses', 32, ...
                        'PhantomAzimuthRad', [azFar; azNear], ...
                        'ClutterGammaDB', o.ClutterGammaDB, 'Tag', tag);
                    assert(truth.platform_row == K + 1 && ...
                        max(abs(truth.source_azimuth_rad(:)' - azNear)) < 1e-9, ...
                        'MotherTrack and the builder disagree on the platform');
                else
                    [jm, truth] = renderPhantomScene([Rd, Rp], rates, 'Rcs', rcs, ...
                        'MotherRangeM', 1700, 'NumFrames', 8, 'NumPulses', 32, ...
                        'SourceAzimuthRad', 0, 'PhantomAzimuthRad', [azNear; azFar], ...
                        'ClutterGammaDB', o.ClutterGammaDB, 'Tag', tag);
                end
                fb = engine.runJudge(jm, judgeArgs{:});
                [verdict, d] = track.skinBacktrack(fb);
                ea = track.emitterAttribution(fb);
                row = localMatchRows(fb, truth);          % track -> truth row (0 = none)
                if moving; m = [0, 2:K+1, 1]; row = m(row + 1); end
                lbl = string(fb.track_label);
                det = det + nnz(ismember(1:N, row));
                detByDrone = detByDrone + ismember(1:N, row);
                cob = cob + fb.cobearing_flagged;
                unm = unm + nnz(row == 0);
                for j = 1:N*K
                    tr = find(row == N + j, 1);
                    if isempty(tr); continue; end
                    real_ = real_ + (lbl(tr) == "real");
                    fake = fake + (ea(tr) == "radiated-fake");
                    if verdict(tr) == "backtracked"
                        k = k + 1;
                        own = own + (ownerOf(row(d(tr).partner) + 1) == owner(j));
                    end
                end
            end
            n = N * K * o.NumSeeds;
            [lo, hi] = localWilson(k, n);
            fprintf('%-9s %8.2g %6d/%-3d %12d/%-3d %6d %11d/%d [%.2f,%.2f] %5d/%-3d %5d %5d   skin by drone range: %s\n', ...
                arm, rcsSkin, det, N*o.NumSeeds, k, n, own, real_, n, lo, hi, ...
                cob, o.NumSeeds, fake, unm, mat2str(detByDrone));
            results(end+1) = struct('arm', char(arm), 'rcs', rcsSkin, 'K', K, ...
                'skinByDrone', detByDrone, 'skinDetected', det / (N*o.NumSeeds), ...
                'farBacktracked', k / n, 'toOwnDrone', own, 'farReal', real_ / n, ...
                'cobFlagged', cob / o.NumSeeds, 'farFake', fake / n, 'unmatched', unm, ...
                'k', k, 'n', n, 'ciLow', lo, 'ciHigh', hi); %#ok<AGROW>
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
