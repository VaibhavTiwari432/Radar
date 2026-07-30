function out = demoSwarmFlood(maxPhantoms, seed, swerling)
%DEMOSWARMFLOOD  Minimum honest validity check for the mother-drone flood
%   concept: a real mother drone flies into coverage and her transmitters
%   emit phantom swarm members. How many objects will the radar actually
%   believe at once?
%
%   out = experiments.demoSwarmFlood(maxPhantoms, seed, swerling)
%
%   MISSION: FLOOD. Success = number of confirmed tracks the judge labels
%   "real" -- the size of the fake picture the radar holds. NOT "did one
%   phantom evade".
%
%   WHAT THIS MEASURES, AND WHY IT IS A SWEEP RATHER THAN ONE SCENE.
%   The flood is not limited by how convincing each phantom is -- that is
%   solved structurally (T1/T4: 100% believable, untrained, because every
%   observable is derived from one entity state). It is limited by how many
%   objects this radar can RESOLVE AT ALL. Three hard limits set that, and
%   all three are properties of the radar, not of the generator:
%
%     1. MINIMUM RANGE ~1124 m. +radar/cfarDetect.m: "Cells within
%        (NumTraining+NumGuard) of either edge cannot be tested and are
%        never flagged." 20 + 4 = 24 bins x 46.84 m. Anything closer is
%        INVISIBLE -- not stealthy, simply never tested.
%     2. MAXIMUM RANGE 2998 m, the unambiguous range at this PRI. Beyond it
%        a real radar folds returns back inside (RADAR_REALISM_AUDIT 2.2 --
%        computed here, never enforced, so placing a swarm at 5 km would
%        manufacture spread that real hardware collapses).
%     3. MUTUAL MASKING at ~1124 m. The CA-CFAR training window is the same
%        +/-24 bins. Two objects closer than that sit inside each other's
%        training cells, raise each other's threshold, and suppress each
%        other.
%
%   Usable band is therefore ~1874 m wide, and the detector emits at most
%   ONE detection per range bin (the profile handed to CFAR is max-over-
%   Doppler). So the range axis alone cannot hold many members, and this
%   sweep finds where it breaks instead of asserting a number.
%
%   ARMS
%     control   mother alone. If a genuine drone is not tracked and labelled
%               real, nothing else here means anything. This arm has already
%               earned its place once: it caught a scene placed inside the
%               CFAR blind zone, which had made every number zero.
%     co-bear   mother + N phantoms on HER EXACT BEARING. The physically
%               honest case: one transmitter is one place. render.m -- "range,
%               Doppler and amplitude can all be forged independently per
%               phantom; azimuth cannot, because it is set by where the
%               transmitter physically is."
%     spread    mother + N phantoms given genuine angular spread. A HARDWARE
%               claim (separated apertures on the airframe), never merged
%               with co-bear.
%
%   NOT MODELLED, so this cannot speak to them: eclipsing/blind ranges,
%   antenna pattern and scan loss, netted or passive geolocation,
%   home-on-jam, or a real system DECLARING jamming.

    if nargin < 1 || isempty(maxPhantoms); maxPhantoms = 4;  end
    if nargin < 2 || isempty(seed);        seed = 2026;      end
    % 0 = non-fluctuating, matching benchmarkSuite (so its published "5%
    % false alarms on genuine aircraft" is comparable). 1 = realistic,
    % measured at 5.59 dB scan-to-scan (T11).
    if nargin < 3 || isempty(swerling);    swerling = 0;     end

    C = physics.Constants();
    K = struct('nFast',400,'nPulses',32,'nFrames',8,'dt',1.0,'prf',50e3, ...
               'carrier',10e9,'pulseWidth',12e-6,'bandwidth',2e6, ...
               'noiseAmp',0.05,'closingMps',-60,'ampScale',3.0);

    binM      = C.range_per_sample;
    guardBins = 20 + 4;
    RMIN      = guardBins * binM;                 % CFAR edge, ~1124 m
    RMAX      = 2998;                             % unambiguous at this PRI
    travel    = abs(K.closingMps) * K.dt * (K.nFrames-1);
    nearestT0 = RMIN + travel;                    % still visible at the END

    fprintf('\n=== SWARM FLOOD VALIDITY (Swerling %d, seed %d) ===\n', swerling, seed);
    fprintf('range bin %.1f m | CFAR blind below %.0f m | unambiguous above %.0f m\n', ...
        binM, RMIN, RMAX);
    fprintf('formation closes %.0f m over %d frames -> nearest member must start >= %.0f m\n', ...
        travel, K.nFrames, nearestT0);
    fprintf('usable t=0 band %.0f-%.0f m (%.0f m wide); CFAR mutual masking needs ~%.0f m spacing\n', ...
        nearestT0, RMAX, RMAX-nearestT0, RMIN);
    fprintf('=> range axis alone can hold about %.1f resolvable objects\n\n', ...
        max(1, (RMAX-nearestT0)/RMIN + 1));

    out = struct('nPhantoms', [], 'coBearReal', [], 'spreadReal', [], ...
                 'coBearConfirmed', [], 'spreadConfirmed', [], 'controlReal', NaN);

    [nc, nr] = localScene(0, false, K, C, seed, swerling, nearestT0, RMAX);
    out.controlReal = nr;
    fprintf('control  mother alone            : confirmed %d | REAL %d\n\n', nc, nr);
    if nr < 1
        warning('demoSwarmFlood:controlFailed', ...
            'CONTROL FAILED -- a genuine drone was not believed. Fix before reading anything below.');
    end

    fprintf('%-3s %-28s %-28s\n', 'N', 'co-bearing (physical)', 'angular spread (hardware)');
    for n = 1:maxPhantoms
        [cbC, cbR] = localScene(n, false, K, C, seed, swerling, nearestT0, RMAX);
        [spC, spR] = localScene(n, true,  K, C, seed, swerling, nearestT0, RMAX);
        out.nPhantoms(end+1) = n;
        out.coBearConfirmed(end+1) = cbC; out.coBearReal(end+1) = cbR;
        out.spreadConfirmed(end+1) = spC; out.spreadReal(end+1) = spR;
        fprintf('%-3d confirmed %d / REAL %-14d confirmed %d / REAL %-14d\n', ...
            n, cbC, cbR, spC, spR);
    end

    [bestCb, iCb] = max(out.coBearReal);
    [bestSp, iSp] = max(out.spreadReal);
    fprintf('\nFLOOD CEILING (objects emitted -> tracks believed)\n');
    fprintf('  co-bearing     : best %d believed, at N=%d emitted\n', bestCb, out.nPhantoms(iCb));
    fprintf('  angular spread : best %d believed, at N=%d emitted\n', bestSp, out.nPhantoms(iSp));
end

% ------------------------------------------------------------------------
function [nConf, nReal] = localScene(nP, spread, K, C, seed, swerling, nearestT0, RMAX)
%LOCALSCENE  Mother (genuine skin return) + nP emitted phantoms, spread
%   evenly across the usable band. Phantoms are placed FARTHER than the
%   mother, enforcing DRFM causality -- a stored-and-replayed pulse can only
%   come back later. The cost of that is stated in the docs: the nearest
%   track is always the real drone.
    rs = RandStream('twister', 'Seed', seed);
    cube  = complex(zeros(K.nFast, K.nPulses, K.nFrames));
    cubeD = complex(zeros(K.nFast, K.nPulses, K.nFrames));

    if nP == 0
        r0 = nearestT0 + 400;                    % comfortably mid-band
    else
        r0 = linspace(nearestT0, RMAX - 50, nP + 1);
    end

    for k = 1:K.nFrames
        for j = 1:numel(r0)
            az = 0;
            if spread && j > 1
                % Inside the monopulse unambiguous sector (+/-2.87 deg at
                % d = 0.30 m, 10 GHz). Monopulse resolves WITHIN a beam; it
                % cannot invent a wider one.
                az = ((j-1) - nP/2) / max(nP,1) * 0.08;
            end
            s = localState(r0(j) + K.closingMps*K.dt*(k-1), K.closingMps, az, j, swerling);
            [cs, ~, cd] = engine.entity.render(s, 'AmpScale', K.ampScale, ...
                'NumPulses', K.nPulses, 'FastTimeSamples', K.nFast, ...
                'CarrierHz', K.carrier, 'PrfHz', K.prf, ...
                'PulseWidth', K.pulseWidth, 'Bandwidth', K.bandwidth, ...
                'RandStream', rs);
            cube(:,:,k)  = cube(:,:,k)  + cs;
            cubeD(:,:,k) = cubeD(:,:,k) + cd;
        end
        cube(:,:,k)  = cube(:,:,k)  + localNoise(rs, K);
        cubeD(:,:,k) = cubeD(:,:,k) + localNoise(rs, K);
    end

    S = struct('rx_frames', cube, 'rx_frames_delta', cubeD, 'fs', C.fs, ...
        'pulse_width_s', K.pulseWidth, 'bandwidth_hz', K.bandwidth, ...
        'prf_hz', K.prf, 'cfar_pfa', 1e-4, 'cfar_num_training', 20, ...
        'cfar_num_guard', 4, 'frame_interval_s', K.dt, 'carrier_hz', K.carrier, ...
        'assignment_gate_m', 200, 'confirmation_threshold', [3 5], ...
        'deletion_threshold', [5 5], 'filter_model', 'cv', 'tracker_type', 'gnn', ...
        'eccm_screens', {{'amplitude','doppler'}});
    f = [tempname '.mat']; save(f, '-struct', 'S');
    cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
    fb = engine.runJudge(f);

    labels = string(fb.track_label(:)).';
    nConf  = numel(labels);
    nReal  = nnz(labels == "real");
end

function nz = localNoise(rs, K)
    nz = K.noiseAmp * (randn(rs, K.nFast, K.nPulses) + ...
                    1i*randn(rs, K.nFast, K.nPulses)) / sqrt(2);
end

function s = localState(rangeM, rateMps, azRad, idx, swerling)
%LOCALSTATE  One entity. Every observable derives from this, which is what
%   makes each member individually on-manifold. Phantoms get the SAME
%   fluctuation model and measured blade rates as the mother -- dead-flat
%   phantoms beside a flickering mother would be a one-line giveaway.
    models = {'Mavic 2 Pro', 'Inspire 2', 'Matrice 30', 'Phantom 4 Pro'};
    s = engine.entity.EntityState('range_m', rangeM, 'range_rate_mps', rateMps, ...
        'rcs_dbsm', 0, 'swerling', swerling, 'class', 'drone', ...
        'model', models{1 + mod(idx, numel(models))}, 'azimuth_rad', azRad);
end
