function q = calibrateQ(varargin)
%CALIBRATEQ  Process-noise calibration for engine.entity.propagate.
%
%   q = engine.entity.calibrateQ('Name', value, ...)
%
%   Name-value
%       'Dt'          frame interval [s]                (default 1.0, this
%                     project's established 1 Hz revisit cadence)
%       'GentleAccelG'  accel-jitter level, in g        (default 0.05)
%       'RadCharFile'   path to RadChar-*.h5            (default data/RadChar-Tiny.h5)
%       'Dataset'       a preloaded data.loadRadChar struct, to skip the
%                       ~6 s reload when calibrating repeatedly
%       'NumRecords'    LFM records to sample           (default 600)
%       'Seed'          RNG seed for the record sample  (default 2026)
%
%   Returns
%       q.sigma_accel_mps2   [m/s^2]  kinematic process-noise accel std
%       q.G                  [3x1]    noise gain, [dt^2/2; dt; 1]
%       q.Q                  [3x3]    sigma_accel^2 * (G*G')
%       q.rcs_process_std_db [dB]     amplitude/RCS process-noise FLOOR,
%                                     MEASURED from real RadChar pulses
%       q.n_records          how many real records that median came from
%       q.dt, q.source
%
%   WHAT IS GROUNDED IN REAL DATA AND WHAT IS NOT -- read this before
%   quoting any number out of here.
%   ---------------------------------------------------------------------
%   GROUNDED (RadChar, real intercepted pulses): q.rcs_process_std_db is the
%   median pulse-to-pulse peak-amplitude standard deviation of real
%   RadChar LFM pulse trains, measured over PRI cells that actually contain
%   a pulse (peak > 6x that record's own median envelope -- cells that fall
%   in the inter-pulse gap are excluded, not averaged in; verified
%   interactively that including them contaminated the number with the
%   pulse/no-pulse contrast, ~5 dB at high SNR, instead of measuring
%   scintillation).
%
%   NOT GROUNDED, and it CANNOT be, so it isn't claimed to be:
%     * Kinematic Q. RadChar has no target motion at all (data/README.md:
%       "treat it as a realistic waveform source, not ground-truth ranges"),
%       so no jerk/accel PSD is derivable from it. sigma_accel is set from
%       standard gravity times 'GentleAccelG' -- 0.05 g IS the definition of
%       "gently closing" in this build's CV threat model, and it is the
%       calibration knob. Raise it and you have left the CV threat model;
%       an IMM (CV/CT/CA) entity is explicitly not this build.
%     * Swerling RCS fluctuation. RadChar is the EMITTER'S OWN pulse train,
%       intercepted -- there is no target and no target return in it, which
%       is exactly why the measured number is small (~0.2 dB, a stable
%       transmitter) rather than Swerling-sized (~5.6 dB for Swerling 1).
%       So rcs_process_std_db is used as a FLOOR ("be at least as jittery
%       as a real, stable emitter"), NOT as a target fluctuation model.
%       Swerling stays where it already lives, in the renderer.
%
%   Why a floor at all: an entity rendered with EXACTLY constant amplitude
%   is a mathematical object, not a physical one -- +track/discriminator.m
%   already scores that as decoy on sight (its "range AND amplitude both
%   dead flat -> score 0" branch). This number says how un-flat a real
%   emitter actually is.
%
%   SECOND FLOOR, FROM A REAL TARGET ECHO (27 July 2026)
%   ---------------------------------------------------
%   The RadChar floor above has a structural blind spot it cannot fix: it is
%   the emitter's own pulse train, so it contains no propagation, no target,
%   no multipath and no receiver chain. Everything that happens between the
%   antenna and the target is missing from it by construction.
%
%   TSMS-Drone supplies the missing case: a CORNER REFLECTOR -- rigid, stable
%   RCS, no rotor -- measured through a real FMCW radar at 5 stations
%   (2/8/14/22/30 m), 100 repetitions each. Same CONCEPT as the RadChar
%   floor (a non-fluctuating source, so this is not a Swerling model), but
%   measured through an actual echo. Per-range std:
%
%       2 m 0.309 | 8 m 0.685 | 14 m 0.378 | 22 m 0.441 | 30 m 0.550  [dB]
%       pooled 0.491 dB
%
%   That is 2.1x the RadChar figure, and the direction is the expected one:
%   a real echo is jitterier than a bench emitter. It is also a LOWER bound,
%   because the sensor appears to normalise per capture (see the warning
%   below) and any such normalisation can only shrink an apparent spread.
%
%   *** THIS FLOOR IS NOT A FLUCTUATION MODEL. *** (T11, 27 July 2026)
%   A corner reflector is rigid and does not scintillate, so 0.491 dB bounds
%   JITTER, not target fluctuation. Measured against theory in
%   tests/test_swerling_scale.m: rendered Swerling 1 scintillates at
%   5.59 dB (closed form 5.57), Swerling 3 at 3.57 dB (3.49) -- about 11x
%   this floor. The two quantities are different and must not be compared;
%   the floor is additionally only a LOWER bound, for the AGC reason below.
%   Nothing in this project measures absolute scintillation on a real
%   fluctuating target -- the model is checked against its own theory only.
%
%   The floor used is therefore max(RadChar, target-echo), reported with
%   q.rcs_floor_source so a caller can always see which one won.
%   Reproduce: experiments.analyzeTSMSCornerReflector ->
%   results/tsms_cr_analysis.mat. Hardcoded rather than recomputed because it
%   needs 24.5 GB of FMCW bundles present, which is not a runtime dependency
%   worth taking.
%
%   *** DO NOT TAKE AN AMPLITUDE-VS-RANGE LAW FROM THAT DATASET. ***
%   The same 5 stations were also fitted for the two-way law and the answer
%   was -3.4 dB/decade [95% CI -5.2, -1.6] against a physical -40. The
%   reflector's return barely fades over a 15x range increase (-90.1 dB at
%   2 m to -94.5 dB at 30 m, where R^-4 demands ~47 dB). That is not a
%   propagation measurement, it is AGC or per-capture normalisation in the
%   TinyRad, and the corner reflector is what makes it obvious. The measured
%   slope is recorded here only so nobody re-derives it and believes it.

    p = inputParser;
    addParameter(p, 'Dt',           1.0,   @(x) isscalar(x) && x > 0);
    addParameter(p, 'GentleAccelG', 0.05,  @(x) isscalar(x) && x >= 0);
    addParameter(p, 'RadCharFile',  '',    @(x) ischar(x) || isstring(x));
    addParameter(p, 'Dataset',      [],    @(x) isstruct(x) || isempty(x));
    addParameter(p, 'NumRecords',   600,   @(x) isscalar(x) && x >= 1);
    addParameter(p, 'Seed',         2026,  @(x) isscalar(x));
    parse(p, varargin{:});
    o = p.Results;

    C  = physics.Constants();
    dt = o.Dt;

    % ---- kinematic: discrete white-noise acceleration (DWNA) on the CV
    %      part of [R; Rdot; Rddot]. One scalar accel draw per step, mapped
    %      through G -- so range and range-rate jitter stay MUTUALLY
    %      CONSISTENT (they come from one draw), which is the whole point of
    %      a single propagated state.
    %
    %      G(3) IS ZERO ON PURPOSE. sigma_accel is the UNMODELLED
    %      acceleration that perturbs constant-velocity motion (textbook
    %      DWNA for a CV model); it is not a driving noise on the
    %      acceleration STATE. Setting G(3)=1 instead makes Rddot a random
    %      walk, and this build measured what that costs: after 40 dwells
    %      the entity had wandered 601 m off its own straight line and its
    %      acceleration had drifted to ~3 m/s^2 -- a maneuvering target,
    %      i.e. outside the CV threat model this build declares. With G(3)=0
    %      the acceleration state stays exactly where it is put, which is
    %      also what build step 5 needs: a commanded maneuver must not be
    %      washed out by process noise before the dwell ends.
    STANDARD_GRAVITY = 9.80665;                     % m/s^2, defined SI value
    q.sigma_accel_mps2 = o.GentleAccelG * STANDARD_GRAVITY;
    q.G = [dt^2/2; dt; 0];
    q.Q = q.sigma_accel_mps2^2 * (q.G * q.G');

    % ---- amplitude floor: measured from real RadChar pulses ----
    if isempty(o.Dataset)
        f = char(o.RadCharFile);
        if isempty(f)
            here = fileparts(mfilename('fullpath'));                 % +entity
            projectRoot = fileparts(fileparts(here));                % repo root
            f = fullfile(projectRoot, 'data', 'RadChar-Tiny.h5');
        end
        % NO silent fallback (CLAUDE.md Rule 7): if the real data isn't
        % here, say so and stop -- do not quietly substitute a constant and
        % let a caller believe it was measured.
        assert(isfile(f), 'engine:entity:noRadChar', ...
            ['calibrateQ needs real RadChar pulses and found none at:\n  %s\n' ...
             'See data/README.md to download it, or pass ''Dataset'', ' ...
             'data.loadRadChar(path).'], f);
        Dset = data.loadRadChar(f);
        q.source = f;
    else
        Dset = o.Dataset;
        if isfield(Dset, 'file'); q.source = Dset.file; else; q.source = '(preloaded)'; end
    end

    LFM_SIGNAL_TYPE = 4;                             % +physics/Constants.m signal_types map
    CLEAR_PULSE_FACTOR = 6;                          % peak/median-envelope test for "this cell holds a pulse"
    MIN_CELLS = 3;                                   % need >=3 pulses to have a std worth quoting

    lfmIdx = find(Dset.signal_type == LFM_SIGNAL_TYPE);
    assert(~isempty(lfmIdx), 'engine:entity:noLfmRecords', ...
        'No LFM (signal_type==%d) records in %s', LFM_SIGNAL_TYPE, q.source);

    rs = RandStream('twister', 'Seed', o.Seed);      % local stream: does not
    nPick = min(o.NumRecords, numel(lfmIdx));        % disturb the caller's rng state
    pick = lfmIdx(randperm(rs, numel(lfmIdx), nPick));

    stds = zeros(0,1);
    for idx = pick(:)'
        nPulses = double(Dset.number_of_pulses(idx));
        cellLen = round(Dset.pulse_repetition_interval(idx) * C.fs);
        env     = abs(Dset.iq(:, idx));
        start   = round(Dset.time_delay(idx) * C.fs) + 1;
        floorEst = median(env);

        peaks = zeros(0,1);
        for i = 0:nPulses-1
            a = start + i*cellLen;
            if a > numel(env); break; end
            b = min(numel(env), a + cellLen - 1);
            peaks(end+1,1) = max(env(a:b)); %#ok<AGROW>
        end
        peaks = peaks(peaks > CLEAR_PULSE_FACTOR * floorEst);
        if numel(peaks) >= MIN_CELLS
            stds(end+1,1) = std(20*log10(peaks)); %#ok<AGROW>
        end
    end

    assert(~isempty(stds), 'engine:entity:noUsableRecords', ...
        ['No RadChar record had >=%d clearly-above-noise pulse cells out of ' ...
         '%d sampled -- cannot measure an amplitude floor.'], MIN_CELLS, nPick);

    % MEASURED, TSMS-Drone corner reflector through a real FMCW receiver --
    % see the "SECOND FLOOR" block in the header for the per-range spread and
    % for why it is a lower bound.
    TARGET_ECHO_FLOOR_DB = 0.491;

    q.rcs_process_std_db_emitter = median(stds);     % RadChar, bench emitter
    q.rcs_process_std_db_target  = TARGET_ECHO_FLOOR_DB;
    % Take the larger. A floor exists to stop an entity being rendered
    % implausibly flat, so between two valid floors the binding one is the
    % higher; picking the lower would let the renderer emit something
    % smoother than anything either measurement has ever seen.
    if q.rcs_process_std_db_target > q.rcs_process_std_db_emitter
        q.rcs_process_std_db = q.rcs_process_std_db_target;
        q.rcs_floor_source   = 'tsms-corner-reflector';
    else
        q.rcs_process_std_db = q.rcs_process_std_db_emitter;
        q.rcs_floor_source   = 'radchar-emitter';
    end
    q.n_records = numel(stds);
    q.dt = dt;
end
