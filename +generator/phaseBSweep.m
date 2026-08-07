function results = phaseBSweep(fixtureDir, varargin)
%PHASEBSWEEP  Blueprint Phase B: SCRIPTED, non-learned feasibility mapping
%   across the radar family (range-only -> +Doppler -> +monopulse -> +IMM ->
%   +agility). No agent, no learning -- every phantom trajectory is the same
%   physics_projection.project_action call Gate A already validated. What
%   varies is the RADAR's own capability, via +generator/render.m and
%   +engine/runJudge.m's own name-value options.
%
%   results = generator.phaseBSweep(fixtureDir, 'Name', value, ...)
%       fixtureDir : directory containing the fixtures written by
%                    python generator/tests/build_phase_b_scenes.py <fixtureDir>
%
%   Name-value
%       'NumSeeds'  5   Monte-Carlo trials per radar class (Rule 5: N + CI,
%                       never a single run)
%
%   TABLE 1 (single phantom): measures P_confirm(radar_class) for ONE
%   genuine-consistent phantom. The co-bearing screen structurally cannot
%   fire on a single track (it compares tracks to each other), so this table
%   answers "does adding a capability break an otherwise-clean phantom" --
%   NOT the angle wall, which needs >=2 phantoms to exist at all.
%
%   TABLE 2 (two-phantom swarm): the SAME two independently-consistent
%   phantoms, rendered through ONE aperture (Blueprint 2.4 -- this generator
%   has no per-phantom angle parameter), with monopulse off vs on. This is
%   what actually exercises the wall.
%
%   Wilson score interval (not a naive normal approximation, which misbehaves
%   at p near 0 or 1 -- exactly where several of these cells land) for every
%   P_confirm, per Blueprint Rule 5 ("value +/- CI, baseline, N").

    p = inputParser;
    p.addParameter('NumSeeds', 5, @(x) isscalar(x) && x >= 1);
    p.parse(varargin{:});
    numSeeds = p.Results.NumSeeds;

    here = fileparts(fileparts(mfilename('fullpath')));
    addpath(here);

    singlePulseMat = fullfile(fixtureDir, 'phaseB_1phantom_singlepulse.mat');
    cubeMat        = fullfile(fixtureDir, 'phaseB_1phantom_cube.mat');
    agileMat       = fullfile(fixtureDir, 'phaseB_1phantom_agile.mat');
    twoPhantomMat  = fullfile(fixtureDir, 'phaseB_2phantom_cube.mat');

    % ============================ TABLE 1 ================================
    classes = struct('name', {}, 'preRenderMat', {}, 'renderArgs', {}, 'judgeArgs', {});

    classes(end+1) = localClass('range_only', singlePulseMat, ...
        {'IncludeAngleChannel', false}, {});
    classes(end+1) = localClass('plus_doppler', cubeMat, ...
        {'IncludeAngleChannel', false}, {});
    classes(end+1) = localClass('plus_monopulse', cubeMat, ...
        {'IncludeAngleChannel', true}, {});
    classes(end+1) = localClass('plus_imm', cubeMat, ...
        {'IncludeAngleChannel', true}, {'FilterModel', 'imm'});
    % Stale phantom belief (always up-chirp) against a radar that truly
    % alternates -- the ONLY way agility can cost this generator anything,
    % since the default PhantomSweepSchedule is omniscient (+generator/
    % render.m's own header explains why).
    classes(end+1) = localClass('plus_agility', agileMat, ...
        {'IncludeAngleChannel', true, 'PhantomSweepSchedule', ones(1,8)}, ...
        {'FilterModel', 'imm'});

    fprintf('\n=== TABLE 1: single phantom, P_confirm(radar_class), N=%d seeds ===\n', numSeeds);
    fprintf('%-16s %10s %8s %20s\n', 'radar_class', 'P_confirm', 'N', '95% Wilson CI');
    table1 = struct('class', {}, 'pConfirm', {}, 'ciLow', {}, 'ciHigh', {}, 'n', {});
    for i = 1:numel(classes)
        cl = classes(i);
        successes = 0;
        for seed = 1:numSeeds
            rng(seed, 'twister');
            judgeMat = fullfile(fixtureDir, sprintf('phaseB_%s_seed%d_judge.mat', cl.name, seed));
            generator.render(cl.preRenderMat, judgeMat, cl.renderArgs{:});
            fb = engine.runJudge(judgeMat, cl.judgeArgs{:});
            if fb.confirmed_tracks >= 1 && strcmp(fb.eccm_label, 'real')
                successes = successes + 1;
            end
        end
        [pHat, lo, hi] = localWilsonCI(successes, numSeeds);
        fprintf('%-16s %10.2f %8d %20s\n', cl.name, pHat, numSeeds, ...
            sprintf('[%.2f, %.2f]', lo, hi));
        table1(end+1) = struct('class', cl.name, 'pConfirm', pHat, ...
            'ciLow', lo, 'ciHigh', hi, 'n', numSeeds); %#ok<AGROW>
    end

    % ============================ TABLE 2 ================================
    % Two independently-consistent phantoms, monopulse off vs on. Success
    % here means BOTH phantoms confirmed AND labelled 'real' -- a partial
    % survival is not "deception achieved" for a 2-phantom scene.
    fprintf('\n=== TABLE 2: 2-phantom co-located-bearing swarm, N=%d seeds ===\n', numSeeds);
    fprintf('%-16s %10s %8s %20s\n', 'monopulse', 'P_confirm', 'N', '95% Wilson CI');
    angleSettings = [false, true];
    table2 = struct('monopulse', {}, 'pConfirm', {}, 'ciLow', {}, 'ciHigh', {}, 'n', {});
    for i = 1:numel(angleSettings)
        angleOn = angleSettings(i);
        successes = 0;
        for seed = 1:numSeeds
            rng(1000+seed, 'twister');
            judgeMat = fullfile(fixtureDir, sprintf('phaseB_2ph_angle%d_seed%d_judge.mat', angleOn, seed));
            generator.render(twoPhantomMat, judgeMat, 'IncludeAngleChannel', angleOn);
            fb = engine.runJudge(judgeMat);
            bothReal = fb.confirmed_tracks >= 2 && all(strcmp(fb.track_label, 'real'));
            if bothReal
                successes = successes + 1;
            end
        end
        [pHat, lo, hi] = localWilsonCI(successes, numSeeds);
        label = ternary(angleOn, 'monopulse ON', 'monopulse OFF');
        fprintf('%-16s %10.2f %8d %20s\n', label, pHat, numSeeds, sprintf('[%.2f, %.2f]', lo, hi));
        table2(end+1) = struct('monopulse', angleOn, 'pConfirm', pHat, ...
            'ciLow', lo, 'ciHigh', hi, 'n', numSeeds); %#ok<AGROW>
    end

    results = struct('table1', table1, 'table2', table2, 'numSeeds', numSeeds);
end

function cl = localClass(name, preRenderMat, renderArgs, judgeArgs)
    cl = struct('name', name, 'preRenderMat', preRenderMat, ...
        'renderArgs', {renderArgs}, 'judgeArgs', {judgeArgs});
end

function [pHat, lo, hi] = localWilsonCI(successes, n)
%LOCALWILSONCI  95% Wilson score interval -- Blueprint Rule 5 requires a CI
%   on every P_confirm; a naive normal-approximation interval breaks down
%   near p=0 or p=1, which is exactly where several of these small-N cells
%   land. Ref: Wilson (1927); standard closed form, z=1.96 for 95%.
    z = 1.96;
    pHat = successes / n;
    denom = 1 + z^2/n;
    center = (pHat + z^2/(2*n)) / denom;
    halfWidth = (z/denom) * sqrt(pHat*(1-pHat)/n + z^2/(4*n^2));
    lo = max(0, center - halfWidth);
    hi = min(1, center + halfWidth);
end

function s = ternary(cond, a, b)
    if cond; s = a; else; s = b; end
end
