function out = ledgerAudit(nEp, seed, outDir)
%LEDGERAUDIT  Emit one provenance ledger per episode from a REAL rollout and
%   audit the whole batch for untagged observables.
%
%   out = experiments.ledgerAudit(nEp, seed, outDir)   % 20, 7, results/episodes
%
%   WHAT THIS ADDS OVER tests/test_provenance_ledger.m. That test proves the
%   CHECKER works, on a hand-built log, in milliseconds -- which is the right
%   place for a structural claim. This runs the real environment, so the
%   ledgers carry real values and any field the environment only creates
%   under particular options (cubeFrames when keepCube, rcsAmp on the
%   Doppler env) is exercised rather than assumed absent. A schema check
%   that never sees the schema actually built is a check of the test's own
%   fixture.
%
%   ONE JSON PER EPISODE, not one big file: the ledger is meant to be the
%   artefact you point a skeptic at for a SPECIFIC emission, and that is
%   awkward if it is buried in a 20-episode array.
%
%   THE JUDGE'S VERDICT IS RECORDED, NOT CONSULTED (CLAUDE.md Rule 2). Each
%   ledger folds in what engine.runJudge decided about that episode's cube
%   alongside what the engine itself believed, so the gap is auditable per
%   emission rather than only as a mean. Nothing in the ledger reaches back
%   into the judge.

    if nargin < 1 || isempty(nEp);  nEp  = 20; end
    if nargin < 2 || isempty(seed); seed = 7;  end
    here = fileparts(mfilename('fullpath'));
    root = fileparts(here);
    if nargin < 3 || isempty(outDir)
        outDir = fullfile(root, 'results', 'episodes');
    end
    if ~isfolder(outDir); mkdir(outDir); end

    C = physics.Constants();
    [env, spec] = agent.buildEnvEntity(C, struct('shaping', false, ...
                        'keepCube', true, 'swerling', 1));
    nVel = numel(spec.velOptionsMps);
    nRcs = numel(spec.rcsOptionsDbsm);
    zeroVel = find(abs(spec.velOptionsMps) < 1e-9);   % see t4JudgeGap's header

    totalUntagged = 0; names = {};
    rng(seed);
    fprintf('ledgerAudit: %d episodes -> %s\n', nEp, outDir);
    for e = 1:nEp
        reset(env);
        vi = zeroVel;
        while vi == zeroVel; vi = randi(nVel); end
        a = sub2ind([nVel nRcs], vi, randi(nRcs));
        lg = [];
        for k = 1:spec.framesPerEpisode
            [~, ~, ~, lg] = step(env, a);          % HELD -- one state, 8 frames
        end

        [jLabel, jConfirmed] = localJudge(lg.cubeFrames, C, spec);
        extra = struct( ...
            'inline_label',    char(lg.eccmLabel), ...
            'judge_label',     char(jLabel), ...
            'judge_confirmed', double(jConfirmed), ...
            'judge_real',      double(jConfirmed && strcmp(char(jLabel), 'real')), ...
            'twin_judge_agree', double(strcmp(char(lg.eccmLabel), char(jLabel))));

        L = assurance.provenanceLedger(lg, extra);
        totalUntagged = totalUntagged + L.untaggedCount;
        names = union(names, L.untagged);

        f = fullfile(outDir, sprintf('episode_%04d_provenance.json', e));
        fid = fopen(f, 'w');
        fwrite(fid, jsonencode(L, 'PrettyPrint', true));
        fclose(fid);
    end

    fprintf('\n  %d ledgers written\n', nEp);
    fprintf('  untagged observables across the batch: %d -> %s\n', totalUntagged, ...
        ternary(totalUntagged == 0, 'PASS', 'FAIL'));
    if totalUntagged > 0
        fprintf('    unregistered: %s\n', strjoin(names, ', '));
    end

    out = struct('nEp', nEp, 'seed', seed, 'outDir', outDir, ...
        'untaggedCount', totalUntagged, 'untaggedNames', {names}, ...
        'pass', totalUntagged == 0);
end

% ------------------------------------------------------------------------
function [label, confirmed] = localJudge(cubeFrames, C, spec)
%LOCALJUDGE  Same call t4JudgeGap/t6JudgeGap/calibrationLog make, so the
%   verdict recorded in a ledger is the one those experiments would report.
    label = ""; confirmed = false;
    if isempty(cubeFrames); return; end
    S = struct('rx_frames', cubeFrames, 'fs', C.fs, ...
        'pulse_width_s', 12e-6, 'bandwidth_hz', 2e6, 'prf_hz', C.PRF, ...
        'frame_interval_s', spec.dt, 'carrier_hz', spec.carrierHz);
    f = [tempname '.mat']; save(f, '-struct', 'S');
    cleanup = onCleanup(@() delete(f)); %#ok<NASGU>
    fb = engine.runJudge(f, 'EccmScreens', {'amplitude', 'doppler'});
    if isfield(fb, 'eccm_label') && strlength(string(fb.eccm_label)) > 0
        confirmed = true;
        label = string(fb.eccm_label);
    end
end

% ------------------------------------------------------------------------
function s = ternary(c, a, b)
    if c; s = a; else; s = b; end
end
