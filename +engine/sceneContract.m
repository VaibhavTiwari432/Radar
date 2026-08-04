function s = sceneContract()
%SCENECONTRACT  MATLAB mirror of cogengine/schema.py -- the data contract
%   crossing the Python/MATLAB seam (design doc Part 4; build-order step 6).
%
%   s = engine.sceneContract() returns a struct of DEFAULT-populated example
%   structs, one per contract type, so a caller can see every required field
%   and its shape without reading schema.py:
%       s.radarState, s.phantom, s.scene, s.feedback
%
%   These are NOT enforced schemas (MATLAB structs are always duck-typed) --
%   they are documentation-by-example, kept honest by
%   tests/test_decideScene.m actually round-tripping a radarState-shaped
%   struct through engine.decideScene and checking the Scene that comes back
%   has exactly these fields.
%
%   Field names/types here MUST match cogengine/schema.py's dataclasses
%   EXACTLY (jsonencode/jsondecode is the wire format -- see
%   engine.decideScene) -- this is NOT the cognitive_engine/ reference
%   package's scene_contract.m, whose field names (fs_hz, n_pulses, cls, ...)
%   predate and don't match this project's actual, evolved schema.

    % pri_s IS DERIVED FROM prf_hz, not restated alongside it.
    %   It was hard-coded 20e-6 -- the PRI of the OLD 50 kHz PRF -- and was
    %   left behind when prf_hz was retargeted to physics.Constants().PRF
    %   (8 kHz), so the two disagreed by 6.25x. That is not cosmetic:
    %   cogengine/renderer.py builds its Doppler phasor from pri_s
    %   ("pulse_times = arange(num_pulses) * pri_s") while +engine/runJudge.m
    %   MEASURES Doppler using prf_hz, so every scene exported through this
    %   contract carried a Doppler 6.25x too small. Measured on the
    %   far-phantom scene: a -8.36 m/s closer rendered f_d = 86 Hz where
    %   2v/lambda = 558 Hz, so the judge read range-rate 0.000 m/s on a track
    %   whose range was visibly walking -- which +track/discriminator.m
    %   correctly calls a physical contradiction and scores 0. The phantom was
    %   condemned by a units bug, not by ECCM. cogengine/schema.py's
    %   RadarState now rejects an inconsistent pair at the boundary.
    s.radarState = struct( ...
        'mode',         "search", ...          % search|track (schema.py doesn't enumerate, MATLAB doesn't enforce)
        'prf_hz',       physics.Constants().PRF, ...
        'pri_s',        1 / physics.Constants().PRF, ...   % DERIVED -- see above
        'carrier_hz',   10e9, ...               % assumed carrier -- RadChar itself is baseband
        'range_gate_m', [500.0 3000.0], ...     % [lo hi], lo<=hi
        'vel_gate_mps', [-300.0 300.0], ...     % [lo hi], lo<=hi
        'scan_phase',   0.0, ...
        'doubt_cue',    0.0);                   % in [0,1]

    s.phantom = struct( ...
        'class',            "drone", ...        % fighter|airliner|drone|missile|decoy
        'range_m',          1800.0, ...         % > 0
        ... % RETARGETED -60.0 -> -40.0, INSIDE v_ua. At PRF 8 kHz the
        ... % unambiguous velocity is 59.958 m/s, so the old canonical -60.0
        ... % sat just PAST the fold edge: measured directly (holding all else
        ... % fixed), -40 reads -41.22 m/s and labels `real`, while -59 and -60
        ... % both read +59.96 m/s -- the SIGN FLIPS -- and label `decoy`,
        ... % because +track/discriminator.m correctly calls "range closing,
        ... % Doppler opening" a physical contradiction. This was invisible
        ... % until the pri_s/prf_hz units bug above was fixed: suppressing
        ... % every rendered Doppler by 6.25x kept everything inside the
        ... % unambiguous window, so nothing ever folded and the screen could
        ... % not fire. Retargeting here follows the decision the rest of the
        ... % project already made for the same reason -- planner bounds
        ... % clamped to +-v_ua (planner_cem.DEFAULT_BOUNDS_MULTI, Phase 4.1),
        ... % test_waveform_agility at -40, test_angle_channel at -35..-25.
        ... % Validating a "genuine target is labelled real" control with a
        ... % target the radar cannot unambiguously measure is not a control.
        'radial_vel_mps',   -40.0, ...
        'accel_mps2',       0.0, ...
        'rcs_dbsm',         0.0, ...
        'swerling',         0, ...               % 0|1|2|3|4
        'amp_scale',        3.0, ...             % > 0
        'micro',            struct('type',"rotor",'n_blades',4,'rpm',3000.0,'blade_len_m',0.25));  % or [] / omitted

    s.scene = struct( ...
        'phantoms',        s.phantom, ...        % array of phantom structs
        'maneuver',        "rgpo", ...           % static|rgpo|vgpo|swarm
        'eirp_budget_dbw', 20.0, ...
        't0_s',            0.0, ...
        'duration_s',      8.0);                 % > 0

    s.feedback = struct( ...
        'confirmed_tracks',           0, ...
        'false_tracks_surviving',     0, ...     % <- primary deception metric (Rule 2/5)
        'flagged_decoys',             0, ...
        'mean_track_lifetime_frames', 0.0, ...
        'eirp_used_dbw',              0.0, ...
        'per_phantom_status',         {{"undetected"}}, ... % undetected|detected|confirmed|flagged
        'degraded_events',            {{}});      % {frame, reason, confidence} entries -- see
                                                   % +features/synthesizeTxPulse.m; MUST be
                                                   % surfaced, never swallowed (mission Task 1).
end
