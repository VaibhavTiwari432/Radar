function s = EntityState(varargin)
%ENTITYSTATE  One virtual entity's complete state -- the SINGLE source every
%             observable is rendered from (Virtual Entity Engine, step 1).
%
%   s = engine.entity.EntityState('Name', value, ...)
%
%   Fields (mission's s = [R, Rdot, Rddot, RCS/Swerling, microDoppler, class])
%   -----------------------------------------------------------------------
%       .range_m           R      [m]      two-way slant range, > 0
%       .range_rate_mps    Rdot   [m/s]    dR/dt. POSITIVE = OPENING, negative
%                                          = closing. Same convention as
%                                          cogengine/renderer.py's doppler_hz
%                                          and +track/discriminator.m -- do not
%                                          silently flip it.
%       .range_accel_mps2  Rddot  [m/s^2]  d2R/dt2
%       .rcs_dbsm                 [dBsm]   mean RCS
%       .swerling                 0..4     fluctuation model (renderer.py's
%                                          swerling_amplitude_samples)
%       .micro_doppler_hz         [Hz]     blade-passage rate; 0 = none
%       .blade_tip_mps            [m/s]    blade-tip radial velocity. With
%                                          micro_doppler_hz this fixes the
%                                          micro-Doppler modulation index
%                                          beta = 2*v_tip/(lambda*f_blade),
%                                          i.e. how many Bessel sidebands the
%                                          rotor actually produces. MEASURED
%                                          (4.55 m/s) -- see render.m.
%       .class                    char     one of CLASSES below (mirrors
%                                          cogengine/schema.py PHANTOM_CLASSES)
%       .model                    char     '' or one of the MEASURED_MODELS
%                                          below. Naming one fills
%                                          micro_doppler_hz from the TSMS-Drone
%                                          CW measurement instead of a retyped
%                                          constant. Requires class 'drone'.
%
%   THREAT MODEL: CONSTANT VELOCITY (straight-line / gently-closing).
%   Rddot is carried in the state and propagated, but for this build it is
%   nominally ZERO and is driven only by process noise -- see
%   engine.entity.propagate. A maneuvering (IMM: CV/CT/CA) adversary is
%   explicitly NOT this build; see CLAUDE.md's "Virtual Entity Engine" section.
%
%   WHY THIS EXISTS: before the VEE, a scene's observables were per-frame
%   independent signal knobs (delay, gain, phase -- +synth/synthesizeSwarm.m's
%   action struct), so nothing forced range, Doppler, amplitude and
%   micro-Doppler to agree with one another or with any single physical
%   object. This struct IS that object; engine.entity.render is the only
%   thing allowed to turn it into observables.
%
%   NO SELF-VERIFICATION (CLAUDE.md Rule 2): this file knows nothing about
%   +radar/+track/trackerGNN and never scores itself.
%
%   Example
%       s = engine.entity.EntityState('range_m', 1800, ...
%               'range_rate_mps', -60, 'class', 'fighter');

    % Mirrors cogengine/schema.py's PHANTOM_CLASSES, same order, same names.
    CLASSES = {'fighter', 'airliner', 'drone', 'missile', 'decoy'};

    p = inputParser;
    addParameter(p, 'range_m',          1800,      @(x) isscalar(x) && isnumeric(x));
    addParameter(p, 'range_rate_mps',    -60,      @(x) isscalar(x) && isnumeric(x));
    addParameter(p, 'range_accel_mps2',    0,      @(x) isscalar(x) && isnumeric(x));
    addParameter(p, 'rcs_dbsm',            0,      @(x) isscalar(x) && isnumeric(x));
    addParameter(p, 'swerling',            1,      @(x) isscalar(x) && isnumeric(x));
    addParameter(p, 'micro_doppler_hz',    0,      @(x) isscalar(x) && isnumeric(x) && x >= 0);
    % Blade-tip radial velocity. Default is MEASURED, not assumed: 4.55 m/s,
    % read off the TSMS-Drone FMCW sample's own range-Doppler map
    % (data/TSMS-Drone/README.md). It is the only quantity here that carries a
    % measured provenance, and it is defaulted rather than left at 0 so that
    % every caller that already sets micro_doppler_hz gets a physically
    % sized comb instead of silently getting no micro-Doppler at all.
    addParameter(p, 'blade_tip_mps',    4.55,      @(x) isscalar(x) && isnumeric(x) && x >= 0);
    addParameter(p, 'class',       'fighter',      @(x) ischar(x) || isstring(x));
    % MODEL (T10, 27 July 2026). Names a measured drone so the blade rate comes
    % from data instead of being retyped at each call site. '' = not a named
    % model, every field behaves exactly as before.
    addParameter(p, 'model',            '',        @(x) ischar(x) || isstring(x));
    % ANGLE (added 25 July 2026, RADAR_REALISM_AUDIT.md 1.1). Azimuth off
    % boresight [rad], plus its rate. Default 0 = on boresight, which is what
    % every caller written before the angle channel existed gets.
    addParameter(p, 'azimuth_rad',         0,      @(x) isscalar(x) && isnumeric(x));
    addParameter(p, 'azimuth_rate_rad_s',  0,      @(x) isscalar(x) && isnumeric(x));
    parse(p, varargin{:});
    o = p.Results;

    % ---- measured drone models (T10) -----------------------------------
    % Blade-passage rate per model, median over the CW set's 15 ranges x 25
    % cells (results/tsms_cw_analysis.mat, +experiments/analyzeTSMSCw.m).
    % These are MEASURED, and they are the only micro-Doppler quantity in
    % this project that may be typed as a number without a carrier beside it:
    %
    %   TRANSFERS: line spacing is the blade-passage rate, a MECHANICAL
    %     property of the rotor. It is the same at 10 GHz as at the sensor's
    %     own carrier.
    %   DOES NOT TRANSFER: the comb's extent, hence beta = 2*v_tip/(lambda*
    %     f_blade). The CW set's measured beta is 6.2-10.5, but that sensor's
    %     CARRIER IS NOT RECORDED IN ANY DOWNLOADED FILE, so v_tip cannot be
    %     backed out of it and beta cannot be re-scaled to this project's
    %     lambda. Per-model tip speed is therefore NOT measurable from this
    %     data and is deliberately absent below -- every model keeps the
    %     shared 4.55 m/s, which is derived from the ONE sample whose carrier
    %     is documented (24.125 GHz FMCW). render.m recomputes beta from
    %     lambda, so the comb narrows correctly on its own.
    %
    % The corner reflector (72 Hz, 2 lines, beta 0.72) has no entry ON
    % PURPOSE: it is the rigid no-rotor control and its "comb" is the noise
    % floor. Giving it a blade rate would fake the very thing it exists to
    % bound.
    MEASURED_MODELS = { ...
        'Inspire 2',     110; ...
        'Matrice 30',    182; ...
        'Mavic 2 Pro',   100; ...
        'Phantom 4 Pro', 200};

    o.model = char(o.model);
    if ~isempty(o.model)
        idx = find(strcmpi(o.model, MEASURED_MODELS(:,1)), 1);
        assert(~isempty(idx), 'engine:entity:badModel', ...
            'model must be one of {%s}, got ''%s''', ...
            strjoin(MEASURED_MODELS(:,1)', ', '), o.model);
        % An explicit micro_doppler_hz wins -- naming a model supplies the
        % measurement, it does not overrule a caller who stated a rate.
        if ismember('micro_doppler_hz', p.UsingDefaults)
            o.micro_doppler_hz = MEASURED_MODELS{idx, 2};
        end
        % A named rotorcraft that is not class 'drone' would render NO comb
        % at all (render.m gates on CLASSES_EXPECTING_MICRO), i.e. the
        % measurement would be silently discarded. Fail instead.
        assert(strcmp(char(o.class), 'drone'), 'engine:entity:modelClassMismatch', ...
            ['model ''%s'' is a rotorcraft but class is ''%s''; render.m emits ' ...
             'micro-Doppler only for class ''drone'', so the measured blade ' ...
             'rate would be silently dropped'], o.model, char(o.class));
    end

    % double() everywhere: this struct crosses into savemat/jsonencode seams
    % that are only as well-typed as whatever produced them -- the same
    % int64-vs-double bug +engine/runJudge.m already guards at its own load
    % boundary (see its header).
    s.range_m          = double(o.range_m);
    s.range_rate_mps   = double(o.range_rate_mps);
    s.range_accel_mps2 = double(o.range_accel_mps2);
    s.rcs_dbsm         = double(o.rcs_dbsm);
    s.swerling         = double(o.swerling);
    s.micro_doppler_hz = double(o.micro_doppler_hz);
    s.blade_tip_mps    = double(o.blade_tip_mps);
    s.class            = char(o.class);
    s.model            = o.model;
    % Azimuth is carried in the state and propagated as its own CV component.
    % HONEST SIMPLIFICATION: true 2-D kinematics would couple range and
    % azimuth (a straight-line pass changes both together). Decoupling them is
    % defensible at this project's ranges, where a target subtends a small
    % angle over an 8 s engagement, and it keeps the CV threat model
    % one-dimensional per component. A coupled 2-D truth model is the
    % follow-on if angle ever drives the kinematics rather than riding along.
    s.azimuth_rad        = double(o.azimuth_rad);
    s.azimuth_rate_rad_s = double(o.azimuth_rate_rad_s);

    % Fail fast at construction (CLAUDE.md Rule 7), same posture as
    % cogengine/schema.py's __post_init__ validators.
    assert(s.range_m > 0, 'engine:entity:badRange', ...
        'range_m must be positive, got %g', s.range_m);
    assert(any(s.swerling == 0:4), 'engine:entity:badSwerling', ...
        'swerling must be in 0..4, got %g', s.swerling);
    assert(ismember(s.class, CLASSES), 'engine:entity:badClass', ...
        'class must be one of {%s}, got ''%s''', strjoin(CLASSES, ', '), s.class);
end
