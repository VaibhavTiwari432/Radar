function [s2, w] = propagate(s, dt, q, rs)
%PROPAGATE  One dwell of entity dynamics: s_{t+1} = F*s_t + process noise.
%
%   s2 = engine.entity.propagate(s, dt, q)
%   s2 = engine.entity.propagate(s, dt, q, rs)
%   [s2, w] = engine.entity.propagate(...)
%
%       s  : engine.entity.EntityState struct
%       dt : dwell interval [s]
%       q  : engine.entity.calibrateQ struct (sigma_accel_mps2, G,
%            rcs_process_std_db). Its .dt is informational -- F and G are
%            rebuilt from the dt passed HERE, so a caller stepping at a
%            different cadence than calibrateQ was asked for still gets
%            self-consistent dynamics.
%       rs : (optional) RandStream for reproducible draws. Omit to use the
%            global stream (so an outer rng(seed) still controls this).
%
%       s2 : propagated EntityState
%       w  : [4x1] the draws actually applied, [dR; dRdot; dRddot; dRcs_dB] --
%            returned so a test can assert the noise was NOT zero rather
%            than take it on trust.
%
%   CONSTANT-VELOCITY THREAT MODEL (this build's stated scope). F is the
%   exact kinematic transition for [R; Rdot; Rddot]:
%
%       F = [1  dt  dt^2/2
%            0   1     dt
%            0   0      1 ]
%
%   Rddot is carried and propagated, but starts at 0 for a CV engagement and
%   is NOT perturbed by process noise (see calibrateQ.m on why G(3)=0), so a
%   CV entity stays a CV entity. A commanded maneuver (build step 5's
%   reframed D3QN action) sets Rddot directly and it holds; a mode-switching
%   IMM (CV/CT/CA) entity is explicitly NOT this build.
%
%   Q IS NOT ZERO, DELIBERATELY. A noiseless constant-velocity target is a
%   mathematical object: its amplitude is dead flat, which
%   +track/discriminator.m already scores as decoy on sight, and its
%   innovations against any filter carrying nonzero Q sit implausibly far
%   below the gate. The process noise here is what makes the entity a
%   PHYSICAL object. One scalar acceleration draw per step is mapped
%   through q.G into all three kinematic components, so range, range-rate
%   and range-accel stay mutually consistent -- they are one perturbation
%   of one object, not three independent knobs. That consistency is the
%   entire reason this function exists.
%
%   NO SELF-VERIFICATION (CLAUDE.md Rule 2): nothing here consults
%   +radar/+track or scores the entity it just moved.

    if nargin < 4 || isempty(rs)
        drawFcn = @() randn();
    else
        drawFcn = @() randn(rs);
    end

    assert(isscalar(dt) && dt > 0, 'engine:entity:badDt', ...
        'dt must be a positive scalar, got %s', mat2str(dt));

    F = [1 dt dt^2/2; 0 1 dt; 0 0 1];
    G = [dt^2/2; dt; 0];   % G(3)=0: DWNA on the CV part -- see calibrateQ.m

    x  = [s.range_m; s.range_rate_mps; s.range_accel_mps2];
    wa = q.sigma_accel_mps2 * drawFcn();      % one accel draw, shared by all 3
    dx = G * wa;
    x2 = F*x + dx;

    dRcs = q.rcs_process_std_db * drawFcn();

    s2 = s;
    % Azimuth advances as its own CV component (see EntityState's note on the
    % range/azimuth decoupling). Not driven by process noise for the same
    % reason range-acceleration isn't: a CV entity must stay a CV entity.
    if isfield(s, 'azimuth_rad')
        s2.azimuth_rad = s.azimuth_rad + s.azimuth_rate_rad_s * dt;
    end
    % Clamp range to positive: the state is a two-way SLANT RANGE and the
    % renderer's amplitude law divides by it. Same 1 m floor
    % cogengine/radar_twin.py's advance_phantom already uses -- kept
    % identical so twin and entity don't disagree at the degenerate edge.
    s2.range_m          = max(1.0, x2(1));
    s2.range_rate_mps   = x2(2);
    s2.range_accel_mps2 = x2(3);
    s2.rcs_dbsm         = s.rcs_dbsm + dRcs;

    w = [dx; dRcs];
end
