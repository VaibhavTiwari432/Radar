function results = phantomCountSweep(fixtureDir, varargin)
%PHANTOMCOUNTSWEEP  How many simultaneous drone phantoms survive, and how
%   many does the radar flag, as N grows?
%
%   results = generator.phantomCountSweep(fixtureDir, 'Name', value, ...)
%       fixtureDir : directory holding the fixtures written by
%                    python generator/tests/build_n_phantom_scenes.py <dir>
%
%   Name-value
%       'NumSeeds'  5   render-noise trials per cell (Rule 5)
%
%   THREE NUMBERS PER CELL, never one. The archived swarm tests reported a
%   single survivor count, which cannot distinguish "the radar caught them"
%   from "the radar never saw them" -- a distinction this project has been
%   burned by before (the N=8 CEM cell that looked like total ECCM success
%   was actually total detection failure):
%       confirmed  of N transmitted, how many became confirmed tracks
%       flagged    of those, how many the ECCM chain labelled decoy
%       surviving  confirmed AND labelled real -- the only one that is
%                  "deception achieved"
%   surviving = confirmed - flagged by construction, and all three are
%   printed so a zero can be read correctly.
%
%   TWO ARMS (see the builder's header): equal_rcs is a real swarm of
%   identical drones and fades with range; equal_power scales RCS as R^4 so
%   every phantom arrives at the same received power -- the adversary's best
%   case. N=1 is identical in both by construction, which makes it a free
%   consistency check on the whole table.
%
%   MONOPULSE OFF vs ON is the other axis, and it is the point. +generator/
%   render.m takes ONE SourceAzimuthRad per call (Blueprint 2.4), so every
%   phantom in an N-phantom scene is structurally co-bearing -- there is no
%   per-phantom angle parameter to set. With the angle channel on, the
%   co-bearing screen should therefore flag the lot for N >= 2, and cannot
%   fire at all for N = 1 (it compares tracks to each other).

    p = inputParser;
    p.addParameter('NumSeeds', 5, @(x) isscalar(x) && x >= 1);
    p.parse(varargin{:});
    numSeeds = p.Results.NumSeeds;

    here = fileparts(fileparts(mfilename('fullpath')));
    addpath(here);

    nValues = [1 2 4 8];
    arms    = {'equalrcs', 'equalpower'};
    armNames = {'equal RCS (real swarm)', 'equal power (best case)'};
    angleSettings = [false true];

    results = struct('arm', {}, 'n', {}, 'monopulse', {}, ...
                     'confirmed', {}, 'flagged', {}, 'surviving', {}, 'seeds', {});

    for a = 1:numel(arms)
        for angleOn = angleSettings
            fprintf('\n=== %s, monopulse %s, N=%d seeds ===\n', ...
                armNames{a}, ternary(angleOn, 'ON', 'OFF'), numSeeds);
            fprintf('%4s %14s %14s %14s   %s\n', 'N', 'confirmed', 'flagged', 'surviving', 'surv. rate');
            for n = nValues
                fx = fullfile(fixtureDir, sprintf('nphantom_%s_N%d.mat', arms{a}, n));
                cSum = 0; fSum = 0; sSum = 0;
                cAll = zeros(1, numSeeds); sAll = zeros(1, numSeeds);
                for seed = 1:numSeeds
                    rng(seed, 'twister');
                    judgeMat = fullfile(fixtureDir, ...
                        sprintf('nsweep_%s_N%d_a%d_s%d_judge.mat', arms{a}, n, angleOn, seed));
                    generator.render(fx, judgeMat, 'IncludeAngleChannel', angleOn);
                    fb = engine.runJudge(judgeMat);
                    conf = double(fb.confirmed_tracks);
                    flag = double(fb.flagged_decoys);
                    surv = max(0, conf - flag);
                    cSum = cSum + conf; fSum = fSum + flag; sSum = sSum + surv;
                    cAll(seed) = conf; sAll(seed) = surv;
                end
                cM = cSum/numSeeds; fM = fSum/numSeeds; sM = sSum/numSeeds;
                fprintf('%4d %8.2f/%-5d %14.2f %14.2f   %8.0f%%\n', ...
                    n, cM, n, fM, sM, 100*sM/n);
                results(end+1) = struct('arm', arms{a}, 'n', n, 'monopulse', angleOn, ...
                    'confirmed', cM, 'flagged', fM, 'surviving', sM, ...
                    'seeds', struct('confirmed', cAll, 'surviving', sAll)); %#ok<AGROW>
            end
        end
    end
end

function out = ternary(c, a, b)
    if c; out = a; else; out = b; end
end
