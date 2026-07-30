function phantoms = buildSceneFromControls(controls, budgetW)
%BUILDSCENEFROMCONTROLS  MISSION_SIMULATOR_UI_SPEC.md Section 3.2's
%   Hallucination Engine controls, turned into an actual N-phantom scene --
%   Step 8's own acceptance criterion: "Setting N=4 in MANUAL produces
%   exactly 4 phantoms in the frame log."
%
%   phantoms = missionsim.buildSceneFromControls(controls, budgetW)
%       controls : struct with fields
%           .n              (1-5, Section 3.2's own locked range -- the
%                            D3QN action space is 5*3*3=45, a slider that
%                            went past 5 would promise capability the
%                            agent can't select, per the spec's own note)
%           .amplitudeProfile  'uniform' | 'decaying' | 'random'
%           .phaseProfile      'random' | 'coherent' | 'staggered'
%                              (HONEST GAP, not wired to physics -- see
%                              below)
%       budgetW  : shared average power budget (W), default this
%                  project's GaN spec (60 W, cogengine.planner_cem.
%                  GAN_AVG_POWER_W) if omitted.
%       phantoms : struct array, this project's own Phantom-compatible
%                  shape (range_m, radial_vel_mps, amp_scale, micro, ...),
%                  ready for engine.sceneStructToJson / cogengine.schema.
%
%   Ranges: spread from 1800 m (this project's canonical reference range)
%   at 1200 m spacing -- comfortably above _min_range_separation_m's
%   derived ~1124 m CFAR interference floor (Task 1, PHASE2_COMPLETION_
%   POA.md), the same spacing already validated end-to-end this session
%   (tests/test_four_phantom_swarm.m).
%
%   HONEST GAP: "Phase profile" has no effect here. This project's Phantom
%   schema (cogengine/schema.py) has never had a phase/coherence field --
%   only range_m, radial_vel_mps, accel_mps2, rcs_dbsm, swerling, amp_scale,
%   micro. The control exists in the UI (Section 3.2 asks for it
%   structurally) but is not wired to any real physics; wiring it would
%   mean inventing a phase-coherence effect this backend has never modeled,
%   which this project's own discipline (CLAUDE.md Rule 1) doesn't allow.

    mod = py.importlib.import_module('cogengine.planner_cem');
    if nargin < 2 || isempty(budgetW)
        budgetW = double(mod.GAN_AVG_POWER_W);
    end
    % Fixed reference anchor (Task 1, PHASE2_COMPLETION_POA.md): amp_scale=3.0
    % <-> 60 W is this project's OWN validated single-phantom reference --
    % constant regardless of what budgetW THIS scene draws from. Read from
    % planner_cem.py directly rather than re-typing 3.0/60.0 here, so the
    % two can never silently drift apart.
    refPowerW = double(mod.REFERENCE_SINGLE_PHANTOM_POWER_W);
    refAmpScale = double(mod.REFERENCE_SINGLE_PHANTOM_AMP_SCALE);

    n = controls.n;
    if n < 1 || n > 5
        error('missionsim:buildSceneFromControls:nOutOfRange', ...
            'Phantom count N must be 1-5 (Section 3.2: the D3QN action space is 5*3*3=45).');
    end

    refRange = 1800.0; spacing = 1200.0;
    ranges = refRange + spacing * (0:n-1);

    powerEach = localAllocatePower(n, budgetW, controls.amplitudeProfile);

    phantoms = repmat(engine.sceneContract().phantom, 1, n);
    for i = 1:n
        phantoms(i).range_m = ranges(i);
        phantoms(i).radial_vel_mps = -60.0;   % this project's canonical closing rate
        phantoms(i).accel_mps2 = 0.0;
        phantoms(i).rcs_dbsm = 0.0;
        phantoms(i).swerling = 0;
        phantoms(i).amp_scale = refAmpScale * (powerEach(i) / refPowerW);
        phantoms(i).micro = struct('type', "rotor", 'n_blades', 4, 'rpm', 3000.0, 'blade_len_m', 0.25);
    end
end

% ===================== file-local helpers =============================
function p = localAllocatePower(n, budgetW, profile)
%LOCALALLOCATEPOWER  Split budgetW across n phantoms per the selected
%   amplitude profile -- 'uniform' splits equally; 'decaying' weights
%   earlier (nearer) phantoms more heavily; 'random' draws a reproducible
%   random simplex split. Always sums to exactly budgetW.
    switch profile
        case 'decaying'
            w = 2 .^ -(0:n-1);
        case 'random'
            r = RandStream('mt19937ar', 'Seed', 20261166);   % reproducible, this project's own mission seed
            w = r.rand(1, n) + 0.1;   % floor avoids a near-zero phantom
        otherwise   % 'uniform'
            w = ones(1, n);
    end
    p = budgetW * w / sum(w);
end
