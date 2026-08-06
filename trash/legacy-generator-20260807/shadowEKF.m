function [f, out] = shadowEKF(f, z, dt, varargin)
%SHADOWEKF  The engine's ESTIMATE of the radar's tracking filter (VEE step 3).
%
%   f        = engine.track.shadowEKF([], z0, dt, 'Class', 'fighter')   % init
%   [f, out] = engine.track.shadowEKF(f, z, dt)                          % step
%
%       f   : filter struct (opaque; carry it between dwells)
%       z   : measured range this dwell [m]. Pass [] for a missed detection
%             -- the filter then predicts only, and `out` reports the
%             prediction with no innovation.
%       dt  : time since the previous dwell [s]
%
%       out : the LIVE, PRE-TRANSMIT consistency signal, per dwell
%           .z_pred       predicted range measurement [m]
%           .S            innovation covariance [m^2]
%           .nu           innovation z - z_pred [m]
%           .nis          normalised innovation squared, nu^2/S
%           .gate         the filter's own chi-square gate threshold
%           .gate_margin  gate - nis  (POSITIVE = inside the gate; the
%                         bigger it is, the more comfortably this dwell's
%                         measurement agrees with the tracked object)
%           .gated        true if nis <= gate
%           .x, .P        posterior state and covariance
%
%   Name-value (init call only)
%       'Class'            'fighter'  sets the birth velocity prior
%       'SigmaAccelMps2'   0.4903     process-noise accel std; pass
%                          engine.entity.calibrateQ's .sigma_accel_mps2
%       'GateProbability'  0.99       chi-square gate probability
%
%   ================= WHY THIS IS NOT THE JUDGE'S FILTER =================
%   This is the engine's MODEL of the radar's predict/gate/update loop, and
%   it is deliberately parameterised SEPARATELY from +track/runTracker.m.
%   If the two shared parameters, scoring a scene by this filter's NIS would
%   be self-grading -- the engine would be marking its own homework one
%   level up, which is the exact failure the VEE rebuild exists to fix.
%   The gap between this filter and the judge is the MEASURED RESULT
%   (tests/test_vee_shadow.m), not a bug to tune away.
%
%   Every difference below is intentional and independently motivated:
%
%     |            | shadow (here)              | judge (+track/runTracker) |
%     |------------|----------------------------|---------------------------|
%     | state      | 2-state, range only [R,Rdot]| trackerGNN/initcvekf,    |
%     |            |                            | 3-D CV position state     |
%     | F          | [1 dt; 0 1]                | MathWorks' constvel       |
%     | Q          | DWNA, sigma_accel from      | trackerGNN's own default  |
%     |            | engine.entity.calibrateQ    | process noise             |
%     | R          | quantisation variance,      | diag([range_per_sample^2, |
%     |            | delta^2/12 (delta =         | 1, 1]) -- i.e. sigma =    |
%     |            | C.range_per_sample)         | delta, sqrt(12)x larger   |
%     | gate       | chi-square on NIS, 1 DOF    | AssignmentThreshold, a    |
%     |            |                            | 200 m EUCLIDEAN distance  |
%
%   The R row is the load-bearing one. A range bin is a UNIFORM quantiser,
%   whose error standard deviation is delta/sqrt(12) ~ 13.5 m, not delta
%   ~ 46.8 m. The judge deliberately uses delta^2 (its own comment explains
%   why: it fixed a real duplicate-TrackID bug). Both are defensible; they
%   are not the same number, so the shadow is systematically MORE suspicious
%   than the judge by roughly a factor of 12 in NIS. That is a predictable,
%   explainable gap -- and step 4 measures whether it still predicts the
%   judge's verdict.
%
%   NOT A TRACKER. This filter follows ONE entity that the engine itself
%   placed; it has no data association, no track birth/death, no M-of-N.
%   Multi-phantom (N entities, N simultaneous shadow gates, shared
%   power/aperture coupling) is explicitly the NEXT phase, not this one.

    C = physics.Constants();

    if isempty(f)
        % ---------------- initialise ----------------
        % The engine's OWN plausible-speed ceilings [m/s]. Same physical
        % meaning as cogengine/radar_twin.py's CLASS_SPEED_LIMIT_MPS, kept in
        % sync by meaning and not by import so the two stay independent.
        SPEED_LIMIT_MPS = struct('drone', 50, 'airliner', 300, ...
                                 'fighter', 700, 'missile', 1000, 'decoy', 1000);

        p = inputParser;
        addParameter(p, 'Class',           'fighter', @(x) ischar(x) || isstring(x));
        addParameter(p, 'SigmaAccelMps2',  0.05*9.80665, @(x) isscalar(x) && x >= 0);
        addParameter(p, 'GateProbability', 0.99,      @(x) isscalar(x) && x > 0 && x < 1);
        parse(p, varargin{:});
        o = p.Results;

        cls = char(o.Class);
        assert(isfield(SPEED_LIMIT_MPS, cls), 'engine:track:badClass', ...
            'Unknown class ''%s'' for the birth velocity prior.', cls);

        assert(~isempty(z), 'engine:track:noBirthMeasurement', ...
            'shadowEKF must be initialised with a real measurement, not [].');

        % Measurement noise: a range bin is a UNIFORM quantiser, so its error
        % variance is delta^2/12 -- derived, not asserted (CLAUDE.md Rule 1).
        f.R = C.range_per_sample^2 / 12;

        % One-point birth, the way a radar actually starts a track: range is
        % known to the quantiser, velocity is completely unknown. A uniform
        % prior over [-vmax, +vmax] has standard deviation vmax/sqrt(3).
        vmax = SPEED_LIMIT_MPS.(cls);
        f.x = [z; 0];
        f.P = diag([f.R, (vmax/sqrt(3))^2]);

        f.sigma_accel = o.SigmaAccelMps2;
        % chi-square gate, 1 DOF, closed form: P(X<=x) = erf(sqrt(x/2)), so
        % x = 2*erfinv(p)^2. Base MATLAB -- no Statistics Toolbox dependency.
        f.gate = 2 * erfinv(o.GateProbability)^2;
        f.class = cls;
        f.n_dwells = 0;

        out = struct('z_pred', z, 'S', f.R, 'nu', 0, 'nis', 0, ...
                     'gate', f.gate, 'gate_margin', f.gate, 'gated', true, ...
                     'x', f.x, 'P', f.P, 'birth', true);
        return;
    end

    % ---------------- predict ----------------
    assert(isscalar(dt) && dt > 0, 'engine:track:badDt', 'dt must be positive.');
    F = [1 dt; 0 1];
    G = [dt^2/2; dt];                       % DWNA on the CV pair
    Q = f.sigma_accel^2 * (G * G');

    xPred = F * f.x;
    PPred = F * f.P * F' + Q;

    H = [1 0];                              % we measure range only
    zPred = H * xPred;
    S     = H * PPred * H' + f.R;

    if isempty(z)
        % Missed detection: predict-only. NaN, not 0 -- a missing innovation
        % is not a perfect one, and must never be averaged in as if it were
        % (CLAUDE.md Rule 7: no silent failures).
        f.x = xPred; f.P = PPred; f.n_dwells = f.n_dwells + 1;
        out = struct('z_pred', zPred, 'S', S, 'nu', NaN, 'nis', NaN, ...
                     'gate', f.gate, 'gate_margin', NaN, 'gated', false, ...
                     'x', f.x, 'P', f.P, 'birth', false);
        return;
    end

    % ---------------- update ----------------
    nu  = z - zPred;
    nis = nu^2 / S;
    K   = PPred * H' / S;

    f.x = xPred + K * nu;
    f.P = PPred - K * S * K';
    f.P = (f.P + f.P') / 2;                 % keep it symmetric against drift
    f.n_dwells = f.n_dwells + 1;

    out = struct('z_pred', zPred, 'S', S, 'nu', nu, 'nis', nis, ...
                 'gate', f.gate, 'gate_margin', f.gate - nis, ...
                 'gated', nis <= f.gate, 'x', f.x, 'P', f.P, 'birth', false);
end
