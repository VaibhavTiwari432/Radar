function [judgeMat, truth] = renderPhantomScene(ranges0M, ratesMps, varargin)
%RENDERPHANTOMSCENE  Build a judge-ready .mat through the REBUILT generator.
%
%   [judgeMat, truth] = renderPhantomScene(ranges0M, ratesMps, ...)
%       ranges0M  [1 x N] each phantom's t=0 apparent range [m]
%       ratesMps  [1 x N] or scalar, range-rate [m/s] (negative = closing)
%       judgeMat  path to a .mat +engine/runJudge.m can be handed directly
%       truth     what was ACTUALLY built: per-frame range per phantom,
%                 frame times, num_frames. Returned rather than re-derived on
%                 the MATLAB side, so a test asserts against the trajectory
%                 the judge really consumed and the two cannot drift apart.
%
%   Name-value (defaults match this project's established operating point):
%       'Rcs'            1.0    [m^2], scalar or [1 x N]
%       'NumFrames'      8
%       'NumPulses'      32     pulses per frame. 1 collapses rx_frames to
%                               the legacy 2-D shape, which is what actually
%                               disables the Doppler screen (see runJudge.m's
%                               own ndims==3 check -- a [400 1 8] cube still
%                               passes it).
%       'FrameIntervalS' 1.0
%       'MotherRangeM'   900
%       'ApplyVetoes'    true   eclipse + range-ambiguity. Turn OFF only when
%                               the fold IS the thing under test.
%       'CheckVelocityAmbiguity' true  refuse |v| >= v_ua = lambda*PRF/4
%                               (59.958 m/s here). SEPARATE from ApplyVetoes
%                               on purpose: past v_ua the Doppler aliases and
%                               the measured range-rate FLIPS SIGN, so the
%                               phantom self-flags on discriminator screen 2.
%                               Turn OFF only to build that fold deliberately.
%       'SweepSchedule'  []     +1/-1 per frame (radar's actual chirp)
%       'PhantomSweepSchedule' []  what the REPEATER transmits; differs from
%                               the above to model a stale intercept
%       'IncludeAngleChannel' true
%       'SourceAzimuthRad'    0
%       'NoiseAmplitude'      0.05
%       'OutDir'         tempdir
%       'Tag'            'scene'
%
%   WHY IT GOES THROUGH PYTHON. Amplitude and phase are DERIVED by
%   generator/physics_projection.py, which GOVERNANCE.md makes the only path
%   from an action to a renderable scene. Recomputing the 1/R^2 law or the
%   phase progression here would be a second, unpoliced copy of Physics
%   Projection -- exactly the duplication the rebuild exists to remove. So
%   this function marshals and renders; it derives nothing.
%
%   WHAT IT CANNOT DO, STATED SO NOBODY REWIRES A TEST ONTO IT IN VAIN.
%   +generator/render.m has no MICRO-DOPPLER -- no blade-comb rendering
%   anywhere in the rebuild -- so tests/test_drone_models.m stays skipped.
%   That is a CAPABILITY gap in the generator, not a wiring gap in the test,
%   and a helper that faked it would make the test green while measuring
%   nothing. It also has no PER-PHANTOM AZIMUTH, and that one is
%   architectural rather than missing (Blueprint 2.4), which is why
%   tests/test_monopulse_snr_boundary.m cannot be rewired either.
%
%   Swerling fluctuation WAS in that list until 12 Aug 2026 and is now
%   BUILT ('Swerling', 'Seed' above; physics_projection.apply_swerling).
%
%   Replaces engine.entity.render for judge-side tests archived 7 Aug 2026
%   (trash/BROKEN_DOWNSTREAM.md).

    p = inputParser;
    p.addParameter('Rcs', 1.0, @isnumeric);
    p.addParameter('NumFrames', 8, @(x) isscalar(x) && x >= 1);
    p.addParameter('NumPulses', 32, @(x) isscalar(x) && x >= 1);
    p.addParameter('FrameIntervalS', 1.0, @(x) isscalar(x) && x > 0);
    p.addParameter('MotherRangeM', 900, @isscalar);
    % THE PLATFORM'S TRAJECTORY (16 Aug 2026). Supplying a velocity turns
    % MotherRangeM from a standing range into one MotherTrack, from which the
    % builder derives BOTH the causality reference and the bearing series --
    % so a caller can no longer get one right and the other wrong. Leave it
    % empty for the historical stationary platform; nothing moves.
    p.addParameter('MotherVelocityMps', [], @(x) isempty(x) || numel(x) == 3);
    p.addParameter('MotherAzimuthRad', 0, @isscalar);
    p.addParameter('MotherElevationRad', 0, @isscalar);
    % The platform's own skin echo -- what makes the judge's emitter bearing
    % into an emitter POSITION. Off by default: every scene published so far
    % was built without one.
    p.addParameter('IncludePlatformSkinReturn', false, @islogical);
    p.addParameter('PlatformRcs', 0.05, @isscalar);
    % POSITION-SPECIFIED PHANTOMS (16 Aug 2026). [N x 3] offsets and, optional,
    % [N x 3] offset velocities, both RELATIVE TO THE DRONE. Supplying these
    % replaces ranges0M/ratesMps (pass [] for those). The scene is built by
    % generator.physics_projection.project_position, which funnels into the
    % same project_range_series as the action path, so the two authoring
    % styles share every veto and every derivation.
    p.addParameter('PhantomOffsets', [], @(x) isempty(x) || size(x,2) == 3);
    p.addParameter('PhantomOffsetVelocities', [], @(x) isempty(x) || size(x,2) == 3);
    p.addParameter('ApplyVetoes', true, @islogical);
    p.addParameter('SweepSchedule', [], @isnumeric);
    p.addParameter('PhantomSweepSchedule', [], @isnumeric);
    % Passed straight through to generator.render. Default false there,
    % so omitting it keeps every scene in this repo byte-identical.
    p.addParameter('FractionalDelay', false, @islogical);
    % V3 leave-one-out ablation, as a struct with any of the fields
    % constant_amplitude / random_phase / doppler_scale. [] = the genuine arm.
    % Applied inside build_scene AFTER the vetoes, so every arm shares one
    % physically-legal trajectory -- see +experiments/v3Ablation.m.
    p.addParameter('Ablation', [], @(x) isempty(x) || isstruct(x));
    p.addParameter('IncludeAngleChannel', true, @islogical);
    p.addParameter('IncludeElevationChannel', false, @islogical);
    % Scalar (fixed bearing, the historical case) or a per-frame vector -- the
    % mother platform's own azimuth trajectory. See +generator/render.m.
    p.addParameter('SourceAzimuthRad', 0, @isnumeric);
    p.addParameter('SourceElevationRad', 0, @isnumeric);
    p.addParameter('NoiseAmplitude', 0.05, @(x) isscalar(x) && x > 0);
    % Ground clutter. Empty = OFF (the default), which keeps every published
    % scene reproducible sample for sample -- the clutter draw advances the
    % shared RNG stream. -15 dB is rural land at X-band; see
    % +physics/surfaceClutter.m for the derivation and the one cited number.
    p.addParameter('ClutterGammaDB', [], @(x) isempty(x) || isscalar(x));
    p.addParameter('RadarHeightM', 10, @(x) isscalar(x) && x > 0);
    p.addParameter('CheckVelocityAmbiguity', true, @islogical);
    p.addParameter('Swerling', 0, @(x) isscalar(x) && any(x == 0:4));
    p.addParameter('Seed', [], @(x) isempty(x) || isscalar(x));
    p.addParameter('OutDir', tempdir, @(x) ischar(x) || isstring(x));
    p.addParameter('Tag', 'scene', @(x) ischar(x) || isstring(x));
    p.parse(varargin{:});
    o = p.Results;

    % With offsets, the phantom COUNT comes from them and ranges0M/ratesMps
    % must be empty -- the builder refuses both, so broadcast against the
    % offsets instead.
    nPh = numel(ranges0M);
    if ~isempty(o.PhantomOffsets); nPh = size(o.PhantomOffsets, 1); end

    if isscalar(ratesMps)
        ratesMps = repmat(ratesMps, 1, numel(ranges0M));
    end
    rcs = o.Rcs;
    if isscalar(rcs) && ~isempty(o.PhantomOffsets)
        rcs = repmat(rcs, 1, nPh);
    elseif isscalar(rcs)
        rcs = repmat(rcs, 1, numel(ranges0M));
    end

    outDir = char(o.OutDir);
    tag = char(o.Tag);
    preMat = fullfile(outDir, sprintf('%s_plan.mat', tag));
    judgeMat = fullfile(outDir, sprintf('%s_judge.mat', tag));

    if isempty(o.SweepSchedule)
        sweep = py.None;
    else
        sweep = py.list(num2cell(double(o.SweepSchedule)));
    end

    meta = py.generator.tests.build_scene.build( ...
        preMat, ...
        py.list(num2cell(double(ranges0M))), ...
        py.list(num2cell(double(ratesMps))), ...
        pyargs('rcs_m2', py.list(num2cell(double(rcs))), ...
               'num_frames', int32(o.NumFrames), ...
               'num_pulses_per_frame', int32(o.NumPulses), ...
               'frame_interval_s', double(o.FrameIntervalS), ...
               'mother_range_m', double(o.MotherRangeM), ...
               'apply_eclipse_and_ambiguity_vetoes', o.ApplyVetoes, ...
               'sweep_schedule', sweep, ...
               'check_velocity_ambiguity', o.CheckVelocityAmbiguity, ...
               'swerling', int32(o.Swerling), ...
               'seed', localSeedArg(o.Seed), ...
               'mother_velocity_mps', localVelArg(o.MotherVelocityMps), ...
               'mother_azimuth_rad', double(o.MotherAzimuthRad), ...
               'mother_elevation_rad', double(o.MotherElevationRad), ...
               'include_platform_skin_return', o.IncludePlatformSkinReturn, ...
               'platform_rcs_m2', double(o.PlatformRcs), ...
               'phantom_offsets', localOffsetArg(o.PhantomOffsets, ...
                                                  o.PhantomOffsetVelocities, rcs), ...
               'ablation', localAblationArg(o.Ablation)));

    % The bearing handed to render.m comes from the PLATFORM unless the caller
    % overrode it explicitly. Two sources for one quantity is what this is
    % preventing: before, a caller wanting a crossing platform passed a
    % hand-built azimuth series here AND a standing scalar range to the
    % causality veto, and nothing made the two agree.
    srcAz = double(o.SourceAzimuthRad);
    srcEl = double(o.SourceElevationRad);
    if ~ismember('SourceAzimuthRad', p.UsingDefaults)
        % explicit override: the caller owns the bearing (used by tests whose
        % subject IS a bearing the geometry would not produce, e.g. a wrapped
        % one)
    else
        srcAz = cellfun(@double, cell(meta{'source_azimuth_rad'}));
    end
    if ismember('SourceElevationRad', p.UsingDefaults)
        srcEl = cellfun(@double, cell(meta{'source_elevation_rad'}));
    end

    % NumPulses is NOT passed here: render.m reads num_pulses_per_frame out
    % of the .mat the builder just wrote, which is the single source of it.
    renderArgs = {'FractionalDelay', o.FractionalDelay, ...
                  'IncludeAngleChannel', o.IncludeAngleChannel, ...
                  'IncludeElevationChannel', o.IncludeElevationChannel, ...
                  'SourceAzimuthRad', srcAz, ...
                  'SourceElevationRad', srcEl, ...
                  'NoiseAmplitude', double(o.NoiseAmplitude), ...
                  'RadarHeightM', double(o.RadarHeightM)};
    if ~isempty(o.ClutterGammaDB)
        renderArgs = [renderArgs, {'ClutterGammaDB', double(o.ClutterGammaDB)}];
    end
    if ~isempty(o.PhantomSweepSchedule)
        renderArgs = [renderArgs, {'PhantomSweepSchedule', double(o.PhantomSweepSchedule)}];
    end
    generator.render(preMat, judgeMat, renderArgs{:});

    % TRUTH IS RETURNED, NEVER WRITTEN INTO THE JUDGE'S .mat. The judge's
    % emitter backtrack has to MEASURE where the platform is; if the answer
    % were in the file it would be reading it off (Rule 2).
    truth = struct( ...
        'num_frames', double(meta{'num_frames'}), ...
        'frame_interval_s', double(meta{'frame_interval_s'}), ...
        'times_s', cellfun(@double, cell(meta{'times_s'})), ...
        'range_m', localCellToMat(meta{'range_m'}), ...
        'source_azimuth_rad', srcAz, ...
        'source_elevation_rad', srcEl, ...
        'mother_range_m', cellfun(@double, cell(meta{'mother_range_m'})), ...
        'mother_position_xyz_m', localCellToMat(meta{'mother_position_xyz_m'}), ...
        'mother_velocity_mps', cellfun(@double, cell(meta{'mother_velocity_mps'})), ...
        'platform_row', localRowArg(meta{'platform_row'}), ...
        ... % Position-specified scenes only; empty otherwise. What a single
        ... % aperture had to DISCARD to render each requested position.
        'residual_norm_m', localCellToMat(meta{'residual_norm_m'}), ...
        'requested_position_m', localCellToCube(meta{'requested_position_m'}), ...
        'predicted_measured_position_m', localCellToCube(meta{'predicted_measured_position_m'}), ...
        'requested_bearing_rad', localCellToMat(meta{'requested_bearing_rad'}));
end


function A = localCellToCube(pyList)
%LOCALCELLTOCUBE  [nPhantoms x 3 x nFrames] from a nested Python list.
%   Built explicitly rather than with cell2mat for the same singleton-collapse
%   reason localCellToMat documents: a one-phantom scene comes back as a list
%   of length 1 and would be flattened.
    outer = cell(pyList);
    if isempty(outer); A = []; return; end
    firstAxes = cell(outer{1});
    nF = numel(cell(firstAxes{1}));
    A = zeros(numel(outer), 3, nF);
    for i = 1:numel(outer)
        axes_ = cell(outer{i});
        for ax = 1:3
            A(i, ax, :) = cellfun(@double, cell(axes_{ax}));
        end
    end
end


function pl = localOffsetArg(offsets, vels, rcs)
%LOCALOFFSETARG  py.None, or a list of generator.geometry.PhantomOffset.
%   Built here rather than in Python so the MATLAB caller writes plain [N x 3]
%   matrices and never touches a Python constructor.
    if isempty(offsets)
        pl = py.None; return
    end
    n = size(offsets, 1);
    if isempty(vels); vels = zeros(n, 3); end
    assert(size(vels,1) == n, 'renderPhantomScene:offsetVelShape', ...
        '%d offsets but %d offset velocities', n, size(vels,1));
    if isscalar(rcs); rcs = repmat(rcs, 1, n); end
    items = cell(1, n);
    for i = 1:n
        items{i} = py.generator.geometry.PhantomOffset( ...
            pyargs('offset_m', py.tuple(num2cell(double(offsets(i,:)))), ...
                   'offset_velocity_mps', py.tuple(num2cell(double(vels(i,:)))), ...
                   'rcs_m2', double(rcs(min(i, numel(rcs))))));
    end
    pl = py.list(items);
end


function v = localVelArg(v3)
% py.None for "stationary", a 3-list otherwise.
    if isempty(v3)
        v = py.None;
    else
        v = py.list(num2cell(double(v3(:)')));
    end
end


function r = localRowArg(pyVal)
% NaN when there is no platform skin return, so the field always exists and a
% caller tests isnan rather than isfield.
    if isa(pyVal, 'py.NoneType')
        r = NaN;
    else
        r = double(pyVal);
    end
end


function s = localSeedArg(v)
% py.None for "draw fresh", an int otherwise. MATLAB's [] does not marshal
% to Python None on its own.
    if isempty(v)
        s = py.None;
    else
        s = int32(v);
    end
end


function M = localCellToMat(pyList)
% [nPhantoms x nFrames] of true per-frame range. Built row by row rather
% than with cell2mat, because a 1-phantom scene comes back as a nested list
% of length 1 and cell2mat would flatten it to a row vector -- the same
% singleton-collapse class of bug this project has already been bitten by
% twice (jsonencode's 1-element struct array, savemat's struct arrays).
    rows = cell(pyList);
    % EMPTY IS A REAL ANSWER, not an error. The residual fields are empty for
    % every action-specified scene -- one that never asked for a bearing has
    % nothing to have discarded. Omitting this guard indexed rows{1} on an
    % empty cell and broke 50 tests at once, which is how it was found.
    if isempty(rows); M = []; return; end
    M = zeros(numel(rows), numel(cell(rows{1})));
    for k = 1:numel(rows)
        M(k, :) = cellfun(@double, cell(rows{k}));
    end
end

function a = localAblationArg(abl)
%LOCALABLATIONARG  py.None, or a generator.render.Ablation built from a struct.
%   Field names match the dataclass exactly, so an unknown field raises in
%   Python rather than being silently ignored here -- a mis-spelled arm that
%   quietly rendered the genuine one would put a wrong row in the table.
    if isempty(abl)
        a = py.None; return
    end
    kv = {};
    f = fieldnames(abl);
    for i = 1:numel(f)
        v = abl.(f{i});
        if islogical(v); v = logical(v); else; v = double(v); end
        kv = [kv, {f{i}, v}]; %#ok<AGROW>
    end
    a = py.generator.render.Ablation(pyargs(kv{:}));
end
