function out = coordinateConsistency(varargin)
%COORDINATECONSISTENCY  Compare where the drone IS against what its signals CLAIM.
%
%   out = experiments.coordinateConsistency()
%   out = experiments.coordinateConsistency('Ranges', [3600 5200 6800], ...)
%
%   THE QUESTION, IN ONE SENTENCE. The mother drone occupies one point in
%   space and radiates N phantoms that each claim to occupy a different one.
%   Given only the received signal, can the radar put both in coordinates and
%   show they are inconsistent?
%
%   WHY IT IS ANSWERABLE AT ALL, AND WHY IT IS THE ONE THING THE ADVERSARY
%   CANNOT FIX. Range, Doppler and amplitude are each forgeable per phantom,
%   independently -- this project spent a great deal of effort proving exactly
%   that, and +generator/physics_projection.py derives all three so they agree
%   with each other by construction. BEARING is not forgeable, because it is
%   set by where the transmitter physically is. +generator/render.m enforces
%   that architecturally: one bearing per frame, shared by every phantom, and
%   no per-phantom angle argument exists to pass.
%
%   So every phantom inherits the PLATFORM's angular rate while reporting its
%   OWN range, and the tangential speed that combination implies is
%
%       v_cross(i) = R(i) * dtheta/dt          [+track/bearingRateScreen.m]
%
%   which is the platform's own cross-range speed multiplied by R(i)/R_mother.
%   A phantom at 3.6 km fed by a drone at 2 km must appear to fly sideways
%   1.8x faster than the drone really does; put three phantoms at three ranges
%   and their implied speeds stand in exact proportion to those ranges, all
%   from one angular rate. No formation of independent aircraft produces that,
%   because for real targets omega = v_cross/R and neither term is shared.
%
%   WHAT THIS FUNCTION PRINTS is that comparison, in metres and metres per
%   second rather than as a screen score: the drone's true track, the radar's
%   own estimate of where the emitter is, and per phantom the measured
%   position, the measured angular rate, and the cross-range speed its claimed
%   range demands. The screen that SCORES this is 2c; this is the audit behind
%   the score.
%
%   THE JUDGE IS NEVER TOLD ANY OF IT. Truth comes back from
%   tests/renderPhantomScene.m to this function, not into the .mat the judge
%   reads (Rule 2). Everything in the "measured" columns is re-derived from
%   complex samples.

    p = inputParser;
    p.addParameter('Ranges', [3600 5200 6800], @isnumeric);   % phantom t=0 ranges [m]
    p.addParameter('Rate', -50, @isscalar);                   % closing [m/s]
    p.addParameter('MotherRangeM', 2000, @isscalar);
    p.addParameter('MotherCrossMps', 3, @isscalar);
    p.addParameter('NumFrames', 8, @isscalar);
    p.addParameter('Seed', 21, @isscalar);
    p.addParameter('SkinReturn', true, @islogical);
    p.parse(varargin{:});
    o = p.Results;

    % Phantom spacing is checked, not assumed: two returns closer than the
    % CA-CFAR's own training+guard width share a window and collapse into one
    % local max, which would look like a detection failure and is really a
    % scene-construction error. Same trap CLAIMABLE_RESULTS.md records twice.
    C = physics.Constants();
    % READ the defaults, never restate them: +radar/cfarDefaults.m is called
    % "the ONE declaration of these values" by its own caller, and an earlier
    % version of this line typed (30 + 4) and claimed it was those defaults.
    % They are 20 and 4, so the real half-window is 24 cells = 1124.2 m.
    cd_ = radar.cfarDefaults();
    cfarSepM = (cd_.NumTraining + cd_.NumGuard) * C.range_per_sample;
    allR = sort([o.MotherRangeM, o.Ranges]);
    assert(all(diff(allR) > cfarSepM), 'coordinateConsistency:tooClose', ...
        'returns must be >%.0f m apart (CFAR train+guard); got %s', ...
        cfarSepM, mat2str(round(allR)));

    rng(o.Seed, 'twister');
    [matPath, truth] = renderPhantomScene(o.Ranges, o.Rate, ...
        'NumFrames', o.NumFrames, ...
        'MotherRangeM', o.MotherRangeM, ...
        'MotherVelocityMps', [0, o.MotherCrossMps, 0], ...
        'IncludePlatformSkinReturn', o.SkinReturn, ...
        'PlatformRcs', 1.0, 'Tag', 'coordcons');
    fb = engine.runJudge(matPath);

    % ---- the drone, truth vs the radar's own estimate ---------------------
    pTrue = truth.mother_position_xyz_m;             % [3 x numFrames]
    omegaTrue = localTrueOmega(truth);

    fprintf('\n=== WHERE THE DRONE IS =================================\n');
    fprintf('true   t=0  (%8.1f, %7.1f, %5.1f) m   v = (%.1f, %.1f, %.1f) m/s\n', ...
        pTrue(1,1), pTrue(2,1), pTrue(3,1), truth.mother_velocity_mps);
    fprintf('true   omega = %+.5f mrad/s   cross speed = %.2f m/s\n', ...
        omegaTrue*1e3, o.MotherCrossMps);
    fprintf('radar  bearing = %+.4f deg   (truth %+.4f deg)\n', ...
        rad2deg(fb.emitter_az_rad), rad2deg(mean(truth.source_azimuth_rad)));
    fprintf('radar  range   = %8.1f m   [%s]   (truth %.1f m)\n', ...
        fb.emitter_range_max_m, fb.emitter_fix, min(truth.mother_range_m));
    fprintf('radar  xyz     = (%8.1f, %7.1f, %5.1f) m\n', fb.emitter_position_xyz_m);
    if o.SkinReturn
        posErr = min(vecnorm(fb.emitter_position_xyz_m - pTrue, 2, 1));
        fprintf('radar  position error = %.1f m   (one range cell = %.1f m)\n', ...
            posErr, C.range_per_sample);
    else
        fprintf('radar  position error = n/a: no skin return, so the range is an\n');
        fprintf('       UPPER BOUND from causality, not a fix\n');
    end

    % ---- each phantom, and what its own claimed range demands -------------
    fprintf('\n=== WHAT THE SIGNALS CLAIM =============================\n');
    fprintf('%-4s %10s %9s %10s %12s %10s  %s\n', 'trk', 'range m', 'x m', 'y m', ...
            'omega mr/s', 'v_cross', 'label');
    n = fb.confirmed_tracks;
    for i = 1:n
        P = fb.track_position_xyz_m{i};
        fprintf('%-4d %10.1f %9.1f %10.1f %12.4f %10.2f  %s\n', i, ...
            mean(fb.track_range_m{i}), mean(P(1,:)), mean(P(2,:)), ...
            fb.track_angular_rate_rad_s(i)*1e3, ...
            fb.track_implied_cross_speed_mps(i), fb.track_label{i});
    end

    % ---- THE COMPARISON ---------------------------------------------------
    % One angular rate shared across every range is the signature. Measured as
    % a RATIO against the within-track scatter, so it needs no tuned threshold
    % -- the same self-calibrating posture as the co-bearing screen.
    omega = fb.track_angular_rate_rad_s(1:n);
    good = isfinite(omega);
    fprintf('\n=== THE COMPARISON =====================================\n');
    fprintf('angular rate across %d tracks: mean %+.4f  spread %.4f mrad/s\n', ...
        nnz(good), mean(omega(good))*1e3, (max(omega(good))-min(omega(good)))*1e3);
    fprintf('drone''s own true rate:        %+.4f mrad/s\n', omegaTrue*1e3);
    fprintf('\nimplied cross-range speed vs the drone''s real %.2f m/s:\n', o.MotherCrossMps);
    for i = 1:n
        if ~isfinite(fb.track_implied_cross_speed_mps(i)); continue; end
        ratioMeas = fb.track_implied_cross_speed_mps(i) / o.MotherCrossMps;
        ratioGeom = mean(fb.track_range_m{i}) / min(truth.mother_range_m);
        fprintf('  trk %d: %6.2f m/s = %.2fx the drone   (its range ratio is %.2fx)\n', ...
            i, fb.track_implied_cross_speed_mps(i), ratioMeas, ratioGeom);
    end

    out = struct('feedback', fb, 'truth', truth, ...
                 'omega_true_rad_s', omegaTrue, ...
                 'omega_measured_rad_s', omega, ...
                 'implied_cross_mps', fb.track_implied_cross_speed_mps(1:n), ...
                 'range_ratio', arrayfun(@(i) mean(fb.track_range_m{i}) / ...
                        min(truth.mother_range_m), 1:n));
end


function w = localTrueOmega(truth)
%LOCALTRUEOMEGA  The platform's own angular rate, from its rendered bearing
%   series. A least-squares slope rather than an endpoint difference, so it
%   matches what the judge fits on its side and the two numbers are
%   comparable rather than merely close.
    t = truth.times_s(:); a = truth.source_azimuth_rad(:);
    pf = polyfit(t, a, 1);
    w = pf(1);
end
