function results = screenAblation(fixtureDir, varargin)
%SCREENABLATION  Per-SCREEN attribution for the radar's ECCM chain, measured
%   on the REBUILT generator (+generator/render.m -> +engine/runJudge.m).
%
%   results = generator.screenAblation(fixtureDir, 'Name', value, ...)
%       fixtureDir : directory holding the fixtures written by
%                    python generator/tests/build_gate_a_scenes.py <dir>
%
%   Name-value
%       'NumSeeds'  5   Monte-Carlo trials per cell (Rule 5: N + CI, never
%                       a single run)
%
%   WHY THIS EXISTS SEPARATELY FROM generator.phaseBSweep. phaseBSweep
%   varies the RADAR CLASS (range-only -> +Doppler -> +monopulse -> +IMM ->
%   +agility) and answers "does adding a capability change the outcome".
%   It cannot say WHICH SCREEN did the work, because every one of its
%   phantoms is genuine-consistent and therefore passes all of them. This
%   function varies the SCREEN MASK against arms that each violate exactly
%   ONE physical law, which is the only way to attribute a flag.
%
%   THE ARMS. Two are deliberate negative controls that BYPASS
%   physics_projection.project_action, because that path structurally
%   cannot emit them -- which is the generator's whole design claim, and
%   also why the judge needs an independent check that it still catches
%   them if handed one directly:
%     genuine        consistent CV phantom, via project_action. The
%                    FALSE-ALARM control: any mask that flags this is
%                    accusing a real target.
%     flat_amplitude range walks, phase correct (screen 2 satisfied),
%                    amplitude held flat -> should be caught by SCREEN 1
%                    alone.
%     zero_doppler   range walks, phase held at zero -> should be caught by
%                    SCREEN 2 alone (the classic pull-off signature).
%     cobearing      two consistent phantoms through ONE aperture -> not a
%                    discriminator screen at all; caught by runJudge's own
%                    co-bearing test, which is multi-track by nature and
%                    cannot fire on any of the three single-phantom arms.
%
%   NO FORKED DISCRIMINATOR (CLAUDE.md Rule 2). The mask goes through
%   engine.runJudge's own 'EccmScreens' option into +track/discriminator.m.
%   Attributing a flag inside a copy of the judge would defeat the point.
%
%   ONE HONEST LIMIT, STATED NOT HIDDEN: 'micro' is in the default mask but
%   gets no dedicated arm here -- these phantoms carry no micro-Doppler
%   modulation, so that screen is uninformative on every row rather than
%   being measured. tests/test_micro_doppler_screen.m covers it directly
%   (5/5) and is the number to quote for it, not any cell below.

    p = inputParser;
    p.addParameter('NumSeeds', 5, @(x) isscalar(x) && x >= 1);
    p.parse(varargin{:});
    numSeeds = p.Results.NumSeeds;

    here = fileparts(fileparts(mfilename('fullpath')));
    addpath(here);

    arms = struct('name', {}, 'mat', {}, 'nPhantoms', {});
    arms(end+1) = struct('name', 'genuine',        'mat', fullfile(fixtureDir, 'gateA_genuine.mat'),            'nPhantoms', 1);
    arms(end+1) = struct('name', 'flat_amplitude', 'mat', fullfile(fixtureDir, 'gateA_flat_amplitude.mat'),     'nPhantoms', 1);
    arms(end+1) = struct('name', 'zero_doppler',   'mat', fullfile(fixtureDir, 'gateA_naive_zero_doppler.mat'), 'nPhantoms', 1);
    arms(end+1) = struct('name', 'cobearing',      'mat', fullfile(fixtureDir, 'gateA_cobearing_pair.mat'),     'nPhantoms', 2);

    % Masks.
    %
    % 'none' MUST NOT be written as {}. engine.runJudge line 519 reads
    % `if ~isempty(opts.EccmScreens)` -- an empty mask means "caller did not
    % specify", so {} silently falls through to the discriminator's OWN
    % default {'amplitude','doppler','micro'}. The first run of this file
    % did exactly that and produced a 'none' row identical to the DEFAULT
    % row, cell for cell, which is how it was caught. A name matching no
    % screen is non-empty, so it survives the guard and disables everything.
    %
    % That row is the floor, and it is not vacuous: with every screen off,
    % discriminator.m scores an empty screen set 0.5 and `> 0.5` is false,
    % so every confirmed track is labelled decoy -- the file's own "nothing
    % here proves this is real should lean suspicious" rule. Expect 1.00
    % everywhere, INCLUDING the genuine arm.
    masks = { {'__no_screens__'}, ...
              {'amplitude'}, ...
              {'doppler'}, ...
              {'amplitude','doppler','micro'}, ...
              {'amplitude','doppler','micro','residual'}, ...
              {'amplitude','doppler','micro'}, ...
              {'amplitude','doppler','micro','maneuver'} };
    maskNames = {'none (floor)', 'amplitude only', 'doppler only', ...
                 'DEFAULT (a+d+micro)', '+residual', ...
                 'DEFAULT, IMM tracker', '+maneuver (IMM)'};
    % The 'maneuver' screen can only score if the tracker is IMM (a plain
    % trackingEKF has no mode probabilities), so its row MUST change the
    % tracker too. That confounds screen with tracker -- hence the
    % 'DEFAULT, IMM tracker' control immediately above it, same tracker,
    % same mask as DEFAULT. Any difference between the last two rows is the
    % SCREEN; any difference between DEFAULT and the control is the TRACKER.
    useImm = [false false false false false true true];

    fprintf('\n=== SCREEN ABLATION: P(flagged), N=%d seeds ===\n', numSeeds);
    fprintf('A screen that never fires or always fires is broken. The genuine\n');
    fprintf('row is the false-alarm control: it should stay at 0.00 everywhere.\n\n');
    fprintf('%-22s', 'mask \ arm');
    for a = 1:numel(arms); fprintf('%16s', arms(a).name); end
    fprintf('\n');

    table = struct('mask', {}, 'arm', {}, 'pFlagged', {}, 'ciLow', {}, 'ciHigh', {}, 'n', {});
    for m = 1:numel(masks)
        fprintf('%-22s', maskNames{m});
        for a = 1:numel(arms)
            flagged = 0;
            for seed = 1:numSeeds
                rng(seed, 'twister');
                judgeMat = fullfile(fixtureDir, sprintf('abl_%s_m%d_s%d_judge.mat', arms(a).name, m, seed));
                if useImm(m)
                    judgeArgs = {'EccmScreens', masks{m}, 'FilterModel', 'imm'};
                else
                    judgeArgs = {'EccmScreens', masks{m}};
                end
                generator.render(arms(a).mat, judgeMat, 'IncludeAngleChannel', true);
                fb = engine.runJudge(judgeMat, judgeArgs{:});
                if fb.confirmed_tracks >= arms(a).nPhantoms && fb.flagged_decoys >= 1
                    flagged = flagged + 1;
                end
            end
            [pHat, lo, hi] = localWilsonCI(flagged, numSeeds);
            fprintf('%16s', sprintf('%.2f [%.2f,%.2f]', pHat, lo, hi));
            table(end+1) = struct('mask', maskNames{m}, 'arm', arms(a).name, ...
                'pFlagged', pHat, 'ciLow', lo, 'ciHigh', hi, 'n', numSeeds); %#ok<AGROW>
        end
        fprintf('\n');
    end

    results = struct('table', table, 'numSeeds', numSeeds, ...
                     'maskNames', {maskNames}, 'armNames', {{arms.name}});
end

function [pHat, lo, hi] = localWilsonCI(s, n)
    z = 1.96; pHat = s / n;
    denom = 1 + z^2/n;
    centre = (pHat + z^2/(2*n)) / denom;
    half = (z/denom) * sqrt(pHat*(1-pHat)/n + z^2/(4*n^2));
    lo = max(0, centre - half); hi = min(1, centre + half);
end
