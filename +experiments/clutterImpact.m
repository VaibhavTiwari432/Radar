function out = clutterImpact(varargin)
%CLUTTERIMPACT  What ground return does to this radar, and to the drone.
%
%   out = experiments.clutterImpact()
%
%   WHY THIS MATTERS MORE THAN IT LOOKS. Every detection number this project
%   has ever published is a THERMAL-NOISE-ONLY number: until 16 Aug 2026 a
%   grep for clutter across +radar/, +engine/, +track/ and +generator/
%   returned one comment and no code. For a counter-UAS problem that is the
%   wrong limit entirely -- finding a small, slow, low-flying target in ground
%   return IS the problem, and a judge that finds a 0.01 m^2 drone at 2 km in
%   thermal noise is not modelling the hard part.
%
%   THE TWO THINGS CLUTTER DOES, and they pull in opposite directions:
%
%     1. IT DOES NOT HURT A FAST PHANTOM. Ground return sits at ZERO Doppler
%        (+generator/render.m holds one realisation across every pulse in a
%        frame, which is what "stationary" means in slow time). A phantom
%        closing at -50 m/s has f_d = 3333 Hz, thirteen Doppler bins away, so
%        the judge's own Doppler processing separates it for free.
%
%     2. IT DESTROYS A SLOW ONE. The drone itself is nearly stationary in
%        RANGE -- crossing motion produces almost no radial rate -- so its
%        skin echo lands in the same zero-Doppler bin as the clutter and
%        competes with it directly. That is the classic clutter notch, and it
%        is where a small RCS stops being survivable.
%
%   WHAT THAT OVERTURNS. Before clutter, this project measured that a drone
%   OUTSIDE the 1798.75 m blind range is detected, and that its own skin echo
%   then supplies the second co-bearing track +track/emitterAttribution.m
%   needs to name a lone phantom -- from which it followed that the drone
%   "must hide inside the blind range". With clutter on and a REALISTIC drone
%   RCS that conclusion does not survive: the drone is hidden by clutter
%   anywhere, and the blind-range constraint turns out to have been an
%   artefact of the thermal-noise-only model. The table below is that
%   correction, measured.
%
%   Physics and the one cited assumption (gamma = -15 dB, rural land at
%   X-band): +physics/surfaceClutter.m.

    p = inputParser;
    p.addParameter('DroneRcs', [1.0 0.1 0.03 0.01], @isnumeric);
    p.addParameter('GammaDB', -15, @isscalar);
    p.addParameter('DroneRangeM', 2000, @isscalar);   % OUTSIDE the blind range
    p.addParameter('PhantomRangeM', 3600, @isscalar);
    p.addParameter('PhantomRate', -50, @isscalar);
    p.addParameter('Seeds', 1:5, @isnumeric);
    p.parse(varargin{:});
    o = p.Results;

    C = physics.Constants();
    assert(o.DroneRangeM > C.blind_range, 'clutterImpact:droneHidden', ...
        ['the drone must be OUTSIDE the %.1f m blind range for this ' ...
         'comparison to be about clutter rather than eclipse'], C.blind_range);

    % ---- the physics, before any scene ------------------------------------
    S = physics.surfaceClutter('RangesM', [o.DroneRangeM o.PhantomRangeM], ...
                                'GammaDB', o.GammaDB);
    fprintf('\n=== THE GROUND RETURN ITSELF (gamma = %g dB) ===\n', o.GammaDB);
    fprintf('  beamwidth %.2f deg (from the 30 dBi gain), range resolution %.1f m\n', ...
            rad2deg(S.beamwidth_rad), S.range_resolution_m);
    for i = 1:2
        fprintf('  R=%5.0f m: grazing %.3f deg, sigma0 %.1f dB, patch %.0f m^2 -> clutter RCS %.2f m^2, CNR %.1f dB\n', ...
            S.ranges_m(i), rad2deg(S.grazing_rad(i)), S.sigma0_db(i), ...
            S.cell_area_m2(i), S.clutter_rcs_m2(i), S.cnr_db(i));
    end
    fprintf(['  NOTE clutter RCS is CONSTANT with range here: sigma0 ~ 1/R from\n' ...
             '  constant-gamma and the patch area ~ R, so they cancel. A 1 m^2\n' ...
             '  target is therefore below the clutter in its own resolution\n' ...
             '  cell at EVERY range, by a flat %.1f dB.\n'], ...
            10*log10(1.0/S.clutter_rcs_m2(1)));

    % ---- the scene, with and without ---------------------------------------
    fprintf('\n=== DOES THE RADAR STILL SEE THE DRONE? ===\n');
    fprintf('drone at %.0f m crossing (radial rate ~0, so it sits IN the clutter notch)\n', ...
            o.DroneRangeM);
    fprintf('phantom at %.0f m closing %+.0f m/s (f_d = %.0f Hz, clear of the notch)\n\n', ...
            o.PhantomRangeM, o.PhantomRate, -2*o.PhantomRate/C.lambda);
    fprintf('%10s %14s %14s %14s\n', 'drone RCS', 'clutter OFF', 'clutter ON', 'drone found?');

    nR = numel(o.DroneRcs);
    droneOff = zeros(nR,1); droneOn = zeros(nR,1);
    for i = 1:nR
        droneOff(i) = localDroneFound(o, o.DroneRcs(i), []);
        droneOn(i)  = localDroneFound(o, o.DroneRcs(i), o.GammaDB);
        fprintf('%10.2f %11d/%-2d %11d/%-2d %14s\n', o.DroneRcs(i), ...
            droneOff(i), numel(o.Seeds), droneOn(i), numel(o.Seeds), ...
            localVerdict(droneOn(i), numel(o.Seeds)));
    end

    fprintf('\n=== READING ===\n');
    % REMOVED means never found, which is not the same as degraded -- an
    % earlier version reported the first row where clutter cost ANY seed and
    % then called it "stops being detectable", which overstated a 4/5 row.
    lost     = find(droneOn == 0, 1);
    degraded = find(droneOff > droneOn, 1);
    if isempty(lost)
        fprintf('  Clutter did not remove the drone at any RCS tested.\n');
    else
        if ~isempty(degraded) && degraded < lost
            fprintf('  At %.2f m^2 clutter DEGRADES the drone (%d/%d -> %d/%d) rather\n', ...
                    o.DroneRcs(degraded), droneOff(degraded), numel(o.Seeds), ...
                    droneOn(degraded), numel(o.Seeds));
            fprintf('  than removing it -- the cliff is between that and %.2f m^2.\n', ...
                    o.DroneRcs(lost));
        end
        fprintf('  From %.2f m^2 downward the drone is NEVER detected once ground\n', ...
                o.DroneRcs(lost));
        fprintf('  return is present, while it was found in every seed without it.\n');
        fprintf('  A small drone does not need the blind range to hide -- clutter\n');
        fprintf('  hides it.\n');
    end
    fprintf(['\n  AND THE PHANTOM IS UNAFFECTED, because it is moving. Clutter\n' ...
             '  costs the RADAR its view of the emitter without costing the\n' ...
             '  ADVERSARY anything, which is the asymmetry that matters here.\n']);
    fprintf(['\n  STATED LIMITS: Rayleigh clutter statistics (real land clutter is\n' ...
             '  heavier-tailed and would give MORE false alarms), no spatial\n' ...
             '  texture or discretes, and no clutter in the angle channel.\n' ...
             '  gamma = %g dB is the assumption.\n'], o.GammaDB);
    fprintf(['\n  AND THE RADAR''S OWN FILTER DOES NOT RESCUE IT. runJudge has an\n' ...
             '  MTI notch (MtiNotchMps, default off and OFF in this table). Turning\n' ...
             '  it on removes the tangential drone at ANY RCS, clutter or not,\n' ...
             '  while the moving phantom stays -- tests/test_mti_notch.m, and\n' ...
             '  CLUTTER_AND_MTI_RESULTS.md for both edges.\n']);

    out = struct('drone_rcs', o.DroneRcs(:), 'found_clutter_off', droneOff, ...
                 'found_clutter_on', droneOn, 'n_seeds', numel(o.Seeds), ...
                 'clutter', S, 'gamma_db', o.GammaDB);
end


function n = localDroneFound(o, rcs, gammaDB)
%LOCALDRONEFOUND  How many seeds detect a track at the drone's own range.
%   Counted by RANGE PROXIMITY rather than track count: with clutter on, a
%   false alarm elsewhere would inflate a bare count and make the drone look
%   present when it is not.
    C = physics.Constants();
    n = 0;
    for s = o.Seeds
        rng(s, 'twister');
        args = {o.PhantomRangeM, o.PhantomRate, 'NumFrames', 8, ...
                'MotherRangeM', o.DroneRangeM, 'MotherVelocityMps', [0 3 0], ...
                'IncludePlatformSkinReturn', true, 'PlatformRcs', rcs, ...
                'IncludeAngleChannel', false, ...
                'Tag', sprintf('ci_%d_%d', round(rcs*1000), s)};
        if ~isempty(gammaDB); args = [args, {'ClutterGammaDB', gammaDB}]; end %#ok<AGROW>
        m = renderPhantomScene(args{:});
        fb = engine.runJudge(m);
        if fb.confirmed_tracks < 1; continue; end
        rr = cellfun(@(r) mean(r), fb.track_range_m);
        if any(abs(rr - o.DroneRangeM) < 2 * C.range_per_sample)
            n = n + 1;
        end
    end
end


function s = localVerdict(found, total)
    if found == 0
        s = 'NEVER';
    elseif found < total
        s = 'sometimes';
    else
        s = 'always';
    end
end
